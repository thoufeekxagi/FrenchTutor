import Foundation
import AVFoundation
import Speech

/// TTS + STT for in-lesson narration and voice Q&A. Fully on-device (AVSpeechSynthesizer +
/// SFSpeechRecognizer) so lessons work at $0 without OpenRouter/Gemini for the voice layer.
///
/// Single-owner rule: this service and AudioStreamingService (used by the Marie call) must never
/// both hold an active audio session. Callers MUST invoke `deactivate()` before presenting
/// SessionView, and this service deactivates itself when idle.
final class LessonSpeechService: NSObject, AVSpeechSynthesizerDelegate {

    // MARK: TTS

    struct SpeechItem {
        let text: String
        let language: String // "fr-FR" or "en-US"
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var ttsQueue: [SpeechItem] = []
    private var ttsIndex = 0
    private var onItemStart: ((Int) -> Void)?
    private var onFinished: (() -> Void)?
    private var rateOverride: Float?
    private(set) var isSpeaking = false
    private(set) var isPaused = false

    /// Narration rate: 0.3 (slow) – 0.55 (normal-fast). Persisted via Settings, unless a
    /// one-off override was passed to `speak(items:rate:)`.
    var rate: Float {
        if let rateOverride { return rateOverride }
        let stored = UserDefaults.standard.float(forKey: "lesson_narration_rate")
        return stored > 0 ? stored : 0.42
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks a sequence of (text, language) items in order. `onItemStart` fires with the index
    /// of each item as it begins (for UI highlight/scroll); `onFinished` fires once the whole
    /// queue completes (not called if `stop()` is invoked). `rate` overrides the Settings rate
    /// for this utterance only (e.g. listening lab's Slow/Normal buttons).
    func speak(items: [SpeechItem], rate: Float? = nil, onItemStart: ((Int) -> Void)? = nil, onFinished: (() -> Void)? = nil) {
        stop()
        guard !items.isEmpty else { onFinished?(); return }
        activateAudioSession()
        self.ttsQueue = items
        self.ttsIndex = 0
        self.rateOverride = rate
        self.onItemStart = onItemStart
        self.onFinished = onFinished
        isPaused = false
        speakCurrent()
    }

    func pause() {
        guard isSpeaking, !isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        ttsQueue.removeAll()
        ttsIndex = 0
        isSpeaking = false
        isPaused = false
        onFinished = nil
        onItemStart = nil
    }

    private func speakCurrent() {
        guard ttsIndex < ttsQueue.count else {
            isSpeaking = false
            let finished = onFinished
            onFinished = nil
            deactivateIfIdle()
            finished?()
            return
        }
        isSpeaking = true
        let item = ttsQueue[ttsIndex]
        onItemStart?(ttsIndex)

        let utterance = AVSpeechUtterance(string: item.text)
        utterance.voice = AVSpeechSynthesisVoice(language: item.language)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.12
        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        ttsIndex += 1
        speakCurrent()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    // MARK: - Narration text helpers

    /// Splits mixed English/French narration text into per-sentence SpeechItems so each
    /// sentence is spoken with the right voice. English framing narrates at normal rate;
    /// French example sentences are detected via accent marks / common French words.
    static func speechItems(from narration: String) -> [SpeechItem] {
        splitSentences(narration).map { SpeechItem(text: $0, language: detectLanguage($0)) }
    }

    static func speechItems(from narrationLines: [String]) -> [SpeechItem] {
        narrationLines.flatMap { speechItems(from: $0) }
    }

    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let raw = text
            .replacingOccurrences(of: "...", with: "…")
            .replacingOccurrences(of: "..", with: ".")

        let pattern = "[.!?…]+"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            var lastEnd = raw.startIndex
            regex.enumerateMatches(in: raw, range: range) { match, _, _ in
                guard let match = match, let matchRange = Range(match.range, in: raw) else { return }
                let sentence = String(raw[lastEnd..<matchRange.upperBound]).trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty { sentences.append(sentence) }
                lastEnd = matchRange.upperBound
            }
            let remaining = String(raw[lastEnd...]).trimmingCharacters(in: .whitespaces)
            if !remaining.isEmpty { sentences.append(remaining) }
        }
        if sentences.isEmpty { sentences = [text.trimmingCharacters(in: .whitespaces)] }
        return sentences.filter { !$0.isEmpty }
    }

