import Flutter
import AVFoundation
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

  func testPlainAudioEngineDeliversMicTap() throws {
    let session = AVAudioSession.sharedInstance()
    if session.recordPermission != .granted {
      let permissionPrompt = expectation(description: "microphone permission resolved")
      session.requestRecordPermission { _ in permissionPrompt.fulfill() }
      wait(for: [permissionPrompt], timeout: 30)
    }
    XCTAssertEqual(session.recordPermission, .granted)
    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
    try session.setActive(true)

    let engine = AVAudioEngine()
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    let firstBuffer = expectation(description: "plain input tap buffer")
    firstBuffer.assertForOverFulfill = false
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { _, _ in
      firstBuffer.fulfill()
    }
    engine.prepare()
    try engine.start()
    defer {
      input.removeTap(onBus: 0)
      engine.stop()
      try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    let waitResult = XCTWaiter.wait(for: [firstBuffer], timeout: 5)
    XCTAssertEqual(
      waitResult,
      .completed,
      "Plain AVAudioEngine input produced no tap buffer; appState=\(UIApplication.shared.applicationState.rawValue), running=\(engine.isRunning), permission=\(session.recordPermission.rawValue), route=\(session.currentRoute.inputs.map(\.portType.rawValue))"
    )
    XCTAssertTrue(engine.isRunning)
  }

  func testVoiceProcessingInputNodeDeliversMicTapWithoutPlaybackGraph() throws {
    let session = AVAudioSession.sharedInstance()
    XCTAssertEqual(session.recordPermission, .granted)
    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
    try session.setActive(true)

    let engine = AVAudioEngine()
    let input = engine.inputNode
    try input.setVoiceProcessingEnabled(true)
    let format = input.outputFormat(forBus: 0)
    let firstBuffer = expectation(description: "voice-processed input tap buffer")
    firstBuffer.assertForOverFulfill = false
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { _, _ in
      firstBuffer.fulfill()
    }
    engine.prepare()
    try engine.start()
    defer {
      input.removeTap(onBus: 0)
      engine.stop()
      try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    let waitResult = XCTWaiter.wait(for: [firstBuffer], timeout: 5)
    XCTAssertEqual(
      waitResult,
      .completed,
      "VoiceProcessingIO input produced no tap buffer; appState=\(UIApplication.shared.applicationState.rawValue), running=\(engine.isRunning), VPIO=\(input.isVoiceProcessingEnabled), permission=\(session.recordPermission.rawValue), route=\(session.currentRoute.inputs.map(\.portType.rawValue))"
    )
    XCTAssertTrue(engine.isRunning)
  }

  func testVoiceProcessingDirectHardwareOutputNodeCaptures() throws {
    let session = AVAudioSession.sharedInstance()
    XCTAssertEqual(session.recordPermission, .granted)
    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
    try session.setPreferredIOBufferDuration(0.02)
    try session.setActive(true)

    let engine = AVAudioEngine()
    let input = engine.inputNode
    try input.setVoiceProcessingEnabled(true)
    let inputFormat = input.outputFormat(forBus: 0)
    let outputFormat = engine.outputNode.inputFormat(forBus: 0)
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.outputNode, format: outputFormat)
    let firstBuffer = expectation(description: "VoiceProcessingIO with player graph tap buffer")
    firstBuffer.assertForOverFulfill = false
    input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { _, _ in
      firstBuffer.fulfill()
    }
    engine.prepare()
    try engine.start()
    defer {
      input.removeTap(onBus: 0)
      engine.stop()
      engine.detach(player)
      try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    let waitResult = XCTWaiter.wait(for: [firstBuffer], timeout: 5)
    XCTAssertEqual(
      waitResult,
      .completed,
      "VoiceProcessingIO with direct hardware output graph produced no tap buffer; appState=\(UIApplication.shared.applicationState.rawValue), running=\(engine.isRunning), VPIO=\(input.isVoiceProcessingEnabled), permission=\(session.recordPermission.rawValue), route=\(session.currentRoute.inputs.map(\.portType.rawValue))"
    )
    XCTAssertTrue(engine.isRunning)
  }

  func testVoiceProcessingCapturesDuringSharedEnginePlayback() throws {
    let session = AVAudioSession.sharedInstance()
    if session.recordPermission != .granted {
      let permissionPrompt = expectation(description: "microphone permission resolved")
      session.requestRecordPermission { _ in permissionPrompt.fulfill() }
      wait(for: [permissionPrompt], timeout: 30)
    }
    XCTAssertEqual(session.recordPermission, .granted, "iOS microphone permission is required: \(session.recordPermission.rawValue)")

    let plugin = VoiceProcessingAudioPlugin()
    let firstFrame = expectation(description: "voice-processed mic frame")
    let frameDuringPlayback = expectation(description: "mic stays live during tutor audio")
    let stateLock = NSLock()
    var playbackStarted = false
    var firstFrameSeen = false
    var playbackFrameSeen = false

    try plugin.startForTesting { frame in
      guard frame.count == 640 else { return }
      stateLock.lock()
      let expectationToFulfill: XCTestExpectation?
      if playbackStarted, !playbackFrameSeen {
        playbackFrameSeen = true
        expectationToFulfill = frameDuringPlayback
      } else if !playbackStarted, !firstFrameSeen {
        firstFrameSeen = true
        expectationToFulfill = firstFrame
      } else {
        expectationToFulfill = nil
      }
      stateLock.unlock()
      expectationToFulfill?.fulfill()
    }
    defer { plugin.stopForTesting() }

    XCTAssertTrue(plugin.voiceProcessingEnabledForTesting)
    let initialStatus = plugin.debugStatus()
    XCTAssertEqual(
      initialStatus["engineRunning"] as? Bool,
      true,
      "The shared AVAudioEngine did not stay running: \(initialStatus)"
    )
    XCTAssertEqual(
      initialStatus["testFrameHandlerAttached"] as? Bool,
      true,
      "The native test frame handler did not attach: \(initialStatus)"
    )
    guard initialStatus["engineRunning"] as? Bool == true else { return }

    let firstFrameResult = XCTWaiter.wait(for: [firstFrame], timeout: 5)
    let captureStatus = plugin.debugStatus()
    guard firstFrameResult == .completed else {
      XCTFail("No native mic frame arrived; audio state: \(captureStatus)")
      return
    }

    try plugin.schedulePlaybackForTesting(testTone())
    XCTAssertEqual(plugin.debugStatus()["outputPlayerRunning"] as? Bool, true)
    Thread.sleep(forTimeInterval: 0.05)
    stateLock.lock()
    playbackStarted = true
    stateLock.unlock()
    let playbackFrameResult = XCTWaiter.wait(for: [frameDuringPlayback], timeout: 3)
    XCTAssertEqual(
      playbackFrameResult,
      .completed,
      "The mic must stay live while the shared engine plays tutor audio: \(plugin.debugStatus())"
    )
  }

  func testVoiceProcessingAcousticCaptureRecordsMacSpeakerAudio() throws {
    let session = AVAudioSession.sharedInstance()
    if session.recordPermission != .granted {
      let permissionPrompt = expectation(description: "microphone permission resolved")
      session.requestRecordPermission { _ in permissionPrompt.fulfill() }
      wait(for: [permissionPrompt], timeout: 30)
    }
    guard session.recordPermission == .granted else {
      XCTFail("iOS microphone permission is required: \(session.recordPermission.rawValue)")
      return
    }

    let plugin = VoiceProcessingAudioPlugin()
    let captureLock = NSLock()
    var capturedPcm = Data()
    var frameCount = 0
    let captureStartedAt = Date()
    try plugin.startForTesting { frame in
      guard frame.count == 640 else { return }
      captureLock.lock()
      capturedPcm.append(frame)
      frameCount += 1
      captureLock.unlock()
    }
    defer { plugin.stopForTesting() }

    XCTAssertTrue(plugin.voiceProcessingEnabledForTesting)
    XCTAssertEqual(plugin.debugStatus()["engineRunning"] as? Bool, true)

    // Start Mac speaker playback a few seconds after launching this test. The
    // long capture window also tolerates the device-test runner's launch time.
    Thread.sleep(forTimeInterval: 2)
    NSLog("PARLESPRINT_ACOUSTIC_CAPTURE_READY")
    Thread.sleep(forTimeInterval: 42)

    captureLock.lock()
    let pcm = capturedPcm
    let capturedFrameCount = frameCount
    captureLock.unlock()

    XCTAssertGreaterThan(capturedFrameCount, 1_000, "The iPhone should capture at least 20 seconds of 20 ms PCM frames")
    XCTAssertEqual(pcm.count, capturedFrameCount * 640)
    let metrics = acousticMetrics(for: pcm)
    XCTAssertGreaterThan(metrics.nonzeroSamples, 1_000, "The iPhone emitted silent PCM; mic permission or routing is still blocking capture. Metrics: \(metrics)")
    XCTAssertGreaterThan(metrics.maximumGateLevel, 0.04, "The Mac speaker speech did not reach the local speech gate. Metrics: \(metrics)")
    XCTAssertGreaterThan(metrics.speechStarts, 0, "The local VAD did not open on Mac speaker speech. Metrics: \(metrics)")

    let pcmAttachment = XCTAttachment(data: pcm, uniformTypeIdentifier: "public.data")
    pcmAttachment.name = "iPhone-voice-processed-16k-mono-pcm-s16le.raw"
    pcmAttachment.lifetime = .keepAlways
    add(pcmAttachment)

    let status = plugin.debugStatus()
    let report = """
    capturedFrames=\(capturedFrameCount)
    frameBytes=640
    sampleRate=16000
    startedAtUnix=\(captureStartedAt.timeIntervalSince1970)
    endedAtUnix=\(Date().timeIntervalSince1970)
    pcmMetrics=\(metrics)
    voiceProcessingEnabled=\(plugin.voiceProcessingEnabledForTesting)
    audioStatus=\(status)
    """
    let reportAttachment = XCTAttachment(data: Data(report.utf8), uniformTypeIdentifier: "public.plain-text")
    reportAttachment.name = "iPhone-acoustic-capture-report.txt"
    reportAttachment.lifetime = .keepAlways
    add(reportAttachment)
    NSLog("PARLESPRINT_ACOUSTIC_CAPTURE_RESULT frames=%d metrics=%@ route=%@", capturedFrameCount, String(describing: metrics), String(describing: status["routeInputs"]))
  }

  private func acousticMetrics(for pcm: Data) -> (rms: Double, peak: Double, nonzeroSamples: Int, maximumGateLevel: Double, speechStarts: Int) {
    let frameBytes = 640
    let samplesPerFrame = frameBytes / MemoryLayout<Int16>.size
    let frameCount = pcm.count / frameBytes
    var totalSquares = 0.0
    var totalSamples = 0
    var nonzeroSamples = 0
    var peak = 0.0
    var maximumGateLevel = 0.0
    var noiseFloor = 0.02
    var candidateMs = 0
    var silenceMs = 0
    var speechActive = false
    var speechStarts = 0

    for frameIndex in 0..<frameCount {
      let frameStart = frameIndex * frameBytes
      var frameSquares = 0.0
      var framePeak = 0.0
      for sampleIndex in 0..<samplesPerFrame {
        let byteIndex = frameStart + sampleIndex * 2
        let encoded = UInt16(pcm[byteIndex]) | (UInt16(pcm[byteIndex + 1]) << 8)
        let sample = Int16(bitPattern: encoded)
        let value = Double(sample) / 32768.0
        let magnitude = abs(value)
        frameSquares += value * value
        totalSquares += value * value
        totalSamples += 1
        if sample != 0 { nonzeroSamples += 1 }
        framePeak = max(framePeak, magnitude)
        peak = max(peak, magnitude)
      }

      let frameRms = sqrt(frameSquares / Double(samplesPerFrame))
      let gateLevel = min(1.0, frameRms * 4.5 + framePeak * 0.15)
      maximumGateLevel = max(maximumGateLevel, gateLevel)
      let threshold = max(0.04, noiseFloor * 2.2 + 0.015)
      let speechLike = gateLevel >= threshold
      if !speechActive {
        if !speechLike {
          noiseFloor = min(0.18, max(0.008, noiseFloor * 0.96 + gateLevel * 0.04))
        }
        candidateMs = speechLike ? candidateMs + 20 : 0
        if candidateMs >= 180 {
          speechActive = true
          candidateMs = 0
          silenceMs = 0
          speechStarts += 1
        }
      } else {
        silenceMs = speechLike ? 0 : silenceMs + 20
        if silenceMs >= 700 {
          speechActive = false
          candidateMs = 0
          silenceMs = 0
        }
      }
    }

    let rms = totalSamples == 0 ? 0 : sqrt(totalSquares / Double(totalSamples))
    return (rms, peak, nonzeroSamples, maximumGateLevel, speechStarts)
  }

  private func testTone() -> Data {
    let sampleRate = 24_000.0
    let sampleCount = 24_000 / 2
    var data = Data(capacity: sampleCount * MemoryLayout<Int16>.size)
    for index in 0..<sampleCount {
      let envelope = min(1.0, min(Double(index) / 2400, Double(sampleCount - index) / 2400))
      let value = Int16((sin(2 * .pi * 440 * Double(index) / sampleRate) * 4500 * envelope).rounded())
      var littleEndian = value.littleEndian
      withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
    return data
  }

}
