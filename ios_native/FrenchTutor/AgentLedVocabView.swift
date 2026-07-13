import SwiftUI

struct VocabStageResult {
    let wordsCovered: [VocabEntry]
    let reviewedCount: Int
}

/// One word in the session plan — straight through in the given order, no interleaved
/// repeats. An earlier version resurfaced earlier words mid-session for extra practice, but
/// that broke the lesson's pacing/flow, so each word now appears exactly once per session.
private struct VocabSessionCard {
    let entry: VocabEntry
}

private enum UserIntent: String {
    case advance   // "next", "got it", "I know this" — explicit request to move on
    case again     // "again", "repeat that" — explicit request to stay
    case back      // "go back", "previous word", "redo the last one" — explicit request to revisit
    case none
}

/// Daily Pathway stage 1 — a focused, agent-led vocabulary session, redesigned around one
/// principle: Marie's tool calls are PROPOSALS, never commands. The app is the sole authority
/// over whether a word actually advances or gets graded — it verifies (via the student's own
/// transcript) that a real attempt happened, or that the student explicitly asked to move on,
/// before honoring next_card/mark_result at all. This exists because giving her that authority
/// directly caused the desync/duplicate/premature-grading bugs found in testing — she stays
/// fully expressive in HOW she teaches, she just no longer decides WHEN progress happens.
/// Example sentences are pre-generated once before the call starts (not invented live), so
/// content is fixed and known upfront — one less thing for a live model to get wrong.
struct AgentLedVocabView: View {
    let vocabQueue: [VocabEntry]
    var focusNote: String? = nil
    var examplesByWordId: [String: LessonAgentService.VocabExample] = [:]
    var onComplete: (VocabStageResult) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var gemini: GeminiLiveService
    private let audio = AudioStreamingService()
    private let store = LearningStore()
    private let sessionPlan: [VocabSessionCard]

    @State private var callStatus: CallStatus = .connecting
    @State private var callDuration = 0
    @State private var timer: Timer?
    @State private var errorMessage = ""
    @State private var showEndConfirm = false
    @State private var showAllWords = false
    @State private var finished = false
    @State private var isWrappingUp = false

    @State private var lastAudioChunkAt = Date()
    @State private var speakingWatchdog: Timer?

    @State private var cardIndex = 0
    @State private var reviewedCount = 0

    // Live debug log — every gate decision (accepted/rejected, why) and detected intent shows
    // up here in real time, so what the gate is doing is visible instead of a black box.
    @State private var debugLog: [String] = []

    // The gate's per-card state: has the student said anything since this card became
    // current, how many genuine attempts at the word (not nav commands like "next"/"again")
    // they've made, has it already been graded (guards against double-grading the same
    // instance), and what did their most recent utterance signal they want.
    @State private var hasAttempted = false
    @State private var attemptCount = 0
    @State private var wasGraded = false
    @State private var lastDetectedIntent: UserIntent = .none

    // Duplicate-call guard: Gemini Live is documented to occasionally fire the identical
    // tool call twice in rapid succession. Track handled IDs and no-op the repeat.
    @State private var handledCallIds: Set<String> = []

    // Transcript-driven sync: her spoken output streams word-by-word in lockstep with the
    // audio, so watching for the current word appearing there is a far more reliable "she's
    // saying this right now" signal than waiting on a separate tool call.
    @State private var recentTranscriptBuffer = ""
    @State private var spokenWordMatched = false
    @State private var wordPulse = false

    init(vocabQueue: [VocabEntry], focusNote: String? = nil, examplesByWordId: [String: LessonAgentService.VocabExample] = [:], onComplete: @escaping (VocabStageResult) -> Void) {
        self.vocabQueue = vocabQueue
        self.focusNote = focusNote
        self.examplesByWordId = examplesByWordId
        self.onComplete = onComplete
        let plan = AgentLedVocabView.buildSessionPlan(from: vocabQueue)
        self.sessionPlan = plan
        let tempStore = LearningStore()
        let isNewById: [String: Bool] = Dictionary(uniqueKeysWithValues: vocabQueue.map { entry in
            (entry.id, (tempStore.srsState(for: entry.id)?.reps ?? 0) == 0)
        })
        let context = AgentLedVocabView.buildContext(plan: plan, examples: examplesByWordId, isNewById: isNewById, focusNote: focusNote)
        _gemini = State(initialValue: GeminiLiveService(apiKey: geminiApiKey, lessonContext: context, tools: AgentTool.vocabPalette))
    }

