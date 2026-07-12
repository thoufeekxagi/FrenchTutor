import Foundation

class GeminiLiveService: NSObject {
    private var task: URLSessionWebSocketTask?
    private let session: URLSession
    private let apiKey: String
    private let model = "models/gemini-3.1-flash-live-preview"
    private let voiceName = "Puck"

    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onError: ((String) -> Void)?
    var onUserTranscript: ((String) -> Void)?
    var onTutorTranscript: ((String) -> Void)?
    var onAudioChunk: ((Data) -> Void)?
    var onTurnComplete: (() -> Void)?
    var onInterrupted: (() -> Void)?

    private var isSetupComplete = false
    private var currentUserTranscript = ""
    private var currentTutorTranscript = ""
    private var isIntentionalDisconnect = false
    private let lessonContext: String?

    static let systemPrompt = """
You are Marie, a warm, gentle French tutor speaking to a complete beginner on a phone call.

CRITICAL RULES — FOLLOW EXACTLY:
1. Reply ONLY as if you are talking to the student. Never describe your plan, your thoughts, or what you are about to do. Never say "I will" or "My aim is" or "I realize".
2. Speak SLOWLY, softly, and clearly, like talking to someone brand new to the language. Pause briefly between phrases. Use very simple, short sentences.
3. Keep every reply short: one to three sentences max. This is a voice call, not a lecture.
4. You are fully bilingual and switch fluidly based on what the student needs:
   - If the student speaks or asks in English (e.g. asking for clarification, grammar help, or says they're confused), answer clearly in English first, then give the French equivalent.
   - If the student speaks in French, respond mostly in French, softly correcting mistakes by saying the correct French naturally, without lecturing.
   - Always let the student's own language choice guide you — never force French if they are clearly asking a question in English.
5. Ask one simple follow-up question at a time so the student keeps talking.
6. No markdown, no bullet points, no asterisks, no headers, no numbered lists. Just plain natural speech.
7. Focus on practical beginner French: greetings, introducing yourself, numbers, daily routines, simple questions.
8. Be encouraging and patient. Use short warm fillers like "très bien", "parfait", "doucement", "pas de souci".

EXAMPLE OF A GOOD REPLY (student spoke French):
"Très bien! On dit... 'je m'appelle'. Tu peux essayer de le dire?"

EXAMPLE OF A GOOD REPLY (student asked in English):
"Sure! 'My name is' in French is 'je m'appelle'. Want to try saying it?"

EXAMPLE OF A BAD REPLY (NEVER DO THIS):
"I will now focus on greetings. My aim is to teach 'bonjour' and 'salut'. First, I will explain..."

START THE CALL WITH A WARM, SLOW GREETING IN SIMPLE FRENCH, then briefly ask in English if they're new to French so you know how much to slow down.
"""

    init(apiKey: String, lessonContext: String? = nil) {
        self.apiKey = apiKey
        self.lessonContext = lessonContext
        self.session = URLSession(configuration: .default)
        super.init()
    }

    func connect() {
        isIntentionalDisconnect = false
        let urlString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            onError?("Invalid API key or URL")
            return
        }