    private static func detectLanguage(_ text: String) -> String {
        let frenchChars = Set("éèêëàâçîïôûùœæÉÈÊËÀÂÇÎÏÔÛÙŒ")
        let frenchWords: Set<String> = ["bonjour", "merci", "oui", "non", "je", "vous", "le",
                                         "la", "les", "comment", "avec", "pour", "suis",
                                         "il", "elle", "nous", "ils", "elles", "un", "une",
                                         "bien", "mal", "aussi", "mais", "et", "ou", "ne",
                                         "pas", "ai", "as", "a", "avons", "avez", "ont",
                                         "sont", "être", "avoir", "aller", "faire", "dire",
                                         "voir", "savoir", "pouvoir", "vouloir", "devoir",
                                         "venir", "prendre", "donner", "parler", "travaille"]
        let lower = text.lowercased()
        if lower.contains(where: { frenchChars.contains($0) }) { return "fr-FR" }
        let words = Set(lower.split(separator: " ").map(String.init))
        if words.intersection(frenchWords).count >= 2 { return "fr-FR" }
        return "en-US"
    }

    // MARK: STT

    private let speechRecognizerEnUS = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let speechRecognizerFrFR = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private(set) var isListening = false

    enum SpeechAuthError: Error, LocalizedError {
        case denied
        var errorDescription: String? { "Speech recognition access was denied. Enable it in Settings > Privacy." }
    }

    /// Starts listening; calls `onPartial` as transcription updates and `onFinal` once with the
    /// final transcript after ~1.5s of silence or when `stopListening()` is called.
    func startListening(locale: String = "en-US", onPartial: @escaping (String) -> Void, onFinal: @escaping (String) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    onFinal("")
                    return
                }
                self?.beginListening(locale: locale, onPartial: onPartial, onFinal: onFinal)
            }
        }
    }

    private func beginListening(locale: String, onPartial: @escaping (String) -> Void, onFinal: @escaping (String) -> Void) {
        stopListening()
        guard synthesizer.isSpeaking == false else { return } // never listen while speaking

        let recognizer = locale.hasPrefix("fr") ? speechRecognizerFrFR : speechRecognizerEnUS
        guard let recognizer, recognizer.isAvailable else { onFinal(""); return }

        activateAudioSession(forRecording: true)

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.audioEngine = engine
        self.recognitionRequest = request

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            onFinal("")
            return
        }
        isListening = true

        var lastTranscript = ""
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                lastTranscript = result.bestTranscription.formattedString
                onPartial(lastTranscript)
                self.resetSilenceTimer {
                    self.stopListening()
                    onFinal(lastTranscript)
                }
            }
            if error != nil {
                self.stopListening()
                onFinal(lastTranscript)
            }
        }
        resetSilenceTimer { [weak self] in
            self?.stopListening()
            onFinal(lastTranscript)
        }
    }

    private func resetSilenceTimer(_ action: @escaping () -> Void) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in action() }
    }

    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isListening = false
        deactivateIfIdle()
    }

    // MARK: Audio session (single-owner)

    private func activateAudioSession(forRecording: Bool = false) {
        do {
            let session = AVAudioSession.sharedInstance()
            if forRecording {
                try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            } else {
                try session.setCategory(.playback, mode: .spokenAudio)
            }
            try session.setActive(true)
        } catch {
            print("LessonSpeechService: audio session error — \(error)")
        }
    }

    private func deactivateIfIdle() {
        guard !isSpeaking, !isListening else { return }
        deactivate()
    }

    /// MUST be called before presenting SessionView (the Marie call) and in onDisappear of any
    /// lesson view that used this service, so AudioStreamingService can claim the session cleanly.
    func deactivate() {
        stop()
        stopListening()
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Non-fatal: session may already be inactive.
        }
    }
}
