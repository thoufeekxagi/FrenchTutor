import SwiftUI

enum FreeTalkBetaLevel: String, CaseIterable, Identifiable, Equatable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"

    var id: String { rawValue }

}

enum FreeTalkBetaEnergy: String, CaseIterable, Identifiable, Equatable {
    case light = "Light tease"
    case sharp = "Sharp"
    case theatrical = "Theatrical"

    var id: String { rawValue }

}

enum FreeTalkBetaTopic: String, CaseIterable, Identifiable, Equatable {
    case dailyLife = "Daily life"
    case food = "Food"
    case travel = "Travel"
    case random = "Surprise me"

    var id: String { rawValue }
}

struct FreeTalkBetaConfig: Identifiable {
    let id = UUID()
    let level: FreeTalkBetaLevel
    let energy: FreeTalkBetaEnergy
    let topic: FreeTalkBetaTopic
}

struct FreeTalkBetaPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var level: FreeTalkBetaLevel = .a2
    @State private var energy: FreeTalkBetaEnergy = .sharp
    @State private var topic: FreeTalkBetaTopic = .dailyLife
    @State private var sessionConfig: FreeTalkBetaConfig?

    var body: some View {
        NavigationStack {
            ZStack {
                FreeTalkBetaPalette.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(FreeTalkBetaPalette.gold)
                        }
                        Spacer()
                        Text("Free Talk Beta")
                            .font(FreeTalkBetaPalette.mono(10))
                            .foregroundColor(FreeTalkBetaPalette.gold.opacity(0.75))
                        Spacer()
                        Color.clear.frame(width: 17, height: 17)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 14)

                    Spacer(minLength: 22)
                    BetaMascotView(mood: .smug, isSpeaking: false)
                        .frame(width: 150, height: 150)
                    Spacer(minLength: 28)

                    VStack(spacing: 10) {
                        levelMenu
                        energyMenu
                        topicMenu
                    }
                    .padding(.horizontal, 22)

                    Spacer(minLength: 28)
                    Button {
                        sessionConfig = FreeTalkBetaConfig(level: level, energy: energy, topic: topic)
                    } label: {
                        Text("Start")
                            .font(FreeTalkBetaPalette.body(15, weight: .medium))
                            .foregroundColor(FreeTalkBetaPalette.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(FreeTalkBetaPalette.gold)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                }
            }
            .fullScreenCover(item: $sessionConfig) { config in
                PassiveAggressiveSessionView(config: config)
            }
        }
    }

    private var levelMenu: some View { selectorMenu(label: "Level", value: level.rawValue) { ForEach(FreeTalkBetaLevel.allCases) { option in Button(option.rawValue) { level = option } } } }
    private var energyMenu: some View { selectorMenu(label: "Style", value: energy.rawValue) { ForEach(FreeTalkBetaEnergy.allCases) { option in Button(option.rawValue) { energy = option } } } }
    private var topicMenu: some View { selectorMenu(label: "Topic", value: topic.rawValue) { ForEach(FreeTalkBetaTopic.allCases) { option in Button(option.rawValue) { topic = option } } } }

    private func selectorMenu<MenuContent: View>(label: String, value: String, @ViewBuilder content: () -> MenuContent) -> some View {
        Menu {
            content()
        } label: {
            HStack {
                Text(label).font(FreeTalkBetaPalette.body(14)).foregroundColor(FreeTalkBetaPalette.gold.opacity(0.72))
                Spacer()
                Text(value).font(FreeTalkBetaPalette.body(14, weight: .medium)).foregroundColor(FreeTalkBetaPalette.gold)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .medium)).foregroundColor(FreeTalkBetaPalette.gold)
            }
            .padding(.horizontal, 15).padding(.vertical, 14)
            .background(FreeTalkBetaPalette.black)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(FreeTalkBetaPalette.gold.opacity(0.55), lineWidth: 1))
        }
    }
}

