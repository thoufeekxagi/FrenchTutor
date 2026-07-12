import Foundation
import AVFoundation

class AudioService: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var recordingURL: URL?
    private var stopCompletion: ((Data?) -> Void)?

    var isRecording: Bool { recorder?.isRecording ?? false }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true)

        let docsDir = FileManager.default.temporaryDirectory
        let filename = "recording_\(Int(Date().timeIntervalSince1970)).wav"
        let url = docsDir.appendingPathComponent(filename)
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.delegate = self
        recorder?.record()
    }

    func stopRecording(completion: @escaping (Data?) -> Void) {
        stopCompletion = completion
        recorder?.stop()
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard flag, let url = recordingURL else {
            stopCompletion?(nil)
            stopCompletion = nil
            return
        }
        do {
            let data = try Data(contentsOf: url)
            stopCompletion?(data)
        } catch {
            stopCompletion?(nil)
        }
        stopCompletion = nil
    }

    func playAudioData(_ data: Data) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)

                self.player = try AVAudioPlayer(data: data)
                self.player?.play()
            } catch {
                print("Audio playback error: \(error)")
            }
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
    }
}
