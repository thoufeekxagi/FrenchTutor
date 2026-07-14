import SwiftUI

struct GrammarStageResult {
    let topicTitle: String
    let drillResults: [Bool]
}

private struct GrammarSessionCard {
    let card: GrammarPracticeCard
}

private enum GrammarUserIntent: String {
    case advance
    case again
    case back
    case none
}

/// Daily Pathway stage 2 — one chosen tense/topic (see `GrammarPickerView`), walked through
/// EXACTLY the way `AgentLedVocabView` walks through vocab: one generated sentence card at a
/// time (front = English meaning, back = the French sentence, a one-line grammar note where
/// vocab shows phonetics), app-owned step index, deterministic intent detection, Back/Next
/// buttons wired to the same functions as voice, a single judgment-only tool. This used to be a
/// dry usage-bullet/conjugation-table/drill layout that didn't feel anything like vocab's proven
/// card interaction — it's been rebuilt to match that pattern structurally, not just in spirit.
/// Cards are generated ONCE before the session starts (`LessonAgentService
/// .generateGrammarPracticeCards`, informed by the vocab words + transcript from the Vocab stage
/// that just happened) — nothing invented live by the model, matching STRUCTURE.md.
struct AgentLedGrammarView: View {
    let cards: [GrammarPracticeCard]
    let tenseTitle: String
    var focusNote: String? = nil
    var vocabSummary: VocabStageResult? = nil
    var onComplete: (GrammarStageResult) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var gemini: GeminiLiveService
    private let audio = AudioStreamingService()
    private let store = LearningStore()
    private let recorder: SessionRecorder
    private let sessionPlan: [GrammarSessionCard]
    private let topicId: String

    @State private var callStatus: CallStatus = .connecting
    @State private var callDuration = 0
    @State private var timer: Timer?
    @State private var errorMessage = ""
    @State private var showEndConfirm = false
    @State private var finished = false
    @State private var isWrappingUp = false

    @State private var lastAudioChunkAt = Date()
    @State private var speakingWatchdog: Timer?

    @State private var cardIndex = 0
    @State private var drillResults: [Bool] = []
    @State private var debugLog: [String] = []

    @State private var hasAttempted = false
    @State private var wasGraded = false
    @State private var lastDetectedIntent: GrammarUserIntent = .none
    @State private var handledCallIds: Set<String> = []

    @State private var recentTranscriptBuffer = ""
    @State private var spokenSentenceMatched = false
    @State private var sentencePulse = false

    init(cards: [GrammarPracticeCard], tenseTitle: String, focusNote: String? = nil, vocabSummary: VocabStageResult? = nil, onComplete: @escaping (GrammarStageResult) -> Void) {
        self.cards = cards
        self.tenseTitle = tenseTitle
        self.focusNote = focusNote
        self.vocabSummary = vocabSummary
        self.onComplete = onComplete
        self.topicId = "grammar_\(tenseTitle.lowercased().replacingOccurrences(of: " ", with: "_"))"
        self.recorder = SessionRecorder(stage: "grammar", topic: "Grammar — \(tenseTitle)")
        let plan = cards.map { GrammarSessionCard(card: $0) }
        self.sessionPlan = plan
        let context = AgentLedGrammarView.buildContext(tenseTitle: tenseTitle, plan: plan, focusNote: focusNote, vocabSummary: vocabSummary)
        _gemini = State(initialValue: GeminiLiveService(apiKey: geminiApiKey, lessonContext: context, tools: AgentTool.grammarPalette))
    }