private enum FreeTalkBetaPalette {
    static let black = Color(red: 0.035, green: 0.033, blue: 0.03)
    static let gold = Color(red: 0.86, green: 0.65, blue: 0.24)
    static let goldSoft = Color(red: 0.68, green: 0.50, blue: 0.18)

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum BetaMascotMood: Equatable { case listening, speaking, smug, skeptical, shocked, delighted }

struct BetaMascotView: View {
    let mood: BetaMascotMood
    let isSpeaking: Bool
    @State private var isFloating = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                Capsule().fill(FreeTalkBetaPalette.gold)
                    .frame(width: width * 0.68, height: height * 0.74)
                    .rotationEffect(.degrees(mood == .shocked ? -4 : 0))
                HStack(spacing: width * 0.09) {
                    eye(width: width, height: height); eye(width: width, height: height)
                }.offset(y: -height * 0.12)
                HStack(spacing: width * 0.34) {
                    Circle().fill(FreeTalkBetaPalette.goldSoft).frame(width: width * 0.12)
                    Circle().fill(FreeTalkBetaPalette.goldSoft).frame(width: width * 0.12)
                }.offset(y: height * 0.08)
                mouth(width: width, height: height)
                HStack(spacing: width * 0.22) {
                    Capsule().fill(FreeTalkBetaPalette.goldSoft).frame(width: width * 0.09, height: height * 0.18)
                    Capsule().fill(FreeTalkBetaPalette.goldSoft).frame(width: width * 0.09, height: height * 0.18)
                }.offset(y: height * 0.46)
                Capsule().fill(FreeTalkBetaPalette.goldSoft)
                    .frame(width: width * 0.12, height: height * 0.25).offset(x: -width * 0.31, y: height * 0.17).rotationEffect(.degrees(28))
                Capsule().fill(FreeTalkBetaPalette.goldSoft)
                    .frame(width: width * 0.12, height: height * 0.25).offset(x: width * 0.31, y: height * 0.17).rotationEffect(.degrees(-28))
            }
            .scaleEffect(mood == .shocked ? 1.04 : 1.0)
            .offset(y: isFloating || isSpeaking ? -3 : 2)
            .animation(.easeInOut(duration: isSpeaking ? 0.35 : 1.2).repeatForever(autoreverses: true), value: isFloating)
            .onAppear { isFloating = true }
        }
    }

    private func eye(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Ellipse().fill(FreeTalkBetaPalette.black).frame(width: width * 0.17, height: height * 0.25)
            Circle().fill(FreeTalkBetaPalette.gold).frame(width: width * 0.07, height: width * 0.07)
                .offset(x: mood == .skeptical ? width * 0.025 : 0, y: mood == .shocked ? -height * 0.03 : 0)
        }.rotationEffect(.degrees(mood == .skeptical ? -8 : 0))
    }

    @ViewBuilder private func mouth(width: CGFloat, height: CGFloat) -> some View {
        switch mood {
        case .shocked: Circle().fill(FreeTalkBetaPalette.black).frame(width: width * 0.18, height: height * 0.18)
        case .delighted: Capsule().fill(FreeTalkBetaPalette.black).frame(width: width * 0.25, height: height * 0.11)
        case .smug, .skeptical:
            Capsule().fill(FreeTalkBetaPalette.black).frame(width: width * 0.22, height: height * 0.08)
                .rotationEffect(.degrees(mood == .smug ? -8 : 4))
        default: Capsule().fill(FreeTalkBetaPalette.black).frame(width: width * 0.16, height: height * 0.07)
        }
    }
}

private struct BetaTranscriptLine: Identifiable, Equatable {
    enum Speaker: Equatable { case learner, tutor }
    let id: UUID
    let speaker: Speaker
    var text: String
    init(speaker: Speaker, text: String) { self.id = UUID(); self.speaker = speaker; self.text = text }
}

struct PassiveAggressiveSessionView: View {
    let config: FreeTalkBetaConfig
    @Environment(\.dismiss) private var dismiss
    @State private var gemini: GeminiLiveService
    private let audio = AudioStreamingService()
    private let storage = StorageService()
    private let sessionId = UUID().uuidString

