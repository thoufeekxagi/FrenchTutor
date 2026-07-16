import SwiftUI

struct ListeningStageResult {
    let grammarDrillResults: [Bool]
    let listeningCorrect: Int
    let listeningAttempted: Int
}

private struct ReadingSessionCard {
    let segment: ReadingSegment
}

private enum ReadingUserIntent: String {
    case advance
    case again
    case back
    case none
}

/// Daily Pathway stage 2 — rebuilt against the same rule as `AgentLedVocabView`: Marie teaches,
/// the app owns every navigation decision. Walks through a pre-built `ReadingPassage` (either
/// LLM-assembled once from the vocab just practiced, or mapped offline from an existing lab
/// script — see `PostVocabChoiceView`) one word/phrase segment at a time, the exact same way
/// vocab walks through one word at a time. See STRUCTURE.md for the full rationale; this view
/// used to give the model show_conjugation/ask_drill/show_question as tools it called on its own
/// initiative, which had the same pacing/desync problems vocab had before its own fix.
struct AgentLedListeningView: View {
    let passage: ReadingPassage
    var vocabSummary: VocabStageResult? = nil
    var onComplete: (ListeningStageResult) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var gemini: GeminiLiveService
    private let audio = AudioStreamingService()
    private let store = LearningStore()
    private let recorder = SessionRecorder(stage: "reading_listening", topic: "Reading & Listening")
    private let sessionPlan: [ReadingSessionCard]

    @State private var callStatus: CallStatus = .connecting
    @State private var callDuration = 0
    @State private var timer: Timer?
    @State private var errorMessage = ""
    @State private var showEndConfirm = false
    @State private var finished = false
    @State private var isWrappingUp = false

    @State private var lastAudioChunkAt = Date()
    @State private var speakingWatchdog: Timer?

    @State private var segmentIndex = 0
    @State private var reviewedCount = 0

    // Same live debug log as vocab's — every gate decision and detected intent, visible in
    // real time rather than a black box.
    @State private var debugLog: [String] = []

    @State private var hasAttempted = false
    @State private var attemptCount = 0
    @State private var wasGraded = false
    @State private var lastDetectedIntent: ReadingUserIntent = .none

    // Documented Gemini Live bug: dedupe identical tool calls fired in rapid succession.
    @State private var handledCallIds: Set<String> = []

    // Same context-aware Flash-Lite intent judge as vocab's — keyword matcher kept only as
    // the automatic fallback. See AgentLedVocabView for the full rationale on each piece.
    private static let useLLMIntentJudge = true
    @State private var utteranceSeq = 0
    @State private var pendingIntentTask: Task<Void, Never>? = nil
    @State private var lastTutorLine = ""
    @State private var announceWorkItem: DispatchWorkItem? = nil

    init(passage: ReadingPassage, vocabSummary: VocabStageResult? = nil, onComplete: @escaping (ListeningStageResult) -> Void) {
        self.passage = passage
        self.vocabSummary = vocabSummary
        self.onComplete = onComplete
        let plan = passage.segments.map { ReadingSessionCard(segment: $0) }
        self.sessionPlan = plan
        let context = AgentLedListeningView.buildContext(passage: passage, plan: plan, vocabSummary: vocabSummary)
        _gemini = State(initialValue: GeminiLiveService(apiKey: geminiApiKey, lessonContext: context, tools: AgentTool.readingPalette))
    }

    private var currentCard: ReadingSessionCard? {
        segmentIndex < sessionPlan.count ? sessionPlan[segmentIndex] : nil
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
        .alert("End this section?", isPresented: $showEndConfirm) {
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
                Text("Reading & Listening").font(Passeport.display(20, weight: .semibold)).foregroundColor(Passeport.text)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text("\(min(segmentIndex + 1, sessionPlan.count)) of \(sessionPlan.count) · \(statusText)")
                        .font(Passeport.mono(11.5)).foregroundColor(Passeport.slateDim)
                }
            }
            .padding(.top, 6)
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                KickerText(text: passage.title, color: Passeport.slateDim)
                Text(passage.fullText).font(Passeport.body(13)).foregroundColor(Passeport.slateDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading).passeportCard()

            if let card = currentCard {
                VStack(spacing: 10) {
                    Text(card.segment.fr).font(Passeport.display(22, weight: .medium)).foregroundColor(Passeport.maroon)
                    if !card.segment.en.isEmpty {
                        Text(card.segment.en).font(Passeport.display(16, weight: .medium)).foregroundColor(Passeport.text)
                    }
                }
                .frame(maxWidth: .infinity).passeportCard(padding: 24)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        KickerText(text: "Grammar note", color: Passeport.slateDim)
                        Text(card.segment.grammarNote).font(Passeport.body(13)).foregroundColor(Passeport.text)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        KickerText(text: "Pronunciation", color: Passeport.slateDim)
                        Text(card.segment.pronunciationTip).font(Passeport.body(13)).foregroundColor(Passeport.text)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).passeportCard()