    private var currentCard: VocabSessionCard? {
        cardIndex < sessionPlan.count ? sessionPlan[cardIndex] : nil
    }

    // Shown for every card, not just "new" words — an example is pre-generated for the whole
    // queue regardless of familiarity. An earlier version gated this on the word's SRS state,
    // which meant it silently stopped appearing for any word once it had been graded once (e.g.
    // across repeated testing), even though the sentence was sitting right there ready to show.
    private var currentExample: LessonAgentService.VocabExample? {
        guard let card = currentCard else { return nil }
        return examplesByWordId[card.entry.id]
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
        .alert("End vocabulary practice?", isPresented: $showEndConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("End", role: .destructive) { finishAndReturn() }
        } message: { Text("Words you've already reviewed are saved.") }
        .sheet(isPresented: $showAllWords) { allWordsSheet }
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
                Button { showAllWords = true } label: {
                    Image(systemName: "list.bullet").font(.system(size: 16)).foregroundColor(Passeport.text)
                }
            }
            .padding(.horizontal, 20).padding(.top, 12)
            VStack(spacing: 2) {
                Text("Vocabulary").font(Passeport.display(20, weight: .semibold)).foregroundColor(Passeport.text)
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

    @ViewBuilder
    private var content: some View {
        if let card = currentCard {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Text(card.entry.en).font(Passeport.display(24, weight: .medium)).foregroundColor(Passeport.text)
                    VStack(spacing: 4) {
                        Text(card.entry.fr)
                            .font(Passeport.display(22, weight: .medium))
                            .foregroundColor(Passeport.maroon)
                            .scaleEffect(wordPulse ? 1.08 : 1.0)
                        Text(card.entry.phonetic).font(Passeport.mono(13)).foregroundColor(Passeport.slateDim)
                    }
                }
                .frame(maxWidth: .infinity).passeportCard(padding: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(wordPulse ? Passeport.brass : .clear, lineWidth: 2)
                )

                if let example = currentExample {
                    VStack(alignment: .leading, spacing: 3) {
                        KickerText(text: "Example", color: Passeport.slateDim)
                        Text(example.fr).font(Passeport.body(13.5, weight: .medium)).foregroundColor(Passeport.text)
                        Text(example.en).font(Passeport.mono(10.5)).foregroundColor(Passeport.slateDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).passeportCard()
                }

                Text("Repeat the word out loud — Marie is listening. Say \"next\" when you're ready, or \"again\" to hear it once more.")
                    .font(Passeport.mono(10.5)).foregroundColor(Passeport.slateDim).multilineTextAlignment(.center)

                // Direct, guaranteed navigation that never depends on speech recognition or the
                // model — tap it and the card moves immediately, same as saying "next"/"back".
                HStack(spacing: 12) {
                    // Back is styled manually (no PasseportPrimaryButton), so its own vertical
                    // padding must match what that style already bakes in for Next — otherwise
                    // Next silently gets the style's padding stacked on top of its own and ends
                    // up visibly taller than Back.
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
                        Label("Next word", systemImage: "chevron.right")
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

    /// Live view into what the gate is actually doing — every tool call, accept/reject
    /// decision and reason, and detected intent, timestamped, newest at the bottom.
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

    private var allWordsSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(uniqueWords.enumerated()), id: \.element.id) { i, entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.en).font(Passeport.body(12.5)).foregroundColor(Passeport.slateDim)
                                Text(entry.fr).font(Passeport.body(14, weight: .medium)).foregroundColor(Passeport.text)
                            }
                            Spacer()
                            Text(entry.phonetic).font(Passeport.mono(11)).foregroundColor(Passeport.slateDim)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        if i < uniqueWords.count - 1 { Divider().overlay(Passeport.hairline) }
                    }
                }
            }
            .navigationTitle("Today's words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Close") { showAllWords = false } }
            }
        }
    }

    private var uniqueWords: [VocabEntry] { vocabQueue }

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
        gemini.onDisconnected = {
            if !finished { errorMessage = "Connection lost"; finishAndReturn() }
        }
        gemini.onError = { msg in errorMessage = msg }
        gemini.onUserTranscript = { text in handleUserTranscript(text) }
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

    // MARK: - The gate: everything below decides whether Marie's proposals get honored

    /// Runs on every completed chunk of the student's own speech. Marks that *something*
    /// happened this card (the broad "did they respond" signal the gate checks), detects an
    /// explicit navigational intent if present, and fires the invisible background judge.
    private func handleUserTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        hasAttempted = true
        let intent = detectIntent(trimmed)
        // Always reflect the MOST RECENT utterance, never let a stale "again"/"back" from an
        // earlier turn linger and silently block future advances — that was the root cause of
        // the "screen stuck while she keeps talking" bug: one ambiguous match years earlier in
        // the same card would never get cleared by a later normal attempt.
        lastDetectedIntent = intent
        // Only count genuine attempts at the word itself — "next"/"again"/"go back" are nav
        // commands, not practice, and shouldn't count toward the repetition a word still needs.
        if intent == .none {
            attemptCount += 1
        }
        logDebug("heard: \"\(trimmed)\" → intent: \(intent.rawValue), attempts: \(attemptCount)")
        // Only worth judging when it's NOT a recognized navigation command — "next"/"again"/
        // "go back" aren't pronunciation attempts, so sending them to the judge would just be
        // wasted tokens on every single "next" the student says (which happens a lot).
        if intent == .none {
            judgeAttempt(said: trimmed)
        }
        // Navigation is 100% driven by the student's own words, decided and executed by the
        // app right here — immediately, not after any delay, and not routed through Marie at
        // all. She has no next_card/previous_card tool anymore; she only finds out the current
        // word changed via the context note below and reacts to it in conversation.
        switch intent {
        case .advance: advanceFromUserIntent()
        case .back: goBackFromUserIntent()
        case .again, .none: break
        }
    }

    /// Executes an advance the app itself decided on — from detected speech intent or a direct
    /// UI tap, the two are identical from here. No model involved in the decision at all.
    // The system prompt's pacing/beginner rules are set once at connect time, and in testing
    // her adherence to them visibly degraded a handful of words into a long session (a known
    // long-context instruction-following issue, not something a one-time prompt fixes). Rather
    // than trust the original instructions to still be "loaded" ten cards later, every context
    // note sent on a card change re-states the core rules — so they're re-grounded fresh at
    // exactly the moment she starts teaching something new.
    private static let pacingReminder = """
    Reminder: this is a total beginner — explain primarily in English, using French only for \
    the target word and its example sentence, not full French explanations. Do at least 4-5 \
    full passes (say the word, have them repeat, react, walk through the example sentence) \
    before you even suggest moving on — never propose it after just one or two repeats.
    """

    private func advanceFromUserIntent() {
        guard currentCard != nil else { return }
        logDebug("→ user-driven advance")
        performAdvance()
        if let next = currentCard {
            let example = examplesByWordId[next.entry.id].map { " Example sentence to teach through: \"\($0.fr)\" (\($0.en))." } ?? ""
            gemini.injectContext("The student has moved on to the next word: \(next.entry.fr) = \(next.entry.en).\(example) \(Self.pacingReminder)")
        } else {
            wrapUp()
        }
    }

    private func goBackFromUserIntent() {
        guard cardIndex > 0 else { return }
        logDebug("→ user-driven go back")
        performGoBack()
        if let card = currentCard {
            let example = examplesByWordId[card.entry.id].map { " Example sentence to teach through: \"\($0.fr)\" (\($0.en))." } ?? ""
            gemini.injectContext("The student asked to go back to: \(card.entry.fr) = \(card.entry.en).\(example) \(Self.pacingReminder)")
        }
    }

    /// The actual card-advance side effects (grading, index, reset) — shared by the accepted
    /// tool-call path and the watchdog's local-override path so they can never drift apart.
    private func performAdvance() {
        if hasAttempted, !wasGraded, let card = currentCard {
            SRSService(store: store).grade(entryId: card.entry.id, grade: .good)
            wasGraded = true
        }
        if currentCard != nil { reviewedCount += 1 }
        cardIndex += 1
        resetPerCardState()
    }

    private func performGoBack() {
        cardIndex -= 1
        resetPerCardState()
    }

    private func detectIntent(_ text: String) -> UserIntent {
        let t = fold(text)

        // Ambiguity guard: some vocab words we actually teach — "oui", "encore", "continuer" —
        // are themselves navigation keywords below ("oui"/"yes" = advance, "encore" = again).
        // If the utterance is nothing but the target word itself (repeated or not), that's the
        // student practicing THIS word, not issuing a command — a bare "oui" said while "oui"
        // is on screen must count as their attempt, never an auto-advance. Only a longer phrase
        // that clearly adds command language on top ("yes, next", "oui, on continue") should
        // still be read as real navigation intent even when the target word overlaps a keyword.
        if let card = currentCard {
            let cleaned = t.trimmingCharacters(in: CharacterSet(charactersIn: ".!?,"))
            let targetFr = fold(card.entry.fr)
            let targetEn = fold(card.entry.en)
            let words = cleaned.split(separator: " ").map(String.init)
            if !words.isEmpty, !targetFr.isEmpty, words.allSatisfy({ $0 == targetFr || $0 == targetEn }) {
                logDebug("→ intent suppressed: utterance is just today's word (\"\(card.entry.fr)\"), treating as practice not a command")
                return .none
            }
        }

        let backKeywords = ["go back", "back to the", "back up", "previous word", "previous one", "the one before", "word before", "last word", "redo the last", "go to the last", "revenons", "mot précédent", "mot precedent"]
        let againKeywords = ["again", "repeat", "one more time", "say it again", "encore", "repete", "repète", "une fois de plus"]
        // Includes plain confirmation words ("yes", "sure", "oui") since she now asks a real
        // question before advancing ("should we move on?") and the student's answer to that is
        // usually just a bare yes/no, not a fresh "next" — that answer must still count as an
        // explicit advance so the gate doesn't block on a technicality.
        let advanceKeywords = ["next", "move on", "got it", "i know this", "i know", "ready", "continue", "yes", "yeah", "yep", "sure", "sounds good", "let's go", "d'accord", "suivant", "je sais", "on continue", "oui"]
        if backKeywords.contains(where: { t.contains($0) }) { return .back }
        if againKeywords.contains(where: { t.contains($0) }) { return .again }
        if advanceKeywords.contains(where: { t.contains($0) }) { return .advance }
        return .none
    }

    private func handleToolCall(name: String, args: [String: Any], callId: String) {
        logDebug("proposed: \(name)(\(args)) [card \(cardIndex + 1), attempted=\(hasAttempted), intent=\(lastDetectedIntent.rawValue)]")

        // Documented Gemini Live bug: the identical tool call can arrive twice in rapid
        // succession. If we've already handled this exact call ID, don't re-apply its
        // side effects — just acknowledge so she isn't left waiting on a response.
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
            guard hasAttempted, let card = currentCard else {
                logDebug("→ REJECTED (no attempt yet)")
                gemini.sendToolResponse(callId: callId, name: name, result: [
                    "ok": false, "reason": "The student hasn't attempted this word yet — listen for their attempt before grading."
                ])
                return
            }
            if wasGraded {
                logDebug("→ already graded this instance, acknowledging only")
                gemini.sendToolResponse(callId: callId, name: name, result: ["ok": true], scheduling: "SILENT")
                return
            }
            if let gradeStr = args["grade"] as? String, let grade = srsGrade(from: gradeStr) {
                SRSService(store: store).grade(entryId: card.entry.id, grade: grade)
                wasGraded = true
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
        attemptCount = 0
        wasGraded = false
        lastDetectedIntent = .none
        spokenWordMatched = false
        recentTranscriptBuffer = ""
    }

    /// Watches her live speech transcript for the current word — the moment it appears is a
    /// reliable "she's saying it right now" signal, since output transcription streams in
    /// lockstep with the audio itself. Triggers a brief highlight pulse on the French text.
    private func handleTranscriptDelta(_ delta: String) {
        guard !spokenWordMatched, let card = currentCard else { return }
        recentTranscriptBuffer += delta
        if recentTranscriptBuffer.count > 200 {
            recentTranscriptBuffer = String(recentTranscriptBuffer.suffix(200))
        }
        let target = fold(card.entry.fr)
        guard !target.isEmpty, fold(recentTranscriptBuffer).contains(target) else { return }
        spokenWordMatched = true
        withAnimation(.easeInOut(duration: 0.25)) { wordPulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeInOut(duration: 0.25)) { wordPulse = false }
        }
    }

    private func fold(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr-FR")).lowercased()
    }

    /// Invisible background "judge": takes what she was just asked to repeat and what speech
    /// recognition heard, and quietly logs a mistake tag if it looks like a genuine recurring
    /// error pattern — never blocks the live conversation, never shown to the student, and any
    /// failure (rate limit, network) is silently swallowed since this is a pure enrichment.
    private func judgeAttempt(said text: String) {
        guard let card = currentCard else { return }
        let word = card.entry.fr
        Task {
            guard let judgment = try? await LessonAgentService.shared.judgePronunciationAttempt(targetWord: word, studentSaid: text),
                  !judgment.isCorrect, let tag = judgment.tag, let description = judgment.description else { return }
            store.logMistake(tag: tag, description: description, example: text)
        }
    }

    private func srsGrade(from string: String) -> SRSGrade? {
        switch string {
        case "again": return .again
        case "good": return .good
        case "easy": return .easy
        default: return nil
        }
    }

    private func wrapUp() {
        guard !isWrappingUp else { return }
        isWrappingUp = true
        gemini.injectContext("The student has now reviewed every word on today's list. Say a short warm closing line (one sentence) congratulating them, then stop talking.")
    }

    private func finishAndReturn() {
        guard !finished else { return }
        finished = true
        timer?.invalidate()
        speakingWatchdog?.invalidate()
        audio.stopStreaming()
        gemini.disconnect()
        callStatus = .ended
        if reviewedCount > 0 {
            store.saveDiaryEntry(stage: "vocab", summary: "Practiced \(reviewedCount) word(s) in a live vocab session.")
        }
        onComplete(VocabStageResult(wordsCovered: Array(vocabQueue.prefix(reviewedCount)), reviewedCount: reviewedCount))
        dismiss()
    }

    /// Straight through in the given order, one card per word — no interleaved mid-session
    /// repeats. That extra "quick check" pass on earlier words was meant as spaced-repetition
    /// polish, but it broke the lesson's pacing and confused the flow, so it's gone.
    private static func buildSessionPlan(from queue: [VocabEntry]) -> [VocabSessionCard] {
        queue.map { VocabSessionCard(entry: $0) }
    }

    private static func buildContext(plan: [VocabSessionCard], examples: [String: LessonAgentService.VocabExample], isNewById: [String: Bool], focusNote: String? = nil) -> String {
        guard !plan.isEmpty else {
            return "VOCAB STAGE: no new or due vocabulary today. Briefly tell the student there's nothing new to review right now and that they can end the call whenever ready."
        }
        var parts: [String] = []
        parts.append("""
        VOCAB STAGE — this is a focused vocabulary session, nothing else. The student's screen \
        ALREADY shows the English, French, and pronunciation for the current word the instant it \
        appears — you never need to reveal anything.

        CRITICAL — SPEAK PRIMARILY IN ENGLISH, THIS STUDENT DOES NOT SPEAK FRENCH YET: this is a \
        total beginner, not someone who's conversational and just polishing vocab. All of your \
        own explaining, encouragement, instructions, and questions should be in English — French \
        should only ever appear as the target word itself and its example sentence, the specific \
        things they're here to learn, never as your own explanatory language. Never answer in \
        French only, including when they ask you to repeat something ("again", "encore", "one \
        more time") — every time you say the French word, pair it with the English meaning in the \
        same breath (e.g. "Sure, again — 'to eat', manger" not just "manger, manger"). If you \
        catch yourself explaining something in French, stop and say it in English instead.

        CRITICAL — YOU DO NOT CONTROL PACING, THE STUDENT DOES: you are NOT in charge of deciding \
        when to move to the next word or go back to a previous one, and you have no tool to do \
        that yourself. The app is watching the student's own words directly, and the instant they \
        say something like "next", "got it", "ready", or "go back", the app moves the card itself \
        — instantly, on its own, with zero involvement from you. You'll simply be told the new \
        current word afterward and should react to it naturally, as if you'd just turned the page \
        together. Never say things like "let's move on" as an announcement of an action you're \
        about to take — you aren't taking one. Instead, teach the current word for as long as it \
        takes, and when it feels like a natural moment, ask a genuine question like "does that feel \
        good? Ready for the next one?" — this is real conversation, not a mechanism, since it's the \
        student's own answer (heard by the app, not you) that actually moves things forward.

        You have exactly one tool: mark_result, for recording how well the student did with the \
        current word (grade: again/good/easy). It's a proposal — the app only accepts it once it's \
        confirmed the student actually attempted the word. A rejection is not an error; never \
        mention it to the student, just keep teaching naturally and try again once appropriate.

        CRITICAL — FOLLOW THIS EXACT ORDER FOR EVERY SINGLE WORD, DO NOT SKIP OR REORDER STEPS: \
        being jumpy/inconsistent about this is the single biggest complaint students have, so \
        stick to it like a script every time:
          1. Say the French word clearly, paired with its English meaning in the same breath.
          2. Ask the student to repeat it, and give them a real beat of silence to actually try.
          3. React briefly to their attempt (encouragement, or a light correction).
          4. THEN walk through the example sentence already shown on their screen — say it in \
             French, then give the English translation, and briefly point out how today's word \
             is being used inside it. Never skip this step and never do it before step 1-3.
          5. ONLY NOW ask a genuine question about moving on — e.g. "Does that feel good? Ready \
             for the next word, or want to try it once more?" — and wait for their actual answer \
             next turn. Never ask this before you've done steps 1 through 4.
        This student is a true beginner, so err toward MORE practice, not less. Some words below \
        are marked NEW (never studied before) — do at least 4 to 5 full passes of steps 1-4 before \
        step 5, not one or two; this is real practice time, not a formality. Others are marked \
        FAMILIAR (already studied) — 2 passes is enough. Above all, follow the student's own lead \
        within this order: if they ask to hear a word again, repeat it (bilingually, in English \
        primarily) as many times as they want before moving to step 5; if they say they already \
        know it, don't force the full 4-5 passes, but still walk through the example sentence at \
        least once — never skip straight from step 1 to step 5.
        """)
        let lines = plan.map { card -> String in
            let tag = isNewById[card.entry.id] == true ? "NEW" : "FAMILIAR"
            var line = "\(card.entry.fr) = \(card.entry.en) [\(tag)]"
            if let example = examples[card.entry.id] {
                line += " — example already shown on screen: \"\(example.fr)\" (\(example.en))"
            }
            return line
        }
        parts.append("TODAY'S WORD LIST (\(plan.count) words):\n" + lines.joined(separator: "\n"))
        if let focusNote, !focusNote.isEmpty {
            parts.append("TODAY'S FOCUS (mention this naturally near the start of the session): \(focusNote)")
        }
        return parts.joined(separator: "\n\n")
    }
}