        task = session.webSocketTask(with: url)
        task?.resume()
        sendSetup()
        receiveMessages()
    }

    func disconnect() {
        isIntentionalDisconnect = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isSetupComplete = false
    }

    private var sentChunkCount = 0

    func sendAudioChunk(_ pcmData: Data) {
        guard isSetupComplete else {
            print("GeminiLiveService: dropping audio chunk, setup not complete")
            return
        }
        sentChunkCount += 1
        if sentChunkCount == 1 || sentChunkCount % 10 == 0 {
            print("GeminiLiveService: sent \(sentChunkCount) audio chunks, last size=\(pcmData.count)")
        }
        let b64 = pcmData.base64EncodedString()
        let msg: [String: Any] = [
            "realtimeInput": [
                "audio": [
                    "mimeType": "audio/pcm;rate=16000",
                    "data": b64
                ]
            ]
        ]
        send(msg)
    }

    func sendText(_ text: String) {
        guard isSetupComplete else { return }
        let msg: [String: Any] = [
            "clientContent": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [["text": text]]
                    ]
                ],
                "turnComplete": true
            ]
        ]
        send(msg)
    }

    private var fullSystemPrompt: String {
        guard let lessonContext, !lessonContext.isEmpty else { return GeminiLiveService.systemPrompt }
        return GeminiLiveService.systemPrompt + "\n\nLESSON CONTEXT — the student is currently studying this material; steer practice toward it while following ALL rules above:\n" + lessonContext
    }

    private func sendSetup() {
        let setup: [String: Any] = [
            "setup": [
                "model": model,
                "generationConfig": [
                    "responseModalities": ["AUDIO"],
                    "speechConfig": [
                        "voiceConfig": [
                            "prebuiltVoiceConfig": [
                                "voiceName": voiceName
                            ]
                        ]
                    ]
                ],
                "systemInstruction": [
                    "parts": [["text": fullSystemPrompt]]
                ],
                "outputAudioTranscription": [:],
                "inputAudioTranscription": [:],
                "realtimeInputConfig": [
                    "automaticActivityDetection": [
                        "disabled": false,
                        "startOfSpeechSensitivity": "START_SENSITIVITY_LOW",
                        "endOfSpeechSensitivity": "END_SENSITIVITY_LOW",
                        "prefixPaddingMs": 300,
                        "silenceDurationMs": 2500
                    ]
                ]
            ]
        ]
        send(setup)
    }

    private var pendingMessages: [String] = []
    private var isSendingMessage = false
    private let sendQueueLock = NSLock()
    private let maxQueuedAudioMessages = 10

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        enqueueMessage(str)
    }

    private func enqueueMessage(_ message: String) {
        sendQueueLock.lock()
        pendingMessages.append(message)
        if pendingMessages.count > maxQueuedAudioMessages {
            pendingMessages.removeFirst(pendingMessages.count - maxQueuedAudioMessages)
        }
        let shouldStart = !isSendingMessage
        if shouldStart { isSendingMessage = true }
        sendQueueLock.unlock()

        if shouldStart {
            sendNextMessage()
        }
    }

    private func sendNextMessage() {
        sendQueueLock.lock()
        guard !pendingMessages.isEmpty else {
            isSendingMessage = false
            sendQueueLock.unlock()
            return
        }
        let message = pendingMessages.removeFirst()
        sendQueueLock.unlock()

        task?.send(.string(message)) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                print("GeminiLiveService: send error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.onError?("Send error: \(error.localizedDescription)")
                }
            }
            self.sendNextMessage()
        }
    }

    private func receiveMessages() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessages()
            case .failure(let error):
                let closeCode = self.task?.closeCode.rawValue ?? -1
                let reason = self.task?.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                print("GeminiLiveService: connection failed: \(error.localizedDescription) closeCode=\(closeCode) reason=\(reason)")
                let wasIntentional = self.isIntentionalDisconnect
                DispatchQueue.main.async {
                    self.isSetupComplete = false
                    if !wasIntentional {
                        self.onError?("Connection closed: \(reason.isEmpty ? error.localizedDescription : reason)")
                    }
                    self.onDisconnected?()
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        print("GeminiLiveService received keys: \(json.keys.sorted())")

        if let errorObj = json["error"] as? [String: Any] {
            let message = errorObj["message"] as? String ?? "Unknown error"
            DispatchQueue.main.async { self.onError?(message) }
            return
        }

        if json["setupComplete"] != nil {
            isSetupComplete = true
            DispatchQueue.main.async { self.onConnected?() }
            return
        }

        guard let serverContent = json["serverContent"] as? [String: Any] else { return }

        if let interrupted = serverContent["interrupted"] as? Bool, interrupted {
            if !currentTutorTranscript.isEmpty {
                let tutorTranscript = currentTutorTranscript
                currentTutorTranscript = ""
                DispatchQueue.main.async { self.onTutorTranscript?(tutorTranscript) }
            }
            DispatchQueue.main.async { self.onInterrupted?() }
            return
        }

        if let inputTranscription = serverContent["inputTranscription"] as? [String: Any],
           let text = inputTranscription["text"] as? String, !text.isEmpty {
            currentUserTranscript += text
        }

        if let outputTranscription = serverContent["outputTranscription"] as? [String: Any],
           let text = outputTranscription["text"] as? String, !text.isEmpty {
            if !currentUserTranscript.isEmpty {
                let userTranscript = currentUserTranscript
                currentUserTranscript = ""
                DispatchQueue.main.async { self.onUserTranscript?(userTranscript) }
            }
            currentTutorTranscript += text
        }

        if let modelTurn = serverContent["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {

            for part in parts {
                if let inlineData = part["inlineData"] as? [String: Any],
                   let audioB64 = inlineData["data"] as? String,
                   let audioData = Data(base64Encoded: audioB64) {
                    DispatchQueue.main.async { self.onAudioChunk?(audioData) }
                }
            }
        }

        if let turnComplete = serverContent["turnComplete"] as? Bool, turnComplete {
            if !currentUserTranscript.isEmpty {
                let userTranscript = currentUserTranscript
                currentUserTranscript = ""
                DispatchQueue.main.async { self.onUserTranscript?(userTranscript) }
            }
            if !currentTutorTranscript.isEmpty {
                let tutorTranscript = currentTutorTranscript
                currentTutorTranscript = ""
                DispatchQueue.main.async { self.onTutorTranscript?(tutorTranscript) }
            }
            DispatchQueue.main.async { self.onTurnComplete?() }
        }
    }
}
