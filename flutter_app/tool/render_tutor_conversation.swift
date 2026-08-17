import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    fputs("usage: render_tutor_conversation <frames-dir> <audio-manifest> <output.mp4>\n", stderr)
    exit(2)
}

let framesDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let manifestURL = URL(fileURLWithPath: arguments[2])
let outputURL = URL(fileURLWithPath: arguments[3])
let videoOnlyURL = outputURL.deletingPathExtension().appendingPathExtension("video.mov")
let fileManager = FileManager.default

try? fileManager.removeItem(at: outputURL)
try? fileManager.removeItem(at: videoOnlyURL)

let frameURLs = try fileManager.contentsOfDirectory(
    at: framesDirectory,
    includingPropertiesForKeys: nil,
    options: [.skipsHiddenFiles]
).filter { $0.pathExtension.lowercased() == "png" }
.sorted { $0.lastPathComponent < $1.lastPathComponent }

guard let firstFrameURL = frameURLs.first,
      let firstSource = CGImageSourceCreateWithURL(firstFrameURL as CFURL, nil),
      let firstImage = CGImageSourceCreateImageAtIndex(firstSource, 0, nil) else {
    throw NSError(domain: "TutorConversationDemo", code: 1, userInfo: [NSLocalizedDescriptionKey: "No renderable frames found"])
}

let width = firstImage.width
let height = firstImage.height
let writer = try AVAssetWriter(outputURL: videoOnlyURL, fileType: .mov)
let videoInput = AVAssetWriterInput(
    mediaType: .video,
    outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 2_800_000,
            AVVideoExpectedSourceFrameRateKey: 30,
        ],
    ]
)
videoInput.expectsMediaDataInRealTime = false
guard writer.canAdd(videoInput) else {
    throw NSError(domain: "TutorConversationDemo", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
}
writer.add(videoInput)

let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: videoInput,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
    ]
)

func pixelBuffer(from imageURL: URL) -> CVPixelBuffer? {
    guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return nil
    }
    var buffer: CVPixelBuffer?
    let attributes: CFDictionary = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true,
    ] as CFDictionary
    guard CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attributes,
        &buffer
    ) == kCVReturnSuccess,
    let buffer else {
        return nil
    }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(buffer),
          let context = CGContext(
              data: baseAddress,
              width: width,
              height: height,
              bitsPerComponent: 8,
              bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
          ) else {
        return nil
    }

    context.setFillColor(CGColor(gray: 0.97, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return buffer
}

guard writer.startWriting() else {
    throw writer.error ?? NSError(domain: "TutorConversationDemo", code: 3)
}
writer.startSession(atSourceTime: .zero)

let frameQueue = DispatchQueue(label: "tutor-conversation-video")
let videoGroup = DispatchGroup()
videoGroup.enter()
var frameIndex = 0
videoInput.requestMediaDataWhenReady(on: frameQueue) {
    while videoInput.isReadyForMoreMediaData && frameIndex < frameURLs.count {
        guard let buffer = pixelBuffer(from: frameURLs[frameIndex]) else {
            videoInput.markAsFinished()
            writer.cancelWriting()
            videoGroup.leave()
            return
        }
        let time = CMTime(value: CMTimeValue(frameIndex), timescale: 30)
        if !adaptor.append(buffer, withPresentationTime: time) {
            videoInput.markAsFinished()
            writer.cancelWriting()
            videoGroup.leave()
            return
        }
        frameIndex += 1
    }
    if frameIndex == frameURLs.count {
        videoInput.markAsFinished()
        writer.finishWriting {
            videoGroup.leave()
        }
    }
}
videoGroup.wait()

guard writer.status == .completed else {
    throw writer.error ?? NSError(domain: "TutorConversationDemo", code: 4, userInfo: [NSLocalizedDescriptionKey: "Video writer failed"])
}

let composition = AVMutableComposition()
let videoAsset = AVURLAsset(url: videoOnlyURL)
guard let sourceVideo = videoAsset.tracks(withMediaType: .video).first,
      let compositionVideo = composition.addMutableTrack(
          withMediaType: .video,
          preferredTrackID: kCMPersistentTrackID_Invalid
      ) else {
    throw NSError(domain: "TutorConversationDemo", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cannot compose video"])
}
try compositionVideo.insertTimeRange(
    CMTimeRange(start: .zero, duration: videoAsset.duration),
    of: sourceVideo,
    at: .zero
)

let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
for line in manifest.split(whereSeparator: \.isNewline) {
    let fields = line.split(separator: "\t", maxSplits: 1).map(String.init)
    guard fields.count == 2 else { continue }
    let audioURL = URL(fileURLWithPath: fields[0])
    let startSeconds = Double(fields[1]) ?? 0
    let audioAsset = AVURLAsset(url: audioURL)
    guard let sourceAudio = audioAsset.tracks(withMediaType: .audio).first,
          let compositionAudio = composition.addMutableTrack(
              withMediaType: .audio,
              preferredTrackID: kCMPersistentTrackID_Invalid
          ) else { continue }
    try compositionAudio.insertTimeRange(
        CMTimeRange(start: .zero, duration: audioAsset.duration),
        of: sourceAudio,
        at: CMTime(seconds: startSeconds, preferredTimescale: 600)
    )
}

guard let exporter = AVAssetExportSession(
    asset: composition,
    presetName: AVAssetExportPresetHighestQuality
) else {
    throw NSError(domain: "TutorConversationDemo", code: 6, userInfo: [NSLocalizedDescriptionKey: "Cannot create MP4 exporter"])
}
exporter.outputURL = outputURL
exporter.outputFileType = .mp4
exporter.shouldOptimizeForNetworkUse = true

let exportGroup = DispatchGroup()
exportGroup.enter()
exporter.exportAsynchronously {
    exportGroup.leave()
}
exportGroup.wait()

guard exporter.status == .completed else {
    throw exporter.error ?? NSError(domain: "TutorConversationDemo", code: 7, userInfo: [NSLocalizedDescriptionKey: "MP4 export failed"])
}

print(outputURL.path)
