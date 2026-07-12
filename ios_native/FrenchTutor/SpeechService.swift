import Foundation
import AVFoundation

class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var queue: [SpeechSegment] = []
    private var isSpeaking = false
    private var onComplete: (() -> Void)?

    var onSpeakingChange: ((Bool) -> Void)?

    struct SpeechSegment {
        let text: String
        let language: String
        let rate: Float
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, onComplete: (() -> Void)? = nil) {
        stop()
        self.onComplete = onComplete
        self.queue = parseSegments(from: text)
        self.isSpeaking = false
        speakNext()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        queue.removeAll()
        isSpeaking = false
        onSpeakingChange?(false)
    }

    private func speakNext() {
        guard !queue.isEmpty else {
            isSpeaking = false
            onSpeakingChange?(false)
            onComplete?()
            onComplete = nil
            return
        }

        let segment = queue.removeFirst()
        if !isSpeaking {
            isSpeaking = true
            onSpeakingChange?(true)
        }

        let utterance = AVSpeechUtterance(string: segment.text)
        utterance.voice = AVSpeechSynthesisVoice(language: segment.language)
        utterance.rate = segment.rate
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.15

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }

        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        speakNext()
    }

    private func parseSegments(from text: String) -> [SpeechSegment] {
        let sentences = splitSentences(text)
        return sentences.map { sentence in
            let lang = detectLanguage(sentence)
            let isCorrection = sentence.lowercased().contains("correction") ||
                               sentence.lowercased().contains("should be") ||
                               sentence.lowercased().contains("instead of") ||
                               sentence.lowercased().contains("not quite")
            let isNewVocab = sentence.lowercased().contains("means") ||
                             sentence.lowercased().contains("this is how") ||
                             sentence.lowercased().contains("new word")

            let rate: Float
            if isCorrection || isNewVocab {
                rate = 0.35
            } else {
                rate = 0.5
            }

            return SpeechSegment(text: sentence, language: lang, rate: rate)
        }
    }

    private func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let raw = text
            .replacingOccurrences(of: "...", with: "…")
            .replacingOccurrences(of: "..", with: ".")

        let pattern = "[.!?…]+"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            var lastEnd = raw.startIndex
            regex.enumerateMatches(in: raw, range: range) { match, _, _ in
                guard let match = match,
                      let matchRange = Range(match.range, in: raw) else { return }
                let sentence = String(raw[lastEnd..<matchRange.upperBound]).trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty {
                    sentences.append(sentence)
                }
                lastEnd = matchRange.upperBound
            }
            let remaining = String(raw[lastEnd...]).trimmingCharacters(in: .whitespaces)
            if !remaining.isEmpty {
                sentences.append(remaining)
            }
        }

        if sentences.isEmpty {
            sentences = [text.trimmingCharacters(in: .whitespaces)]
        }

        return sentences.filter { !$0.isEmpty }
    }

    private func detectLanguage(_ text: String) -> String {
        let frenchChars = Set("éèêëàâçîïôûùœæÉÈÊËÀÂÇÎÏÔÛÙŒ")
        let frenchWords: Set<String> = ["bonjour", "merci", "oui", "non", "je", "vous", "le",
                                         "la", "les", "comment", "avec", "pour", "suis",
                                         "appelle", "bonsoir", "salut", "ça", "va", "très",
                                         "bien", "mal", "aussi", "mais", "et", "ou", "ne",
                                         "pas", "ai", "as", "a", "avons", "avez", "ont",
                                         "sont", "être", "avoir", "aller", "faire", "dire",
                                         "voir", "savoir", "pouvoir", "vouloir", "devoir",
                                         "falloir", "venir", "prendre", "donner", "parler",
                                         "écouter", "regarder", "aimer", "manger", "boire",
                                         "acheter", "vendre", "habiter", "travailler",
                                         "étudier", "apprendre", "comprendre", "répéter",
                                         "corriger", "expliquer", "traduire", "prononcer"]

        let lower = text.lowercased()
        if lower.contains(where: { frenchChars.contains($0) }) {
            return "fr-FR"
        }

        let words = Set(lower.split(separator: " ").map(String.init))
        let frenchCount = words.intersection(frenchWords).count
        if frenchCount >= 2 {
            return "fr-FR"
        }

        return "en-US"
    }
}
