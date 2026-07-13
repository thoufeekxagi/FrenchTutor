import SwiftUI

struct SessionView: View {
    let apiKey: String
    @Environment(\.dismiss) var dismiss

    @State private var messages: [ChatMessage] = []
    @State private var callStatus: CallStatus = .connecting
    @State private var errorMessage = ""
    @State private var showEndConfirm = false
    @State private var sessionSaved = false
    @State private var callDuration: Int = 0
    @State private var timer: Timer?
    @State private var isSpeakerOn = true

    private let gemini: GeminiLiveService
    private let audio: AudioStreamingService
    private let storage: StorageService
    private let sessionId: String

    init(apiKey: String, lessonContext: String? = nil) {
        self.apiKey = apiKey
        self.gemini = GeminiLiveService(apiKey: apiKey, lessonContext: lessonContext)
        self.audio = AudioStreamingService()
        self.storage = StorageService()
        self.sessionId = UUID().uuidString
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                callHeader

                transcriptView

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(Color(red: 0.8, green: 0.2, blue: 0.2))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 1.0, green: 0.42, blue: 0.42).opacity(0.1))
                }

                callControls
            }
        }
        .onAppear {
            setupCallbacks()
            startCall()
        }
        .onDisappear {
            endCall()
        }
        .alert("End Call?", isPresented: $showEndConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("End Call", role: .destructive) {
                endCall()
            }
        } message: {
            Text("Your session transcript and summary will be saved.")
        }
    }

    private var callHeader: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: { showEndConfirm = true }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                }
                Spacer()
                Text(formatDuration(callDuration))
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            VStack(spacing: 2) {
                Text("French Tutor")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text(statusText)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
        .padding(.bottom, 16)
    }

    private var transcriptView: some View {
        Group {
            if messages.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "phone.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(callStatus == .connecting ? "Connecting to your tutor..." : "Start speaking to begin")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: messages.count) { _ in
                        withAnimation {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var callControls: some View {
        HStack(spacing: 40) {
            Button(action: toggleMute) {
                VStack(spacing: 6) {
                    Image(systemName: callStatus == .muted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(callStatus == .muted ? Color.gray : Color(red: 0.42, green: 0.36, blue: 0.91))
                        .clipShape(Circle())
                    Text(callStatus == .muted ? "Muted" : "Mic On")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(callStatus == .connecting || callStatus == .ended)

            Button(action: toggleSpeaker) {
                VStack(spacing: 6) {
                    Image(systemName: isSpeakerOn ? "speaker.wave.2.fill" : "ear.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(isSpeakerOn ? Color(red: 0.42, green: 0.36, blue: 0.91) : Color.gray)
                        .clipShape(Circle())
                    Text(isSpeakerOn ? "Speaker" : "Earpiece")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(callStatus == .connecting || callStatus == .ended)

            Button(action: { showEndConfirm = true }) {
                VStack(spacing: 6) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color(red: 0.85, green: 0.2, blue: 0.2))
                        .clipShape(Circle())
                    Text("End Call")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 24)
        .padding(.bottom, 8)
    }

    private var statusColor: Color {
        switch callStatus {
        case .connecting: return Color(red: 0.95, green: 0.60, blue: 0.10)
        case .listening: return Color(red: 0.20, green: 0.78, blue: 0.35)
        case .tutorSpeaking: return Color(red: 0.42, green: 0.36, blue: 0.91)
        case .muted: return Color.gray
        case .ended: return Color.gray.opacity(0.5)
        }
    }

    private var statusText: String {
        switch callStatus {
        case .connecting: return "Connecting..."
        case .listening: return "Listening — speak in French"
        case .tutorSpeaking: return "Tutor is speaking..."
        case .muted: return "Microphone muted"
        case .ended: return "Call ended"
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func startCall() {
        gemini.connect()
    }

    private func endCall() {
        guard !sessionSaved else { return }
        sessionSaved = true

        timer?.invalidate()
        audio.stopStreaming()
        gemini.disconnect()
        callStatus = .ended

        saveSessionLocally()
    }

    private func toggleSpeaker() {
        isSpeakerOn.toggle()
        audio.setSpeakerEnabled(isSpeakerOn)
    }

    private func toggleMute() {
        if callStatus == .muted {
            do {
                try audio.startStreaming { chunk in
                    self.gemini.sendAudioChunk(chunk)
                }
                callStatus = .listening
            } catch {
                errorMessage = "Failed to unmute: \(error.localizedDescription)"
            }
        } else {
            audio.stopStreaming()
            callStatus = .muted
        }
    }

    private func setupCallbacks() {
        gemini.onConnected = {
            callStatus = .listening
            startTimer()

            audio.requestPermission { granted in
                if granted {
                    do {
                        try audio.startStreaming { chunk in
                            self.gemini.sendAudioChunk(chunk)
                        }
                        gemini.sendText("(Le student vient de rejoindre l'appel. Salue-le chaleureusement en français et demande ce qu'il veut pratiquer aujourd'hui.)")
                    } catch {
                        errorMessage = "Mic error: \(error.localizedDescription)"
                    }
                } else {
                    errorMessage = "Microphone permission denied"
                }
            }
        }

        gemini.onDisconnected = {
            if !sessionSaved {
                errorMessage = "Connection lost"
                callStatus = .ended
            }
        }

        gemini.onError = { msg in
            errorMessage = msg
        }

        gemini.onUserTranscript = { text in
            messages.append(ChatMessage(role: "user", content: text, timestamp: Date()))
        }

        gemini.onTutorTranscript = { text in
            messages.append(ChatMessage(role: "tutor", content: text, timestamp: Date()))
        }

        gemini.onAudioChunk = { audioData in
            audio.isOutputActive = true
            audio.playAudioChunk(audioData)
            if callStatus != .tutorSpeaking {
                callStatus = .tutorSpeaking
            }
        }

        gemini.onTurnComplete = {
            audio.isOutputActive = false
            callStatus = .listening
        }

        gemini.onInterrupted = {
            audio.isOutputActive = false
            audio.stopPlayback()
            callStatus = .listening
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            callDuration += 1
        }
    }

    private func saveSessionLocally() {
        let now = ISO8601DateFormatter().string(from: Date())
        let summary = generateLocalSummary()

        let session = Session(id: sessionId, startedAt: now, endedAt: now, summary: summary, topic: nil, vocabulary: [])
        storage.saveSession(session)

        for msg in messages {
            storage.saveMessage(sessionId: sessionId, role: msg.isUser ? "user" : "assistant", content: msg.content)
        }

        if callDuration >= 45 {
            LearningStore().markHabit(date: Date(), habitId: "speaking", done: true, addMinutes: max(1, callDuration / 60))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }

    private func generateLocalSummary() -> String {
        guard !messages.isEmpty else { return "No conversation recorded." }

        let userMessages = messages.filter { $0.isUser }.count
        let tutorMessages = messages.filter { !$0.isUser }.count
        let duration = formatDuration(callDuration)

        var summary = "Session lasted \(duration). "
        summary += "\(userMessages) exchanges from you, \(tutorMessages) responses from tutor. "

        let allText = messages.map { $0.content }.joined(separator: " ").lowercased()

        let frenchKeywords = ["bonjour", "merci", "oui", "non", "je", "vous", "le", "la", "les",
                              "comment", "avec", "pour", "suis", "appelle", "salut", "ça", "va",
                              "très", "bien", "mal", "aussi", "mais", "et", "ou", "ne", "pas",
                              "ai", "as", "a", "avons", "avez", "ont", "sont", "être", "avoir",
                              "aller", "faire", "dire", "voir", "savoir", "pouvoir", "vouloir",
                              "devoir", "falloir", "venir", "prendre", "donner", "parler",
                              "écouter", "regarder", "aimer", "manger", "boire", "acheter",
                              "vendre", "habiter", "travailler", "étudier", "apprendre",
                              "comprendre", "répéter", "corriger", "expliquer", "traduire"]

        let words = Set(allText.split(separator: " ").map(String.init))
        let frenchUsed = words.intersection(frenchKeywords)
        if !frenchUsed.isEmpty {
            summary += "French words used: \(frenchUsed.sorted().prefix(10).joined(separator: ", ")). "
        }

        if userMessages > 3 {
            summary += "Good practice session — keep going!"
        } else {
            summary += "Try speaking more next time for better practice."
        }

        return summary
    }
}

enum CallStatus {
    case connecting
    case listening
    case tutorSpeaking
    case muted
    case ended
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if !message.isUser {
                avatar(false)
            }
            if !message.isUser { Spacer().frame(width: 8) }

            Text(message.content)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(message.isUser ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.isUser
                        ? Color(red: 0.42, green: 0.36, blue: 0.91)
                        : Color(.secondarySystemGroupedBackground)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))

            if message.isUser { Spacer().frame(width: 8) }
            if message.isUser {
                avatar(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }

    private func avatar(_ isUser: Bool) -> some View {
        Circle()
            .fill((isUser ? Color(red: 0.42, green: 0.36, blue: 0.91) : Color(red: 0.55, green: 0.49, blue: 0.96)).opacity(0.2))
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: isUser ? "person.fill" : "graduationcap.fill")
                    .font(.system(size: 12))
                    .foregroundColor(isUser ? Color(red: 0.42, green: 0.36, blue: 0.91) : Color(red: 0.55, green: 0.49, blue: 0.96))
            )
    }
}
