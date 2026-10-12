import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else {
    fputs("usage: extract input.mp4 output-dir [step-seconds]\n", stderr)
    exit(2)
}
let input = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2])
let step = args.count >= 4 ? Double(args[3])! : 0.5
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let asset = AVAsset(url: input)
let duration = CMTimeGetSeconds(asset.duration)
print(String(format: "duration=%.3f", duration))
let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.requestedTimeToleranceBefore = .zero
gen.requestedTimeToleranceAfter = .zero
let count = Int(ceil(duration / step))
for i in 0...count {
    let t = min(Double(i) * step, max(0, duration - 0.001))
    let time = CMTime(seconds: t, preferredTimescale: 600)
    do {
        let cg = try gen.copyCGImage(at: time, actualTime: nil)
        let url = out.appendingPathComponent(String(format: "frame_%04d_%07.3f.jpg", i, t))
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
    } catch {
        print("failed", i, t, error)
    }
}