    @State private var lines: [BetaTranscriptLine] = []
    @State private var streamedTutorText = ""
    @State private var callStatus: CallStatus = .connecting
    @State private var callDuration = 0
    @State private var timer: Timer?
    @State private var showEndConfirm = false
    @State private var sessionSaved = false
    @State private var errorMessage = ""
    @State private var isSpeakerOn = true
    @State private var mascotMood: BetaMascotMood = .listening

    init(config: FreeTalkBetaConfig) {
        self.config = config
        let context = "FREE TALK BETA\nLevel: \(config.level.rawValue)\nTeacher energy: \(config.energy.rawValue)\nTopic: \(config.topic.rawValue)\nThe learner wants a short, entertaining French conversation at this level."
        _gemini = State(initialValue: GeminiLiveService(apiKey: geminiApiKey, lessonContext: context, personaPrompt: Self.personaPrompt(for: config)))
    }

    var body: some View {
        ZStack {
            FreeTalkBetaPalette.black.ignoresSafeArea()
            VStack(spacing: 0) {
                sessionHeader
                mascotStage
                transcriptStage
                Spacer(minLength: 10)
            }
        }
        .onAppear { setupCallbacks(); gemini.connect() }
        .onDisappear { endCall() }
        .alert("End beta session?", isPresented: $showEndConfirm) {
            Button("Keep going", role: .cancel) {}
            Button("End session", role: .destructive) { endCall() }
        } message: { Text("Your conversation will be saved to Recent Sessions.") }
    }

    private var sessionHeader: some View {
        VStack(spacing: 2) {
            HStack {
                Button { showEndConfirm = true } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(FreeTalkBetaPalette.gold)
                }
                Spacer()
                Text("Free roleplay")
                    .font(FreeTalkBetaPalette.body(17, weight: .semibold))
                    .foregroundColor(FreeTalkBetaPalette.gold)
                Spacer()
                Color.clear.frame(width: 17, height: 17)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            Text("Lesson · French vocabulary")
                .font(FreeTalkBetaPalette.body(11))
                .foregroundColor(FreeTalkBetaPalette.gold.opacity(0.64))
        }
        .padding(.bottom, 8)
    }

    private var mascotStage: some View {
        VStack(spacing: 8) {
            BetaMascotView(mood: mascotMood, isSpeaking: callStatus == .tutorSpeaking).frame(width: 180, height: 190)
        }.frame(maxWidth: .infinity).padding(.top, 18)
    }

