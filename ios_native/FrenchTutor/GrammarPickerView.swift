import SwiftUI

/// Sits in front of the grammar stage, same role as `VocabPickerView`: Auto (the LLM picks one
/// tense/topic from today's candidates, informed by recurring mistakes — one lightweight
/// planning call, raced against a timeout, never live during teaching) or manual (student picks
/// directly from every tense/topic already authored in Content/grammar.json).
struct GrammarPickerView: View {
    var vocabSummary: VocabStageResult? = nil
    var onComplete: (GrammarStageResult) -> Void

    @Environment(\.dismiss) private var dismiss
    private let store = LearningStore()

    private enum Mode: String, CaseIterable, Identifiable {
        case auto = "Auto"
        case manual = "Choose"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .auto
    @State private var isPlanning = false
    @State private var planningLabel = "Picking today's focus…"
    @State private var focusNote: String?
    @State private var showSession = false
    @State private var chosenLesson: GrammarLesson?
    @State private var chosenTopic: GrammarTopic?
    @State private var practiceCards: [GrammarPracticeCard] = []
    @State private var practiceTenseTitle = ""

    // Live visibility into the generation call — what's being sent, how long it's taking, what
    // came back or went wrong — same reasoning as the vocab/grammar session debug panels: a
    // silent "Building today's practice…" spinner that either works or quietly swaps in stale
    // fallback content is undebuggable. This makes the actual failure visible instead.
    @State private var debugLog: [String] = []
    @State private var generationFailed: String? = nil

    private var pack: GrammarPack? { ContentService.shared.grammar() }
    private var candidates: [(id: String, title: String)] {
        let lessons = pack?.lessons.map { ($0.id, $0.title) } ?? []
        let topics = pack?.topics.map { ($0.id, $0.title) } ?? []
        return lessons + topics
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Passeport.parchmentDim.ignoresSafeArea()
                VStack(spacing: 0) {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)

                    switch mode {
                    case .auto: autoBody
                    case .manual: manualBody
                    }
                }

