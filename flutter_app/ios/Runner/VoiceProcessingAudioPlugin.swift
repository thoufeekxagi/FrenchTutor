import AVFoundation
import Flutter
import Foundation

/// Small native audio bridge for the V3 Gemini tutor. Input and output share a
/// single AVAudioEngine so VoiceProcessingIO can remove the tutor's own sound
/// while leaving the learner free to interrupt.
final class VoiceProcessingAudioPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let methodName = "com.parlesprint/voice_audio"
  private static let eventName = "com.parlesprint/voice_audio_events"

  private let engineLock = NSRecursiveLock()
  private let micLock = NSLock()
  private let inputRate: Double = 16_000
  private let outputRate: Double = 24_000
  private let outputPlayer = AVAudioPlayerNode()
  private var engine: AVAudioEngine?
  private var converter: AVAudioConverter?
  private var inputPcmFormat: AVAudioFormat?
  private var outputPcmFormat: AVAudioFormat?
  private var outputDeviceFormat: AVAudioFormat?
  private var outputConverter: AVAudioConverter?
  private var captureEnabled = true
  private var eventSink: FlutterEventSink?
  private var testFrameHandler: ((Data) -> Void)?
  private var pendingInput = Data()
  private var tapBufferCount = 0
  private var emittedFrameCount = 0
  private var convertedBufferCount = 0
  private var conversionErrorCount = 0
  private var zeroOutputBufferCount = 0
  private var lastConverterStatus = "not-run"
  private var lastConverterError = ""
  private var lastInputBufferLength = 0
  private var lastInputBufferFormat = ""

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = VoiceProcessingAudioPlugin()
    let method = FlutterMethodChannel(
      name: methodName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: method)

    let events = FlutterEventChannel(
      name: eventName,
      binaryMessenger: registrar.messenger()
    )
    events.setStreamHandler(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      do {
        try startEngine()
        result([
          "voiceProcessingEnabled": engine?.inputNode.isVoiceProcessingEnabled == true,
          "inputSampleRate": inputRate,
          "outputSampleRate": outputRate,
        ])
      } catch {
        stopEngine()
        result(FlutterError(code: "voice_processing_start_failed", message: Self.describe(error), details: nil))
      }
    case "recover":
      do {
        stopEngine()
        try startEngine()
        result([
          "voiceProcessingEnabled": engine?.inputNode.isVoiceProcessingEnabled == true,
          "inputSampleRate": inputRate,
          "outputSampleRate": outputRate,
        ])
      } catch {
        stopEngine()
        result(FlutterError(code: "voice_processing_recovery_failed", message: Self.describe(error), details: nil))
      }
    case "setMicEnabled":
      micLock.lock()
      captureEnabled = (call.arguments as? Bool) ?? false
      micLock.unlock()
      result(nil)
    case "playPcm":
      guard let typed = call.arguments as? FlutterStandardTypedData else {
        result(FlutterError(code: "invalid_pcm", message: "Expected PCM16 bytes", details: nil))
        return
      }
      do {
        try schedulePlayback(typed.data)
        result(nil)
      } catch {
        result(FlutterError(code: "playback_failed", message: error.localizedDescription, details: nil))
      }
    case "stopPlayback":
      stopPlayback()
      result(nil)
    case "debugStatus":
      result(debugStatus())
    case "setOutputVolume":
      let volume = (call.arguments as? NSNumber)?.floatValue ?? 1
      outputPlayer.volume = max(0, min(1, volume))
      result(nil)
    case "stop":
      stopEngine()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func startForTesting(onFrame: @escaping (Data) -> Void) throws {
    micLock.lock()
    testFrameHandler = onFrame
    micLock.unlock()
    try startEngine()
  }

  func schedulePlaybackForTesting(_ bytes: Data) throws {
    try schedulePlayback(bytes)
  }

  var voiceProcessingEnabledForTesting: Bool {
    engine?.inputNode.isVoiceProcessingEnabled == true
  }

  func stopForTesting() {
    stopEngine()
    micLock.lock()
    testFrameHandler = nil
    micLock.unlock()
    eventSink = nil
  }

  private func startEngine() throws {
    engineLock.lock()
    defer { engineLock.unlock() }
    if let engine, engine.isRunning, engine.inputNode.isVoiceProcessingEnabled {
      return
    }
    stopEngineLocked()

    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
    try session.setPreferredIOBufferDuration(0.02)
    try session.setActive(true)

    let newEngine = AVAudioEngine()
    let input = newEngine.inputNode
    try input.setVoiceProcessingEnabled(true)
    let sourceFormat = input.outputFormat(forBus: 0)
    guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
      throw NSError(domain: "ParleSprintVoiceAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "The microphone has no active audio format"])
    }
    guard let targetInputFormat = AVAudioFormat(
      standardFormatWithSampleRate: inputRate,
      channels: 1
    ), let inputConverter = AVAudioConverter(from: sourceFormat, to: targetInputFormat),
      let targetOutputPcmFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: outputRate,
        channels: 1,
        interleaved: false
      ) else {
      throw NSError(domain: "ParleSprintVoiceAudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not configure PCM conversion"])
    }
    let targetOutputDeviceFormat = newEngine.outputNode.inputFormat(forBus: 0)
    guard targetOutputDeviceFormat.sampleRate > 0,
      targetOutputDeviceFormat.channelCount > 0,
      let playbackConverter = AVAudioConverter(from: targetOutputPcmFormat, to: targetOutputDeviceFormat) else {
      throw NSError(domain: "ParleSprintVoiceAudio", code: 6, userInfo: [NSLocalizedDescriptionKey: "Could not configure the device playback format"])
    }

    engine = newEngine
    converter = inputConverter
    inputPcmFormat = targetInputFormat
    outputPcmFormat = targetOutputPcmFormat
    outputDeviceFormat = targetOutputDeviceFormat
    outputConverter = playbackConverter
    pendingInput.removeAll(keepingCapacity: true)
    micLock.lock()
    captureEnabled = true
    micLock.unlock()

    newEngine.attach(outputPlayer)
    newEngine.connect(outputPlayer, to: newEngine.outputNode, format: targetOutputDeviceFormat)
    input.installTap(onBus: 0, bufferSize: 1024, format: sourceFormat) { [weak self] buffer, _ in
      self?.convertAndEmit(buffer)
    }
    newEngine.prepare()
    try newEngine.start()
    guard newEngine.isRunning else {
      throw NSError(
        domain: "ParleSprintVoiceAudio",
        code: 4,
        userInfo: [NSLocalizedDescriptionKey: "AVAudioEngine.start() returned without starting the engine"]
      )
    }
  }

  private func convertAndEmit(_ inputBuffer: AVAudioPCMBuffer) {
    micLock.lock()
    tapBufferCount += 1
    let shouldCapture = captureEnabled
    micLock.unlock()
    engineLock.lock()
    let activeConverter = converter
    let activeInputFormat = inputPcmFormat
    engineLock.unlock()
    guard shouldCapture, let converter = activeConverter, let inputFormat = activeInputFormat,
      let converted = AVAudioPCMBuffer(
        pcmFormat: inputFormat,
        frameCapacity: AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * inputRate / inputBuffer.format.sampleRate) + 32)
      ), let floatSamples = converted.floatChannelData?[0] else { return }

    var suppliedInput = false
    var conversionError: NSError?
    let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
      if suppliedInput {
        inputStatus.pointee = .noDataNow
        return nil
      }
      suppliedInput = true
      inputStatus.pointee = .haveData
      return inputBuffer
    }
    micLock.lock()
    lastConverterStatus = String(describing: status)
    lastInputBufferLength = Int(inputBuffer.frameLength)
    lastInputBufferFormat = String(describing: inputBuffer.format)
    if status == .error {
      conversionErrorCount += 1
      lastConverterError = conversionError?.localizedDescription ?? "unknown conversion error"
    }
    if converted.frameLength == 0 {
      zeroOutputBufferCount += 1
    }
    micLock.unlock()
    guard status != .error, converted.frameLength > 0 else { return }
    micLock.lock()
    convertedBufferCount += 1
    micLock.unlock()

    let byteCount = Int(converted.frameLength) * MemoryLayout<Int16>.size
    var pcmBytes = Data(count: byteCount)
    pcmBytes.withUnsafeMutableBytes { rawBuffer in
      guard let destination = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
      for index in 0..<Int(converted.frameLength) {
        let sample = max(-1.0, min(1.0, Double(floatSamples[index])))
        destination[index] = Int16(clamping: Int((sample * Double(Int16.max)).rounded()))
      }
    }
    let frameBytes = 640 // 20ms at 16kHz, mono, PCM16.
    var outputFrames = [Data]()
    engineLock.lock()
    pendingInput.append(pcmBytes)
    while pendingInput.count >= frameBytes {
      outputFrames.append(Data(pendingInput.prefix(frameBytes)))
      pendingInput.removeFirst(frameBytes)
    }
    engineLock.unlock()
    for frame in outputFrames {
      let payload = FlutterStandardTypedData(bytes: frame)
      micLock.lock()
      let testFrameHandler = self.testFrameHandler
      micLock.unlock()
      if let testFrameHandler {
        testFrameHandler(frame)
        micLock.lock()
        emittedFrameCount += 1
        micLock.unlock()
      } else {
        DispatchQueue.main.async { [weak self] in
          guard let self, let eventSink = self.eventSink else { return }
          eventSink(payload)
          self.micLock.lock()
          self.emittedFrameCount += 1
          self.micLock.unlock()
        }
      }
    }
  }

  func debugStatus() -> [String: Any] {
    engineLock.lock()
    let activeEngine = engine
    let inputFormat = activeEngine?.inputNode.outputFormat(forBus: 0)
    let deviceOutputFormat = outputDeviceFormat
    let converterInputFormat = converter?.inputFormat
    let converterOutputFormat = converter?.outputFormat
    let engineRunning = activeEngine?.isRunning == true
    let voiceProcessingEnabled = activeEngine?.inputNode.isVoiceProcessingEnabled == true
    engineLock.unlock()

    micLock.lock()
    let status: [String: Any] = [
      "engineRunning": engineRunning,
      "voiceProcessingEnabled": voiceProcessingEnabled,
      "inputSampleRate": inputFormat?.sampleRate ?? 0,
      "inputChannels": inputFormat?.channelCount ?? 0,
      "outputSampleRate": deviceOutputFormat?.sampleRate ?? 0,
      "outputChannels": deviceOutputFormat?.channelCount ?? 0,
      "captureEnabled": captureEnabled,
      "eventSinkAttached": eventSink != nil,
      "testFrameHandlerAttached": testFrameHandler != nil,
      "tapBufferCount": tapBufferCount,
      "emittedFrameCount": emittedFrameCount,
      "convertedBufferCount": convertedBufferCount,
      "conversionErrorCount": conversionErrorCount,
      "zeroOutputBufferCount": zeroOutputBufferCount,
      "lastConverterStatus": lastConverterStatus,
      "lastConverterError": lastConverterError,
      "lastInputBufferLength": lastInputBufferLength,
      "lastInputBufferFormat": lastInputBufferFormat,
      "converterInputFormat": converterInputFormat.map { String(describing: $0) } ?? "",
      "converterOutputFormat": converterOutputFormat.map { String(describing: $0) } ?? "",
      "recordPermission": AVAudioSession.sharedInstance().recordPermission.rawValue,
      "routeInputs": AVAudioSession.sharedInstance().currentRoute.inputs.map(\.portType.rawValue),
      "routeOutputs": AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType.rawValue),
      "audioSessionCategory": AVAudioSession.sharedInstance().category.rawValue,
      "audioSessionMode": AVAudioSession.sharedInstance().mode.rawValue,
      "outputPlayerRunning": outputPlayer.isPlaying,
      "applicationState": UIApplication.shared.applicationState.rawValue,
      "otherAudioPlaying": AVAudioSession.sharedInstance().isOtherAudioPlaying,
    ]
    micLock.unlock()
    return status
  }

  private func schedulePlayback(_ bytes: Data) throws {
    engineLock.lock()
    defer { engineLock.unlock() }
    guard engine?.isRunning == true,
      let pcmFormat = outputPcmFormat,
      let deviceFormat = outputDeviceFormat,
      let converter = outputConverter else {
      throw NSError(domain: "ParleSprintVoiceAudio", code: 3, userInfo: [NSLocalizedDescriptionKey: "Audio engine is not running"])
    }
    let evenByteCount = bytes.count - (bytes.count % 2)
    guard evenByteCount > 0,
      let inputBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(evenByteCount / 2)),
      let samples = inputBuffer.int16ChannelData?[0] else { return }
    inputBuffer.frameLength = AVAudioFrameCount(evenByteCount / 2)
    bytes.withUnsafeBytes { rawBuffer in
      if let baseAddress = rawBuffer.baseAddress {
        memcpy(samples, baseAddress, evenByteCount)
      }
    }
    let outputCapacity = AVAudioFrameCount(
      ceil(Double(inputBuffer.frameLength) * deviceFormat.sampleRate / pcmFormat.sampleRate) + 256
    )
    guard let deviceBuffer = AVAudioPCMBuffer(pcmFormat: deviceFormat, frameCapacity: outputCapacity) else {
      throw NSError(domain: "ParleSprintVoiceAudio", code: 7, userInfo: [NSLocalizedDescriptionKey: "Could not allocate a device output buffer"])
    }
    var suppliedInput = false
    var conversionError: NSError?
    let conversionStatus = converter.convert(to: deviceBuffer, error: &conversionError) { _, inputStatus in
      if suppliedInput {
        inputStatus.pointee = .noDataNow
        return nil
      }
      suppliedInput = true
      inputStatus.pointee = .haveData
      return inputBuffer
    }
    guard conversionStatus != .error, deviceBuffer.frameLength > 0 else {
      if conversionStatus == .error {
        throw conversionError ?? NSError(domain: "ParleSprintVoiceAudio", code: 8, userInfo: [NSLocalizedDescriptionKey: "Could not convert tutor audio to the device output format"])
      }
      return
    }
    outputPlayer.scheduleBuffer(deviceBuffer, completionHandler: nil)
    if !outputPlayer.isPlaying {
      outputPlayer.play()
    }
  }

  private func stopPlayback() {
    engineLock.lock()
    defer { engineLock.unlock() }
    guard outputPlayer.engine?.isRunning == true else { return }
    outputPlayer.stop()
    outputPlayer.reset()
  }

  private func stopEngine() {
    engineLock.lock()
    defer { engineLock.unlock() }
    stopEngineLocked()
  }

  private func stopEngineLocked() {
    if let engine {
      engine.inputNode.removeTap(onBus: 0)
      outputPlayer.stop()
      engine.stop()
      engine.detach(outputPlayer)
    }
    engine = nil
    converter = nil
    inputPcmFormat = nil
    outputPcmFormat = nil
    outputDeviceFormat = nil
    outputConverter = nil
    pendingInput.removeAll(keepingCapacity: false)
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private static func describe(_ error: Error) -> String {
    let nsError = error as NSError
    return "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
  }
}