                Text("Repeat it out loud — Marie is listening. Say \"next\" when you're ready, or \"again\" to hear it once more.")
                    .font(Passeport.mono(10.5)).foregroundColor(Passeport.slateDim).multilineTextAlignment(.center)

                // Same guaranteed navigation fallback as vocab — Back/Next always work, no
                // dependency on speech recognition or the model.
                HStack(spacing: 12) {
                    Button { goBackFromUserIntent() } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(Passeport.body(13, weight: .medium))
                            .foregroundColor(segmentIndex == 0 ? Passeport.slateDim.opacity(0.5) : Passeport.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Passeport.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Passeport.hairline, lineWidth: 1))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(segmentIndex == 0)

                    Button { advanceFromUserIntent() } label: {
                        Label("Next", systemImage: "chevron.right")
                            .font(Passeport.body(13, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PasseportPrimaryButton())
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 30)).foregroundColor(Passeport.brass)
                    Text(isWrappingUp ? "Wrapping up…" : "All done!").font(Passeport.body(14, weight: .medium)).foregroundColor(Passeport.text)
                    Button { finishAndReturn() } label: { Text("Continue to Speaking →") }
                        .buttonStyle(PasseportPrimaryButton())
                        .padding(.horizontal, 40).padding(.top, 6)
                }
                .frame(maxWidth: .infinity).passeportCard()
            }
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
        gemini.onTutorTranscript = { text in recorder.logTutor(text); lastTutorLine = text }
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

        speakingWatchdog?.invalidate()
        speakingWatchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if callStatus == .tutorSpeaking, Date().timeIntervalSince(lastAudioChunkAt) > 2.5 {
                audio.isOutputActive = false
                callStatus = .listening
            }
        }
    }

    // MARK: - The gate: identical shape to AgentLedVocabView's, walking segments instead of words

    private func handleUserTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        hasAttempted = true

        guard Self.useLLMIntentJudge else {
            applyIntent(mapKeywordIntent(detectIntent(trimmed)), utterance: trimmed, source: "keyword")
            return
        }

        utteranceSeq += 1
        let seq = utteranceSeq
        let segmentIndexAtLaunch = segmentIndex
        let card = currentCard
        let tutorLine = lastTutorLine
        let attempts = attemptCount
        pendingIntentTask?.cancel()
        logDebug("heard: \"\(trimmed)\" → judging…")

        pendingIntentTask = Task {
            var verdict: LessonAgentService.LiveNavIntent
            var source = "judge"
            do {
                verdict = try await LessonAgentService.shared.classifyLiveIntent(
                    utterance: trimmed,
                    cardDescription: card.map { "passage segment \"\($0.segment.fr)\" = \"\($0.segment.en)\"" } ?? "(session already finished)",
                    tutorLastLine: tutorLine,
                    attemptCount: attempts
                )
            } catch {
                verdict = mapKeywordIntent(detectIntent(trimmed))
                source = "keyword-fallback"
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard seq == utteranceSeq, segmentIndexAtLaunch == segmentIndex, !finished else {
                    logDebug("→ stale verdict (\(verdict.rawValue)) discarded")
                    return
                }
                applyIntent(verdict, utterance: trimmed, source: source)
            }
        }
    }

    private func mapKeywordIntent(_ intent: ReadingUserIntent) -> LessonAgentService.LiveNavIntent {
        switch intent {
        case .advance: return .advance
        case .back: return .back
        case .again: return .again
        case .none: return .attempt
        }
    }

    private func applyIntent(_ verdict: LessonAgentService.LiveNavIntent, utterance: String, source: String) {
        logDebug("[\(source)] \"\(utterance)\" → \(verdict.rawValue), attempts: \(attemptCount)")
        switch verdict {
        case .attempt:
            lastDetectedIntent = .none
            attemptCount += 1
        case .chat:
            lastDetectedIntent = .none
        case .again:
            lastDetectedIntent = .again
        case .advance:
            lastDetectedIntent = .advance
            advanceFromUserIntent()
        case .back:
            lastDetectedIntent = .back
            goBackFromUserIntent()
        }
    }

    private static let pacingReminder = """
    Reminder: this is a total beginner — explain primarily in English, using French only for \
    the target word/phrase itself, never full French explanations. Do at least 2 full passes \
    (read it, have them repeat, react, walk through the grammar note and pronunciation tip) \
    before you even suggest moving on.
    """

    private func advanceFromUserIntent() {
        guard currentCard != nil else { return }
        logDebug("→ user-driven advance")
        cutTutorAudio()
        performAdvance()
        if let next = currentCard {
            scheduleCardAnnouncement(Self.contextNote(for: next.segment, prefix: "The student has moved on to the next part of the passage") + " Announce the new segment briefly out loud, then teach it.")
        } else {
            wrapUp()
        }
    }

    private func goBackFromUserIntent() {
        guard segmentIndex > 0 else { return }
        logDebug("→ user-driven go back")
        cutTutorAudio()
        performGoBack()
        if let card = currentCard {
            scheduleCardAnnouncement(Self.contextNote(for: card.segment, prefix: "The student asked to go back to") + " Briefly re-introduce it out loud, then pick up teaching it again.")
        }
    }

    /// See AgentLedVocabView.cutTutorAudio — flushing local playback silences her instantly.
    private func cutTutorAudio() {
        audio.stopPlayback()
        audio.isOutputActive = false
        if callStatus == .tutorSpeaking { callStatus = .listening }
    }

    /// Debounced spoken card announcement — rapid skips only announce the landing segment.
    private func scheduleCardAnnouncement(_ note: String) {
        announceWorkItem?.cancel()
        let item = DispatchWorkItem { gemini.injectContext(note, expectReply: true) }
        announceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    private static func contextNote(for segment: ReadingSegment, prefix: String) -> String {
        let meaning = segment.en.isEmpty ? "" : " = \(segment.en)"
        return "\(prefix): \"\(segment.fr)\"\(meaning). Grammar note to mention: \(segment.grammarNote) Pronunciation tip: \(segment.pronunciationTip) \(pacingReminder)"
    }

    private func performAdvance() {
        if hasAttempted, !wasGraded { wasGraded = true }
        if currentCard != nil { reviewedCount += 1 }
        segmentIndex += 1
        resetPerCardState()
    }

    private func performGoBack() {
        segmentIndex -= 1
        resetPerCardState()
    }

    private func detectIntent(_ text: String) -> ReadingUserIntent {
        let t = fold(text)

        // Same ambiguity guard as vocab: if the utterance is just today's segment itself, that's
        // a practice attempt, never navigation — even if the segment text happens to overlap a
        // nav keyword (e.g. a passage segment that is itself "oui").
        if let card = currentCard {
            let cleaned = t.trimmingCharacters(in: CharacterSet(charactersIn: ".!?,"))
            let targetFr = fold(card.segment.fr)
            let targetEn = fold(card.segment.en)
            let words = cleaned.split(separator: " ").map(String.init)
            if !words.isEmpty, !targetFr.isEmpty, words.allSatisfy({ $0 == targetFr || $0 == targetEn }) {
                logDebug("→ intent suppressed: utterance is just the current segment (\"\(card.segment.fr)\"), treating as practice not a command")
                return .none
            }
        }

        let backKeywords = ["go back", "back to the", "back up", "previous", "the one before", "last part", "redo the last", "revenons"]
        let againKeywords = ["again", "repeat", "one more time", "say it again", "encore", "repete", "repète", "une fois de plus"]
        let advanceKeywords = ["next", "move on", "got it", "i know this", "i know", "ready", "continue", "yes", "yeah", "yep", "sure", "sounds good", "let's go", "d'accord", "suivant", "on continue", "oui"]
        if backKeywords.contains(where: { t.contains($0) }) { return .back }
        if againKeywords.contains(where: { t.contains($0) }) { return .again }
        if advanceKeywords.contains(where: { t.contains($0) }) { return .advance }
        return .none
    }

    private func handleToolCall(name: String, args: [String: Any], callId: String) {
        logDebug("proposed: \(name)(\(args)) [segment \(segmentIndex + 1), attempted=\(hasAttempted), intent=\(lastDetectedIntent.rawValue)]")

        if handledCallIds.contains(callId) {
            logDebug("→ DUPLICATE call ID, ignoring side effects")
            gemini.sendToolResponse(callId: callId, name: name, result: ["ok": true], scheduling: "SILENT")
            return
        }
        handledCallIds.insert(callId)

        switch name {
        case "mark_segment_result":
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
                    "ok": false, "reason": "The student hasn't attempted this segment yet — listen for their attempt before grading."
                ])
                return
            }
            if wasGraded {
                logDebug("→ already graded this instance, acknowledging only")
                gemini.sendToolResponse(callId: callId, name: name, result: ["ok": true], scheduling: "SILENT")
                return
            }
            wasGraded = true
            logDebug("→ ACCEPTED")
            gemini.sendToolResponse(callId: callId, name: name, result: ["ok": true], scheduling: "SILENT")

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
        attemptCount = 0
        wasGraded = false
        lastDetectedIntent = .none
    }

    private func fold(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr-FR")).lowercased()
    }

    private func wrapUp() {
        guard !isWrappingUp else { return }
        isWrappingUp = true
        gemini.injectContext("The student has now gone through the whole passage. Say a short warm closing line (one sentence) congratulating them, then stop talking.", expectReply: true)
    }

    private func finishAndReturn() {
        guard !finished else { return }
        finished = true
        timer?.invalidate()
        speakingWatchdog?.invalidate()
        pendingIntentTask?.cancel()
        announceWorkItem?.cancel()
        audio.stopStreaming()
        gemini.disconnect()
        callStatus = .ended
        if reviewedCount > 0 {
            store.saveDiaryEntry(stage: "reading", summary: "Read through \(reviewedCount) part(s) of \"\(passage.title)\" in a live reading/listening session.")
        }
        recorder.finish(summary: reviewedCount > 0 ? "Read through \(reviewedCount) part(s) of \"\(passage.title)\"." : "Ended early.")
        onComplete(ListeningStageResult(grammarDrillResults: [], listeningCorrect: reviewedCount, listeningAttempted: reviewedCount))
        dismiss()
    }

    private static func buildContext(passage: ReadingPassage, plan: [ReadingSessionCard], vocabSummary: VocabStageResult?) -> String {
        guard !plan.isEmpty else {
            return "READING & LISTENING STAGE: no passage available today. Briefly tell the student there's nothing to read right now and that they can end the call whenever ready."
        }
        var parts: [String] = []
        parts.append("""
        READING & LISTENING STAGE — walking through a short French passage, one word or short \
        phrase at a time, exactly the way the vocab stage teaches one word at a time. The \
        student's screen ALREADY shows the current segment's French text and English meaning the \
        instant it appears — you never need to reveal anything.

        CRITICAL — SPEAK PRIMARILY IN ENGLISH, THIS STUDENT DOES NOT SPEAK FRENCH YET: all of \
        your own explaining, encouragement, instructions, and questions should be in English — \
        French should only ever appear as the current segment itself, never as your own \
        explanatory language. Never answer in French only, including when they ask you to repeat \
        something. If you catch yourself explaining something in French, stop and say it in \
        English instead.

        CRITICAL — YOU DO NOT CONTROL PACING, THE STUDENT DOES: you are NOT in charge of deciding \
        when to move to the next segment or go back, and you have no tool to do that yourself. \
        The app is watching the student's own words directly, and the instant they say something \
        like "next", "got it", "ready", or "go back", the app moves the segment itself — instantly, \
        with zero involvement from you. You'll simply be told the new current segment afterward \
        and should react to it naturally, as if you'd just turned the page together. Never say \
        things like "let's move on" as an announcement of an action you're about to take.

        You have exactly one tool: mark_segment_result, for recording how well the student did \
        with the current segment (grade: again/good/easy). It's a proposal — the app only accepts \
        it once it's confirmed the student actually attempted it. A rejection is not an error; \
        never mention it to the student, just keep teaching naturally.

        CRITICAL — FOLLOW THIS EXACT ORDER FOR EVERY SINGLE SEGMENT, DO NOT SKIP OR REORDER STEPS:
          1. Read the French word/phrase slowly and clearly, pairing it with its English meaning.
          2. Ask the student to repeat it, and give them a real beat of silence to actually try.
          3. React briefly to their attempt (encouragement, or a light correction).
          4. THEN explain the grammar note already shown on their screen (why this word/word \
             order is used) AND the pronunciation tip already shown, in your own words, briefly.
          5. ONLY NOW ask a genuine question about moving on — e.g. "Ready for the next part, or \
             want to try it once more?" — and wait for their actual answer next turn.
        This student is a true beginner: do at least 2 full passes of steps 1-4 before step 5, not \
        one. Keep grammar explanations SIMPLE — no conjugation tables, no advanced tense talk, this \
        is intentionally basic; a harder version comes later.
        """)
        let lines = plan.enumerated().map { i, card -> String in
            let meaning = card.segment.en.isEmpty ? "" : " = \(card.segment.en)"
            return "\(i + 1). \(card.segment.fr)\(meaning) — grammar note: \(card.segment.grammarNote) pronunciation tip: \(card.segment.pronunciationTip)"
        }
        parts.append("FULL PASSAGE TEXT: \(passage.fullText)")
        parts.append("SEGMENTS IN ORDER (\(plan.count)):\n" + lines.joined(separator: "\n"))
        if let vocabSummary, !vocabSummary.wordsCovered.isEmpty {
            let words = vocabSummary.wordsCovered.map { $0.fr }.joined(separator: ", ")
            parts.append("VOCABULARY JUST COVERED (in the previous stage, feel free to note the connection naturally if relevant): \(words)")
        }
        return parts.joined(separator: "\n\n")
    }
}