    private var currentCard: GrammarSessionCard? {
        cardIndex < sessionPlan.count ? sessionPlan[cardIndex] : nil
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView { content.padding(.horizontal, 18).padding(.vertical, 16) }
                if !errorMessage.isEmpty {
                    Text(errorMessage).font(.system(size: 12, design: .rounded)).foregroundColor(Passeport.maroon)
                        .padding(.horizontal, 20).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                }
                debugPanel
                controls
            }
        }
        .onAppear { setupCallbacks(); gemini.connect() }
        .onDisappear { finishAndReturn() }
        .alert("End grammar practice?", isPresented: $showEndConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("End", role: .destructive) { finishAndReturn() }
        } message: { Text("Your progress so far is saved.") }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Button { showEndConfirm = true } label: {
                    Image(systemName: "xmark").font(.system(size: 18)).foregroundColor(Passeport.text)
                }
                Spacer()
                Text(formatDuration(callDuration)).font(Passeport.mono(13, weight: .medium)).foregroundColor(Passeport.slateDim)
                Spacer()
                Circle().fill(statusColor).frame(width: 10, height: 10)
            }
            .padding(.horizontal, 20).padding(.top, 12)
            VStack(spacing: 2) {
                Text("Grammar — \(tenseTitle)").font(Passeport.display(19, weight: .semibold)).foregroundColor(Passeport.text)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text("\(min(cardIndex + 1, sessionPlan.count)) of \(sessionPlan.count) · \(statusText)")
                        .font(Passeport.mono(11.5)).foregroundColor(Passeport.slateDim)
                }
            }
            .padding(.top, 6)
        }
        .padding(.bottom, 12)
    }

    // Card layout mirrors AgentLedVocabView's exactly: English meaning on top (the "front"), the
    // French sentence big and maroon below (the "back", pulses when Marie says it), and the
    // grammar note in an "Example"-style card underneath — same shape as vocab's example sentence
    // card, just carrying the grammar explanation instead.
    @ViewBuilder
    private var content: some View {
        if let session = currentCard {
            let card = session.card
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Text(card.en).font(Passeport.display(20, weight: .medium)).foregroundColor(Passeport.text)
                    Text(card.fr)
                        .font(Passeport.display(20, weight: .medium))
                        .foregroundColor(Passeport.maroon)
                        .multilineTextAlignment(.center)
                        .scaleEffect(sentencePulse ? 1.05 : 1.0)
                }
                .frame(maxWidth: .infinity).passeportCard(padding: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(sentencePulse ? Passeport.brass : .clear, lineWidth: 2)
                )

                if !card.note.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        KickerText(text: "Grammar note", color: Passeport.slateDim)
                        Text(card.note).font(Passeport.body(13, weight: .medium)).foregroundColor(Passeport.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).passeportCard()
                }

                Text("Say the sentence out loud — Marie is listening. Say \"next\" when you're ready, or \"again\" to hear it once more.")
                    .font(Passeport.mono(10.5)).foregroundColor(Passeport.slateDim).multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button { goBackFromUserIntent() } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(Passeport.body(13, weight: .medium))
                            .foregroundColor(cardIndex == 0 ? Passeport.slateDim.opacity(0.5) : Passeport.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Passeport.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Passeport.hairline, lineWidth: 1))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(cardIndex == 0)

                    Button { advanceFromUserIntent() } label: {
                        Label("Next", systemImage: "chevron.right")
                            .font(Passeport.body(13, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PasseportPrimaryButton())
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 30)).foregroundColor(Passeport.brass)
                Text(isWrappingUp ? "Wrapping up…" : "All done!").font(Passeport.body(14, weight: .medium)).foregroundColor(Passeport.text)
            }
            .frame(maxWidth: .infinity).passeportCard()
        }
    }

    private var debugPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(debugLog.enumerated()), id: \.offset) { i, line in
                        Text(line)
                            .font(Passeport.mono(9.5))
                            .foregroundColor(Passeport.slateDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .frame(height: 110)
            .background(Color.black.opacity(0.85))
            .onChange(of: debugLog.count) { _ in
                withAnimation { proxy.scrollTo(debugLog.count - 1, anchor: .bottom) }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 40) {
            Button { toggleMute() } label: {
                VStack(spacing: 6) {
                    Image(systemName: callStatus == .muted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 22)).foregroundColor(.white)
                        .frame(width: 54, height: 54)
                        .background(callStatus == .muted ? Passeport.slate : Passeport.maroon)
                        .clipShape(Circle())
                    Text(callStatus == .muted ? "Muted" : "Mic on").font(Passeport.mono(10)).foregroundColor(Passeport.slateDim)
                }
            }
            .disabled(callStatus == .connecting || callStatus == .ended)

            Button { showEndConfirm = true } label: {
                VStack(spacing: 6) {
                    Image(systemName: "phone.down.fill").font(.system(size: 22)).foregroundColor(.white)
                        .frame(width: 54, height: 54).background(Color(red: 0.85, green: 0.2, blue: 0.2)).clipShape(Circle())
                    Text("End").font(Passeport.mono(10)).foregroundColor(Passeport.slateDim)
                }
            }
        }
        .padding(.vertical, 20)
    }

    private var statusColor: Color {
        switch callStatus {
        case .connecting: return .orange
        case .listening: return .green
        case .tutorSpeaking: return Passeport.maroon
        case .muted: return Passeport.slate
        case .ended: return Passeport.slate.opacity(0.5)
        }
    }
    private var statusText: String {
        switch callStatus {
        case .connecting: return "connecting…"
        case .listening: return "listening"
        case .tutorSpeaking: return "Marie is speaking"
        case .muted: return "muted"
        case .ended: return "ended"
        }
    }

    private func toggleMute() {
        if callStatus == .muted {
            do { try audio.startStreaming { chunk in gemini.sendAudioChunk(chunk) }; callStatus = .listening }
            catch { errorMessage = "Failed to unmute: \(error.localizedDescription)" }
        } else {
            audio.stopStreaming()
            callStatus = .muted
        }
    }

    private func formatDuration(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

    private func setupCallbacks() {
        gemini.onConnected = {
            callStatus = .listening
            if timer == nil { timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in callDuration += 1 } }
            audio.requestPermission { granted in
                if granted {
                    do { try audio.startStreaming { chunk in gemini.sendAudioChunk(chunk) } }
                    catch { errorMessage = "Mic error: \(error.localizedDescription)" }
                } else {
                    errorMessage = "Microphone permission denied"
                }
            }
        }
        gemini.onDisconnected = { if !finished { errorMessage = "Connection lost"; finishAndReturn() } }
        gemini.onError = { msg in errorMessage = msg }
        gemini.onUserTranscript = { text in recorder.logUser(text); handleUserTranscript(text) }
        gemini.onTutorTranscript = { text in recorder.logTutor(text) }
        gemini.onAudioChunk = { data in
            lastAudioChunkAt = Date()
            audio.isOutputActive = true
            audio.playAudioChunk(data)
            if callStatus != .tutorSpeaking { callStatus = .tutorSpeaking }
        }
        gemini.onTurnComplete = {
            audio.isOutputActive = false
            if callStatus != .muted { callStatus = .listening }
            if isWrappingUp { finishAndReturn() }
        }
        gemini.onInterrupted = {
            audio.isOutputActive = false
            audio.stopPlayback()
            if callStatus != .muted { callStatus = .listening }
        }
        gemini.onToolCall = { name, args, callId in handleToolCall(name: name, args: args, callId: callId) }
        gemini.onTranscriptDelta = { delta in handleTranscriptDelta(delta) }

        speakingWatchdog?.invalidate()
        speakingWatchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if callStatus == .tutorSpeaking, Date().timeIntervalSince(lastAudioChunkAt) > 2.5 {
                audio.isOutputActive = false
                callStatus = .listening
            }
        }
    }

    // MARK: - The gate: same shape as vocab, walking one generated sentence card at a time

    private func handleUserTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        hasAttempted = true
        let intent = detectIntent(trimmed)
        lastDetectedIntent = intent
        logDebug("heard: \"\(trimmed)\" → intent: \(intent.rawValue)")
        switch intent {
        case .advance: advanceFromUserIntent()
        case .back: goBackFromUserIntent()
        case .again, .none: break
        }
    }

    private static let pacingReminder = """
    Reminder: this is a total beginner — explain primarily in English, using French only for \
    the target sentence itself, not full French explanations. Keep grammar SIMPLE — no advanced \
    tense talk beyond the note shown, this is intentionally basic for now. Do at least one full \
    pass (say the sentence, have them repeat it, react, explain the grammar note) before you even \
    suggest moving on.
    """

    private func advanceFromUserIntent() {
        guard currentCard != nil else { return }
        logDebug("→ user-driven advance")
        performAdvance()
        if let next = currentCard {
            gemini.injectContext("The student has moved on to the next sentence: \"\(next.card.fr)\" (\(next.card.en)). Grammar note: \(next.card.note) \(Self.pacingReminder)")
        } else {
            wrapUp()
        }
    }

    private func goBackFromUserIntent() {
        guard cardIndex > 0 else { return }
        logDebug("→ user-driven go back")
        performGoBack()
        if let card = currentCard {
            gemini.injectContext("The student asked to go back to: \"\(card.card.fr)\" (\(card.card.en)). Grammar note: \(card.card.note) \(Self.pacingReminder)")
        }
    }

    private func performAdvance() {
        if hasAttempted, !wasGraded {
            drillResults.append(lastDetectedIntent != .again)
            wasGraded = true
        }
        cardIndex += 1
        resetPerCardState()
    }

    private func performGoBack() {
        cardIndex -= 1
        resetPerCardState()
    }

    private func detectIntent(_ text: String) -> GrammarUserIntent {
        let t = fold(text)

        // Same ambiguity guard as vocab: if the utterance is nothing but the current sentence
        // itself (the student practicing it), never misread that as a navigation command even if
        // it happens to contain a word that overlaps a keyword below.
        if let card = currentCard {
            let cleaned = t.trimmingCharacters(in: CharacterSet(charactersIn: ".!?,"))
            let targetFr = fold(card.card.fr)
            if !targetFr.isEmpty, cleaned == targetFr {
                logDebug("→ intent suppressed: utterance is just today's sentence, treating as practice not a command")
                return .none
            }
        }

        let backKeywords = ["go back", "back to the", "back up", "previous", "the one before", "last sentence", "redo the last", "revenons"]
        let againKeywords = ["again", "repeat", "one more time", "say it again", "encore", "repete", "repète", "une fois de plus"]
        let advanceKeywords = ["next", "move on", "got it", "i know this", "i know", "ready", "continue", "yes", "yeah", "yep", "sure", "sounds good", "let's go", "d'accord", "suivant", "on continue", "oui"]
        if backKeywords.contains(where: { t.contains($0) }) { return .back }
        if againKeywords.contains(where: { t.contains($0) }) { return .again }
        if advanceKeywords.contains(where: { t.contains($0) }) { return .advance }
        return .none
    }

    private func handleToolCall(name: String, args: [String: Any], callId: String) {
        logDebug("proposed: \(name)(\(args)) [card \(cardIndex + 1), attempted=\(hasAttempted), intent=\(lastDetectedIntent.rawValue)]")

        if handledCallIds.contains(callId) {
            logDebug("→ DUPLICATE call ID, ignoring side effects")
            gemini.sendToolResponse(callId: callId, name: name, result: ["ok": true], scheduling: "SILENT")
            return
        }
        handledCallIds.insert(callId)

        switch name {
        case "mark_result":
            if lastDetectedIntent == .again {
                logDebug("→ REJECTED (intent=again)")
                gemini.sendToolResponse(callId: callId, name: name, result: [
                    "ok": false, "reason": "The student asked to try again — don't grade yet."
                ])
                return
            }
            guard hasAttempted, currentCard != nil else {
                logDebug("→ REJECTED (no attempt yet)")
                gemini.sendToolResponse(callId: callId, name: name, result: [
                    "ok": false, "reason": "The student hasn't attempted this sentence yet."
                ])
                return
            }
            if wasGraded {
                logDebug("→ already graded this instance, acknowledging only")
                gemini.sendToolResponse(callId: callId, name: name, result: ["ok": true], scheduling: "SILENT")
                return
            }
            if let gradeStr = args["grade"] as? String {
                wasGraded = true
                drillResults.append(gradeStr != "again")
                logDebug("→ ACCEPTED, graded \(gradeStr)")
                gemini.sendToolResponse(callId: callId, name: name, result: ["ok": true], scheduling: "SILENT")
            } else {
                logDebug("→ REJECTED (bad grade arg)")
                gemini.sendToolResponse(callId: callId, name: name, result: ["ok": false], scheduling: "SILENT")
            }

        default:
            logDebug("→ unknown tool \(name)")
            gemini.sendToolResponse(callId: callId, name: name, result: ["ok": false, "error": "unknown tool"])
        }
    }

    private func logDebug(_ message: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        debugLog.append("[\(time)] \(message)")
        if debugLog.count > 40 { debugLog.removeFirst(debugLog.count - 40) }
    }

    private func resetPerCardState() {
        hasAttempted = false
        wasGraded = false
        lastDetectedIntent = .none
        spokenSentenceMatched = false
        recentTranscriptBuffer = ""
    }

    private func handleTranscriptDelta(_ delta: String) {
        guard !spokenSentenceMatched, let card = currentCard else { return }
        recentTranscriptBuffer += delta
        if recentTranscriptBuffer.count > 300 {
            recentTranscriptBuffer = String(recentTranscriptBuffer.suffix(300))
        }
        let target = fold(card.card.fr)
        guard !target.isEmpty, fold(recentTranscriptBuffer).contains(target) else { return }
        spokenSentenceMatched = true
        withAnimation(.easeInOut(duration: 0.25)) { sentencePulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeInOut(duration: 0.25)) { sentencePulse = false }
        }
    }

    private func fold(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr-FR")).lowercased()
    }

    private func wrapUp() {
        guard !isWrappingUp else { return }
        isWrappingUp = true
        gemini.injectContext("The student has now gone through today's grammar practice. Say a short warm closing line (one sentence) congratulating them, then stop talking.")
    }

    private func finishAndReturn() {
        guard !finished else { return }
        finished = true
        timer?.invalidate()
        speakingWatchdog?.invalidate()
        audio.stopStreaming()
        gemini.disconnect()
        callStatus = .ended
        if cardIndex > 0 {
            let score = drillResults.isEmpty ? nil : Double(drillResults.filter { $0 }.count) / Double(drillResults.count)
            store.setLessonStatus(topicId, status: (score ?? 1.0) >= 0.8 ? "completed" : "in_progress", score: score)
            store.saveDiaryEntry(stage: "grammar", summary: "Practiced \(tenseTitle) in a live grammar session.")
        }
        recorder.finish(summary: cardIndex > 0 ? "Practiced \(min(cardIndex, sessionPlan.count)) sentence(s) on \(tenseTitle)." : "Ended early.")
        onComplete(GrammarStageResult(topicTitle: tenseTitle, drillResults: drillResults))
        dismiss()
    }

    private static func buildContext(tenseTitle: String, plan: [GrammarSessionCard], focusNote: String?, vocabSummary: VocabStageResult?) -> String {
        guard !plan.isEmpty else {
            return "GRAMMAR STAGE: nothing to practice today. Briefly tell the student there's nothing new and that they can end the call whenever ready."
        }
        var parts: [String] = []
        parts.append("""
        GRAMMAR STAGE — this is a focused grammar session on ONE tense/topic ("\(tenseTitle)"), \
        walked through one short French sentence at a time, exactly like the vocab session that \
        just happened but for a full sentence instead of a single word. The student's screen \
        ALREADY shows the English meaning, the French sentence, and a grammar note the instant it \
        appears — you never need to reveal anything.

        CRITICAL — SPEAK PRIMARILY IN ENGLISH, THIS STUDENT DOES NOT SPEAK FRENCH YET: all of your \
        own explaining, encouragement, instructions, and questions should be in English — French \
        should only appear as the sentence itself, never as your own explanatory language.

        CRITICAL — YOU DO NOT CONTROL PACING, THE STUDENT DOES: you have no tool to advance or go \
        back. The app watches the student's own words directly and moves the card itself the \
        instant they say something like "next" or "go back" — zero involvement from you. You'll \
        simply be told the new current sentence afterward and should react to it naturally.

        You have exactly one tool: mark_result, for recording how well the student did with the \
        current sentence (grade: again/good/easy). It's a proposal — the app only accepts it once \
        it's confirmed the student actually attempted the sentence. A rejection is not an error; \
        never mention it, just keep teaching naturally.

        CRITICAL — FOLLOW THIS EXACT ORDER FOR EVERY SENTENCE:
          1. Say the French sentence clearly, paired with its English meaning.
          2. Ask the student to repeat it, and give them a real beat of silence to actually try.
          3. React briefly to their attempt.
          4. THEN explain the grammar note already shown on screen, in plain simple English.
          5. ONLY NOW ask if they're ready to move on, and wait for their actual answer.
        Keep grammar explanations SIMPLE — no advanced tense talk beyond the note shown, this is \
        intentionally basic for now; a harder/dynamic-difficulty version comes later.
        """)
        let lines = plan.enumerated().map { i, session in "\(i + 1). \(session.card.fr) = \(session.card.en) — \(session.card.note)" }
        parts.append("TODAY'S SENTENCES (\(plan.count)):\n" + lines.joined(separator: "\n"))
        if let focusNote, !focusNote.isEmpty {
            parts.append("TODAY'S FOCUS (mention this naturally near the start): \(focusNote)")
        }
        if let vocabSummary, !vocabSummary.wordsCovered.isEmpty {
            let words = vocabSummary.wordsCovered.map { $0.fr }.joined(separator: ", ")
            parts.append("VOCABULARY JUST COVERED (previous stage, these sentences reuse some of these words): \(words)")
        }
        return parts.joined(separator: "\n\n")
    }
}