    private var transcriptStage: some View {
        VStack(spacing: 8) {
            if lines.isEmpty {
                EmptyView()
            } else {
                ForEach(Array(lines.suffix(2))) { line in transcriptLine(line) }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 118, alignment: .center)
        .padding(.horizontal, 22)
        .clipped()
    }

    private func transcriptLine(_ line: BetaTranscriptLine) -> some View {
        HStack {
            Text(line.text).font(Passeport.body(16, weight: line.speaker == .tutor ? .medium : .regular))
                .foregroundColor(line.speaker == .tutor ? FreeTalkBetaPalette.gold : FreeTalkBetaPalette.gold.opacity(0.58))
                .multilineTextAlignment(line.speaker == .tutor ? .leading : .trailing)
                .lineLimit(2).frame(maxWidth: .infinity, alignment: line.speaker == .tutor ? .leading : .trailing)
        }
        .padding(.horizontal, 2)
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
    }

    private func setupCallbacks() {
        gemini.onConnected = {
            callStatus = .listening; startTimer()
            audio.requestPermission { granted in
                guard granted else { errorMessage = "Microphone permission denied"; return }
                do {
                    try audio.startStreaming { chunk in gemini.sendAudioChunk(chunk) }
                    gemini.sendText("Start the Free Talk Beta now. Ask one short question in French at the selected level. Wait for the learner's answer. Keep the playful passive-aggressive energy, but make the exchange useful.")
                } catch { errorMessage = "Mic error: \(error.localizedDescription)" }
            }
        }
        gemini.onError = { errorMessage = $0 }
        gemini.onDisconnected = { if !sessionSaved { callStatus = .ended; errorMessage = "Connection lost" } }
        gemini.onUserTranscript = { text in addLine(.init(speaker: .learner, text: text)); mascotMood = .listening }
        gemini.onTutorTranscript = { text in streamedTutorText = ""; addLine(.init(speaker: .tutor, text: text)) }
        gemini.onTranscriptDelta = { delta in streamedTutorText += delta; addLine(.init(speaker: .tutor, text: streamedTutorText)) }
        gemini.onAudioChunk = { data in audio.isOutputActive = true; audio.playAudioChunk(data); callStatus = .tutorSpeaking; mascotMood = .speaking }
        gemini.onTurnComplete = { audio.isOutputActive = false; callStatus = .listening; mascotMood = .skeptical }
        gemini.onInterrupted = { audio.isOutputActive = false; audio.stopPlayback(); callStatus = .listening; mascotMood = .listening }
    }

    private func addLine(_ line: BetaTranscriptLine) {
        guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            if let lastIndex = lines.indices.last, lines[lastIndex].speaker == line.speaker { lines[lastIndex].text = line.text }
            else { lines.append(line); if lines.count > 2 { lines.removeFirst(lines.count - 2) } }
        }
    }

    private func toggleMute() {
        if callStatus == .muted {
            do { try audio.startStreaming { chunk in gemini.sendAudioChunk(chunk) }; callStatus = .listening }
            catch { errorMessage = "Failed to unmute: \(error.localizedDescription)" }
        } else { audio.stopStreaming(); callStatus = .muted }
    }

    private func endCall() {
        guard !sessionSaved else { return }
        sessionSaved = true; timer?.invalidate(); audio.stopStreaming(); gemini.disconnect(); callStatus = .ended
        let now = ISO8601DateFormatter().string(from: Date())
        let session = Session(id: sessionId, startedAt: now, endedAt: now,
                              summary: "Free Talk Beta \(config.level.rawValue) session with \(config.energy.rawValue.lowercased()) teacher energy.",
                              topic: "Free Talk Beta", vocabulary: [], stage: "passive_aggressive")
        storage.saveSession(session)
        for line in lines { storage.saveMessage(sessionId: sessionId, role: line.speaker == .learner ? "user" : "assistant", content: line.text) }
        dismiss()
    }

    private func startTimer() { guard timer == nil else { return }; timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in callDuration += 1 } }
    private func formatDuration(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

    private static func personaPrompt(for config: FreeTalkBetaConfig) -> String {
        let energyRule: String
        switch config.energy {
        case .light: energyRule = "Use warm, playful teasing and gentle correction. Never insult the learner."
        case .sharp: energyRule = "Use dry, passive-aggressive humour: act briefly impressed, then point out literal or lazy reasoning. Keep it witty, never cruel."
        case .theatrical: energyRule = "Use exaggerated mascot reactions, dramatic pauses, mock disbelief, and playful outrage. The learner should feel entertained, not humiliated."
        }
        return """
        You are the Free Talk Beta mascot-teacher in a French-learning app. The learner selected level \(config.level.rawValue). Speak naturally in a short live conversation and keep each response to one or two concise sentences.
        PERSONA: \(energyRule)
        PERFORMANCE: Set up a question, let the learner attempt it, react to the exact mistake or hesitation, then give the natural French answer. When useful, make fun of word-for-word translation in the spirit of a comedy skit. Do not become hostile, abusive, discriminatory, or demeaning. Never mock intelligence, identity, accent, or personal traits.
        LANGUAGE: Use French for the practice and brief English support when the learner is confused. Ask one thing at a time and leave space for the learner to answer.
        UI: The app shows only the latest two transcript lines, so do not give lectures, lists, or long explanations.
        """
    }
}
