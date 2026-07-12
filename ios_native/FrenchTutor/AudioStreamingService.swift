import Foundation
import AVFoundation

class AudioStreamingService: NSObject {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private var inputConverter: AVAudioConverter?
    private var outputConverter: AVAudioConverter?

    private let geminiOutputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: false)!
    private let geminiInputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!

    private var isStreaming = false
    private var audioChunkCallback: ((Data) -> Void)?
    private var isEngineSetup = false
    private var micChunkCount = 0

    // While true, captured mic audio is not forwarded via audioChunkCallback.
    // Used to prevent the mic from picking up the tutor's own speaker output
    // and feeding it back to Gemini as an echo, since we don't use built-in
    // voice processing (which would degrade output audio quality).
    var isOutputActive = false

    private var isPlayerAttached = false
    private var playerConnectFormat: AVAudioFormat?

    override init() {
        super.init()
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigurationChange(_:)),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    // Handles ALL dynamic audio route changes: Bluetooth earpiece/speaker
    // connect or disconnect, wired headset plug/unplug, CarPlay, AirPlay, etc.
    // The hardware sample rate/channel count can change with the new route,
    // so the engine graph (tap format, mixer connection format) must be
    // rebuilt to match, otherwise AVAudioEngine hard-crashes on format
    // mismatch.
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        print("AudioStreamingService: route changed reason=\(reason.rawValue)")

        // NOTE: .categoryChange is deliberately excluded. We call
        // setCategory/setActive ourselves inside configureSession(), which
        // itself generates a .categoryChange notification. Reacting to it
        // here would create an infinite rebuild loop (rebuild → reconfigure
        // session → categoryChange notification → rebuild → ...).
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .routeConfigurationChange, .override:
            rebuildAudioGraphIfNeeded()
        default:
            break
        }
    }

    @objc private func handleEngineConfigurationChange(_ notification: Notification) {
        print("AudioStreamingService: engine configuration changed")
        rebuildAudioGraphIfNeeded()
    }

    @objc private func handleMediaServicesReset(_ notification: Notification) {
        print("AudioStreamingService: media services were reset")
        isEngineSetup = false
        isPlayerAttached = false
        rebuildAudioGraphIfNeeded()
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .ended {
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                rebuildAudioGraphIfNeeded()
            }
        }
    }

    // Tears down and rebuilds the entire audio graph in-place, preserving
    // whether streaming was active so the mic and tutor audio keep working
    // seamlessly across Bluetooth earpiece, Bluetooth speaker, wired
    // headphones, AirPlay, or built-in speaker/mic — the same way a normal
    // phone call handles route changes.
    private var isRebuildingGraph = false
    private var rebuildPending = false

    private func rebuildAudioGraphIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Coalesce rapid, overlapping notifications (route change +
            // engine configuration change often fire back-to-back) into a
            // single rebuild instead of stacking concurrent rebuilds.
            if self.isRebuildingGraph {
                self.rebuildPending = true
                return
            }
            self.isRebuildingGraph = true

            let wasStreaming = self.isStreaming
            let callback = self.audioChunkCallback

            self.engine.inputNode.removeTap(onBus: 0)
            self.playerNode.stop()
            self.engine.stop()
            self.isEngineSetup = false
            self.isStreaming = false

            do {
                try self.configureSession()
            } catch {
                print("AudioStreamingService: failed to reconfigure session after route change: \(error.localizedDescription)")
            }

            if wasStreaming, let callback = callback {
                do {
                    try self.startStreaming(onChunk: callback)
                    print("AudioStreamingService: successfully rebuilt audio graph after route change")
                } catch {
                    print("AudioStreamingService: failed to restart streaming after route change: \(error.localizedDescription)")
                }
            }

            self.isRebuildingGraph = false
            if self.rebuildPending {
                self.rebuildPending = false
                self.rebuildAudioGraphIfNeeded()
            }
        }
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(48000)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)
    }

    private func setupEngineIfNeeded() throws {
        guard !isEngineSetup else { return }
        try configureSession()

        // Must access inputNode BEFORE building the output chain, otherwise
        // AVAudioEngine never configures itself for input and inputNode's
        // format stays stuck at 0 Hz / 0 channels permanently.
        let inputNode = engine.inputNode
        print("AudioStreamingService: inputNode format at setup=\(inputNode.outputFormat(forBus: 0))")

        // NOTE: We intentionally do NOT enable AVAudioInputNode's built-in
        // voice processing here. It does provide echo cancellation, but it
        // also forces telephony-grade audio (mono, bandwidth-limited, AGC
        // artifacts) on both input AND output, degrading playback quality.
        // Instead, echo is avoided by gating mic uploads while the tutor is
        // speaking (see `isOutputActive`), which preserves full audio quality.
        //
        // Only force the built-in speaker when there is no external route
        // (Bluetooth earpiece/speaker, wired headset, AirPlay, CarPlay)
        // already selected. Forcing .speaker unconditionally fights the
        // system's Bluetooth routing and triggers a route-change loop
        // (override → Bluetooth reclaims route → route-change notification →
        // override again), which is what caused crashes when connecting a
        // Bluetooth earpiece.
        applySpeakerOverrideIfNoExternalRoute()

        let outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        if !isPlayerAttached {
            engine.attach(playerNode)
            isPlayerAttached = true
        }
        engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)
        // Cache the exact format used for this connection. playerNode's
        // fixed output format is whatever we pass to connect() here — it
        // does NOT automatically track later changes to
        // mainMixerNode.outputFormat(forBus:). Buffers scheduled on
        // playerNode must always match this cached format exactly, or
        // AVAudioEngine crashes with a channelCount mismatch.
        playerConnectFormat = outputFormat
        engine.prepare()
        isEngineSetup = true
    }

    // Returns true if the current audio route includes an external output
    // device the user explicitly connected (Bluetooth, wired headset,
    // AirPlay, CarPlay, HDMI). In that case we should leave routing to the
    // system rather than forcing the built-in speaker.
    private func hasExternalOutputRoute() -> Bool {
        let externalPortTypes: Set<AVAudioSession.Port> = [
            .bluetoothA2DP, .bluetoothHFP,
            .headphones, .airPlay, .carAudio, .HDMI, .usbAudio
        ]
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.contains { externalPortTypes.contains($0.portType) }
    }

    private func applySpeakerOverrideIfNoExternalRoute() {
        guard !hasExternalOutputRoute() else {
            print("AudioStreamingService: external route active, leaving routing to system")
            return
        }
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
        } catch {
            print("AudioStreamingService: failed to override to speaker: \(error.localizedDescription)")
        }
    }

    enum AudioStreamingError: Error {
        case invalidInputFormat
    }

    func startStreaming(onChunk: @escaping (Data) -> Void) throws {
        guard !isStreaming else { return }
        audioChunkCallback = onChunk
        inputConverter = nil

        try setupEngineIfNeeded()

        let inputNode = engine.inputNode
        let bufferSize: UInt32 = 4096
        let nodeFormat = inputNode.outputFormat(forBus: 0)
        print("AudioStreamingService: node inputFormat=\(nodeFormat)")

        var tapFormat = nodeFormat
        if tapFormat.sampleRate <= 0 || tapFormat.channelCount == 0 {
            let session = AVAudioSession.sharedInstance()
            let sampleRate = session.sampleRate > 0 ? session.sampleRate : 48000
            let channels = AVAudioChannelCount(max(session.inputNumberOfChannels, 1))
            guard let fallback = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false) else {
                throw AudioStreamingError.invalidInputFormat
            }
            tapFormat = fallback
            print("AudioStreamingService: node format invalid, using session-based fallback format=\(tapFormat)")
        }

        print("AudioStreamingService: installing tap with format=\(tapFormat)")
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: tapFormat) { [weak self] buffer, _ in
            self?.processInputBuffer(buffer)
        }

        do {
            try engine.start()
            print("AudioStreamingService: engine started, isRunning=\(engine.isRunning)")
        } catch {
            print("AudioStreamingService: engine.start() failed: \(error.localizedDescription)")
            throw error
        }

        applySpeakerOverrideIfNoExternalRoute()

        playerNode.play()
        isStreaming = true
    }

    func stopStreaming() {
        guard isStreaming else { return }
        isStreaming = false

        engine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        engine.stop()
        audioChunkCallback = nil
    }

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer) {
        if inputConverter == nil {
            inputConverter = AVAudioConverter(from: buffer.format, to: geminiInputFormat)
        }
        guard let converter = inputConverter else { return }

        let inputFrameCount = buffer.frameLength
        let outputFrameCount = AVAudioFrameCount(Double(inputFrameCount) * geminiInputFormat.sampleRate / buffer.format.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: geminiInputFormat, frameCapacity: outputFrameCount) else { return }

        var inputBufferConsumed = false
        var error: NSError?

        converter.convert(to: outputBuffer, error: &error) { _, status in
            if !inputBufferConsumed {
                inputBufferConsumed = true
                status.pointee = AVAudioConverterInputStatus.haveData
                return buffer
            } else {
                status.pointee = AVAudioConverterInputStatus.noDataNow
                return nil
            }
        }

        if let error = error {
            print("AudioStreamingService: input conversion error: \(error.localizedDescription)")
            return
        }

        guard let int16Data = outputBuffer.int16ChannelData?[0] else { return }
        let frameLength = Int(outputBuffer.frameLength)
        let byteCount = frameLength * MemoryLayout<Int16>.size
        let data = Data(bytes: int16Data, count: byteCount)

        guard !isOutputActive else { return }

        micChunkCount += 1
        if micChunkCount == 1 || micChunkCount % 10 == 0 {
            var maxAmp: Int16 = 0
            for i in 0..<frameLength {
                maxAmp = max(maxAmp, abs(int16Data[i]))
            }
            print("AudioStreamingService: mic chunk #\(micChunkCount) bytes=\(byteCount) maxAmp=\(maxAmp) srcFormat=\(buffer.format)")
        }

        audioChunkCallback?(data)
    }

    func playAudioChunk(_ data: Data) {
        do {
            try setupEngineIfNeeded()
        } catch {
            print("AudioStreamingService: setup failed: \(error.localizedDescription)")
            return
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("AudioStreamingService: failed to start engine: \(error.localizedDescription)")
                return
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }

        guard let buffer = convertGeminiAudioToEngineFormat(data) else { return }

        // Final safety check: playerNode's live output format must exactly
        // match the buffer we're about to schedule, regardless of which
        // device (Bluetooth earpiece, Bluetooth speaker, wired headphones,
        // built-in speaker) is currently active. If a route change slipped
        // in between conversion and scheduling, drop this chunk and let the
        // route-change rebuild handle reconnecting rather than crashing.
        let liveFormat = playerNode.outputFormat(forBus: 0)
        guard liveFormat.channelCount == buffer.format.channelCount,
              liveFormat.sampleRate == buffer.format.sampleRate else {
            print("AudioStreamingService: dropping chunk, format mismatch live=\(liveFormat) buffer=\(buffer.format)")
            return
        }

        playerNode.scheduleBuffer(buffer)
    }

    private func convertGeminiAudioToEngineFormat(_ data: Data) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frameCount > 0 else { return nil }

        // Must use the exact format playerNode was connected with, NOT a
        // fresh query of mainMixerNode.outputFormat(forBus:). The mixer's
        // reported format can change immediately after a route switch
        // (Bluetooth earpiece/speaker, wired headset, built-in speaker),
        // but playerNode's actual output format stays fixed until we
        // explicitly reconnect it. Using a stale/mismatched format here is
        // what caused the hard crash on channelCount mismatch.
        guard let engineFormat = playerConnectFormat else {
            print("AudioStreamingService: no cached player connect format, dropping chunk")
            return nil
        }

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: geminiOutputFormat, frameCapacity: frameCount),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: engineFormat, frameCapacity: AVAudioFrameCount(Double(frameCount) * engineFormat.sampleRate / geminiOutputFormat.sampleRate)) else {
            return nil
        }

        inputBuffer.frameLength = frameCount
        data.withUnsafeBytes { rawBuffer in
            if let int16Data = inputBuffer.int16ChannelData?[0] {
                let src = rawBuffer.bindMemory(to: Int16.self)
                for i in 0..<Int(frameCount) {
                    int16Data[i] = src[i]
                }
            }
        }

        guard let converter = AVAudioConverter(from: geminiOutputFormat, to: engineFormat) else {
            print("AudioStreamingService: failed to create converter to \(engineFormat), dropping chunk")
            return nil
        }

        var inputBufferConsumed = false
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, status in
            if !inputBufferConsumed {
                inputBufferConsumed = true
                status.pointee = AVAudioConverterInputStatus.haveData
                return inputBuffer
            } else {
                status.pointee = AVAudioConverterInputStatus.noDataNow
                return nil
            }
        }

        guard error == nil else {
            print("AudioStreamingService: output conversion error: \(error!.localizedDescription), dropping chunk")
            return nil
        }

        // Never fall back to returning `inputBuffer` in its original
        // (geminiOutputFormat) format — its channel count/sample rate may
        // not match playerNode's fixed output format and would crash
        // scheduleBuffer.
        return outputBuffer
    }

    func stopPlayback() {
        playerNode.stop()
    }

    func setSpeakerEnabled(_ enabled: Bool) {
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(enabled ? .speaker : .none)
        } catch {
            print("AudioStreamingService: failed to set speaker enabled=\(enabled): \(error.localizedDescription)")
        }
    }
}