                if isPlanning || generationFailed != nil {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    VStack(spacing: 12) {
                        if let generationFailed {
                            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 24)).foregroundColor(Passeport.maroon)
                            Text("Couldn't build today's practice").font(Passeport.body(14, weight: .medium)).foregroundColor(Passeport.text)
                            Text(generationFailed).font(Passeport.mono(10.5)).foregroundColor(Passeport.slateDim).multilineTextAlignment(.center)
                            Button("Retry") { generateCardsAndStart() }
                                .buttonStyle(PasseportPrimaryButton())
                                .padding(.horizontal, 30)
                        } else {
                            ProgressView().tint(Passeport.maroon)
                            Text(planningLabel).font(Passeport.mono(11)).foregroundColor(Passeport.slateDim)
                        }
                        if !debugLog.isEmpty { debugPanel }
                    }
                    .padding(20)
                    .frame(maxWidth: 320)
                    .background(Passeport.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .navigationTitle("Grammar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
            }
        }
        .fullScreenCover(isPresented: $showSession) {
            AgentLedGrammarView(cards: practiceCards, tenseTitle: practiceTenseTitle, focusNote: focusNote, vocabSummary: vocabSummary) { result in
                onComplete(result)
                dismiss()
            }
            .overlay(FloatingNotetakerOverlay())
        }
    }

    // MARK: - Practice card generation (once, before the session starts — never live)

    // The request itself is now small (tense name, ≤6 vocab words, one short recent line) and
    // should come back well under 20s — this is generous headroom for a slow moment on the free
    // tier, not a sign the request is expected to take this long. No fallback on expiry: a
    // student who hits this waits, they don't silently get stale content.
    private static let generationTimeoutNanoseconds: UInt64 = 30_000_000_000

    /// Runs once after a tense/topic is chosen (either mode) — builds the actual sentence-card
    /// deck `AgentLedGrammarView` teaches from, informed by the vocab words + transcript from the
    /// Vocab stage that just happened. No silent fallback to the old static grammar.json content
    /// on failure/timeout — that was masking real generation problems instead of surfacing them.
    /// A failure now stops here with the real error visible and a Retry button; the student never
    /// gets dropped into a stale-content session that just looks like it "worked."
    private func generateCardsAndStart() {
        let title = chosenLesson?.title ?? chosenTopic?.title ?? "Grammar"
        let usage = chosenLesson?.usage ?? chosenTopic?.sections.map { "\($0.heading): \($0.body)" } ?? []
        let vocabWords = vocabSummary?.wordsCovered.map { $0.fr } ?? []
        practiceTenseTitle = title
        isPlanning = true
        generationFailed = nil
        debugLog = []
        planningLabel = "Building today's practice…"
        logDebug("→ tense: \"\(title)\", vocab words: \(vocabWords.isEmpty ? "none" : vocabWords.joined(separator: ", "))")
        Task {
            let transcript = SessionRecorder.recentVocabTranscript()
            logDebug(transcript.isEmpty ? "→ no recent vocab transcript found" : "→ vocab transcript: \(transcript.count) chars")
            logDebug("→ sending request to LLM…")
            let outcome = await withTaskGroup(of: Outcome.self) { group in
                group.addTask {
                    do {
                        let cards = try await LessonAgentService.shared.generateGrammarPracticeCards(
                            tenseTitle: title, tenseUsage: usage, vocabWords: vocabWords, recentVocabTranscript: transcript
                        )
                        return .success(cards)
                    } catch {
                        return .failure("\(error)")
                    }
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: Self.generationTimeoutNanoseconds)
                    return .timeout
                }
                let first = await group.next() ?? .timeout
                group.cancelAll()
                return first
            }
            await MainActor.run {
                isPlanning = false
                switch outcome {
                case .success(let cards):
                    logDebug("→ received \(cards.count) card(s)")
                    practiceCards = cards
                    showSession = true
                case .failure(let message):
                    let rawSnippet = String(LessonAgentService.shared.lastRawResponse.prefix(300))
                    if !rawSnippet.isEmpty { logDebug("→ RAW LLM response: \(rawSnippet)") }
                    logDebug("→ ERROR: \(message)")
                    generationFailed = message
                case .timeout:
                    logDebug("→ TIMED OUT after \(Self.generationTimeoutNanoseconds / 1_000_000_000)s — no response from the LLM")
                    generationFailed = "The request timed out after \(Self.generationTimeoutNanoseconds / 1_000_000_000)s with no response. Check your connection and the OpenRouter key in Settings, then retry."
                }
            }
        }
    }

    private enum Outcome {
        case success([GrammarPracticeCard])
        case failure(String)
        case timeout
    }

    private func logDebug(_ message: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        debugLog.append("[\(time)] \(message)")
    }

    private var debugPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(debugLog.enumerated()), id: \.offset) { i, line in
                        Text(line)
                            .font(Passeport.mono(9))
                            .foregroundColor(Passeport.slateDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                    }
                }
            }
            .frame(maxHeight: 90)
            .onChange(of: debugLog.count) { _ in
                withAnimation { proxy.scrollTo(debugLog.count - 1, anchor: .bottom) }
            }
        }
    }

    // MARK: - Auto mode

    private var autoBody: some View {
        VStack(spacing: 16) {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 30)).foregroundColor(Passeport.brass)
                Text("Let Marie pick today's focus").font(Passeport.display(19, weight: .medium)).foregroundColor(Passeport.text)
                Text("Based on what you've been mixing up recently, or the next tense in the curriculum if nothing stands out.")
                    .font(Passeport.body(13)).foregroundColor(Passeport.slateDim).multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .frame(maxWidth: .infinity).passeportCard(padding: 24)
            Spacer()
            Button("Start") { beginAutoSession() }
                .buttonStyle(PasseportPrimaryButton())
                .disabled(candidates.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private func beginAutoSession() {
        guard !candidates.isEmpty else { return }
        isPlanning = true
        planningLabel = "Picking today's focus…"
        let mistakeTags = store.topMistakeTags()
        let diary = store.recentDiaryEntries()
        Task {
            let plan = await raceForPlan(mistakeTags: mistakeTags, diary: diary)
            await MainActor.run {
                let chosenId = plan?.chosenId ?? incompleteFirst()?.id ?? candidates.first?.id
                focusNote = plan?.focusNote.isEmpty == false ? plan?.focusNote : nil
                selectById(chosenId)
                generateCardsAndStart()
            }
        }
    }

    /// Same next-incomplete-first default `DailyPathwayView` used before this picker existed —
    /// kept as the fallback when the planner call fails/times out, so Auto still makes a
    /// reasonable choice rather than always restarting from the first tense.
    private func incompleteFirst() -> (id: String, title: String)? {
        let sortedLessons = pack?.lessons.sorted(by: { $0.order < $1.order }) ?? []
        if let incomplete = sortedLessons.first(where: { store.lessonStatus($0.id).status != "completed" }) {
            return (incomplete.id, incomplete.title)
        }
        if let incompleteTopic = pack?.topics.first(where: { store.lessonStatus($0.id).status != "completed" }) {
            return (incompleteTopic.id, incompleteTopic.title)
        }
        return candidates.first
    }

    private static let raceTimeoutNanoseconds: UInt64 = 14_000_000_000

    private func raceForPlan(mistakeTags: [(tag: String, description: String, count: Int)], diary: [String]) async -> LessonAgentService.GrammarSessionPlan? {
        let list = candidates
        return await withTaskGroup(of: LessonAgentService.GrammarSessionPlan?.self) { group in
            group.addTask { try? await LessonAgentService.shared.planGrammarSession(candidates: list, mistakeTags: mistakeTags, recentDiary: diary) }
            group.addTask { try? await Task.sleep(nanoseconds: Self.raceTimeoutNanoseconds); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Manual mode

    private var manualBody: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let lessons = pack?.lessons, !lessons.isEmpty {
                    KickerText(text: "Tenses", color: Passeport.slateDim).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(lessons) { lesson in
                        pickRow(title: lesson.title, subtitle: lesson.subtitle, id: lesson.id)
                    }
                }
                if let topics = pack?.topics, !topics.isEmpty {
                    KickerText(text: "Topics", color: Passeport.slateDim).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    ForEach(topics) { topic in
                        pickRow(title: topic.title, subtitle: nil, id: topic.id)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    private func pickRow(title: String, subtitle: String?, id: String) -> some View {
        let isDone = store.lessonStatus(id).status == "completed"
        return Button {
            selectById(id)
            focusNote = nil
            generateCardsAndStart()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isDone ? Passeport.brass : Passeport.slate)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Passeport.body(14, weight: .medium)).foregroundColor(Passeport.text)
                    if let subtitle { Text(subtitle).font(Passeport.mono(10.5)).foregroundColor(Passeport.slateDim) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(Passeport.slate)
            }
            .padding(14)
            .passeportCard(padding: 0)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func selectById(_ id: String?) {
        guard let id else { return }
        if let lesson = pack?.lessons.first(where: { $0.id == id }) {
            chosenLesson = lesson
            chosenTopic = nil
        } else if let topic = pack?.topics.first(where: { $0.id == id }) {
            chosenTopic = topic
            chosenLesson = nil
        }
    }
}
