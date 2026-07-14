import SwiftUI

/// The Daily Pathway hub — lives directly inside the Dashboard's "Today's plan" card now, not
/// behind a tap into a separate modal copy of itself. Today's material is assembled once here,
/// then handed through five focused stages in sequence — each its own small, reliable agent-led
/// (or plain typed) screen rather than one giant session trying to juggle everything. Each stage
/// is fed a summary of what came before, so the whole thing behaves as one continuous feedback
/// loop even though it's technically five separate steps: Vocabulary → Grammar → Reading &
/// Listening → Writing → Speaking (the existing, untouched "Discuss with Marie" call, now last so
/// it can pull together everything the student did in the other four stages into one closing
/// roleplay). Tapping a row opens ONLY that stage's real session, full-screen, one modal layer —
/// never this same stage list again behind it.
struct DailyPathwayView: View {
    private enum Stage: Int, CaseIterable, Identifiable {
        case vocab, grammar, postVocabChoice, listening, writing, speaking
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .vocab: return "Vocabulary"
            case .grammar: return "Grammar"
            case .postVocabChoice, .listening: return "Reading & Listening"
            case .writing: return "Writing"
            case .speaking: return "Speaking"
            }
        }
        var detail: String {
            switch self {
            case .vocab: return "Flashcards with spaced repetition"
            case .grammar: return "Pick a tense, or let Marie choose"
            case .postVocabChoice, .listening: return "Word-by-word passage walkthrough"
            case .writing: return "Short emails, paragraphs, essays"
            case .speaking: return "Closing roleplay with Marie"
            }
        }
        var habitId: String {
            switch self {
            case .vocab: return "anki"
            case .grammar: return "reading"
            case .postVocabChoice, .listening: return "listening"
            case .writing: return "writing"
            case .speaking: return "speaking"
            }
        }
        // The choice screen is an internal hop on the way to Listening, not its own row in the
        // stage list — it's shown automatically right after Reading & Listening is started.
        static var visibleCases: [Stage] { [.vocab, .grammar, .listening, .writing, .speaking] }
    }

    private let vocabQueue: [VocabEntry]
    private let listeningExercise: ListeningExercise?
    private let store = LearningStore()

    @State private var completed: Set<Stage> = []
    @State private var vocabResult: VocabStageResult?
    @State private var grammarResult: GrammarStageResult?
    @State private var listeningResult: ListeningStageResult?
    @State private var writingResult: WritingStageResult?
    // Set once, right after the post-vocab choice screen, then handed to AgentLedListeningView
    // unchanged — the passage is fixed content from that point on, never regenerated.
    @State private var chosenReadingPassage: ReadingPassage?

    @State private var activeStage: Stage?
    var onProgress: () -> Void = {}

    init(onProgress: @escaping () -> Void = {}) {
        self.onProgress = onProgress
        let store = LearningStore()
        self.vocabQueue = SRSService(store: store).dailyMixedQueue()

        let listeningPack = ContentService.shared.listening()
        let sortedExercises = listeningPack?.exercises.sorted(by: { $0.phase < $1.phase }) ?? []
        self.listeningExercise = sortedExercises.first { store.lessonStatus("listening_\($0.id)").status != "completed" } ?? sortedExercises.first
    }

    private var nextStage: Stage? {
        Stage.visibleCases.first { !completed.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Today's plan")
                    .font(Passeport.display(16, weight: .medium))
                    .foregroundColor(Passeport.text)
                Spacer()
                Text("auto-tracked")
                    .font(Passeport.mono(9, weight: .medium))
                    .foregroundColor(Passeport.slateDim)
            }
            .padding(.bottom, 6)

            ForEach(Array(Stage.visibleCases.enumerated()), id: \.element) { index, stage in
                stageRow(stage)
                if index < Stage.visibleCases.count - 1 {
                    Divider().overlay(Passeport.hairline)
                }
            }

            if completed.count == Stage.visibleCases.count {
                doneCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .passeportCard()
        .fullScreenCover(item: Binding(get: { activeStage }, set: { activeStage = $0 })) { stage in
            destination(for: stage)
                .overlay(FloatingNotetakerOverlay())
                .onAppear { NotetakerState.shared.currentContext = stage.title }
        }
    }

    private func stageRow(_ stage: Stage) -> some View {
        let isDone = completed.contains(stage)
        let isNext = stage == nextStage
        return Button {
            activeStage = stage
        } label: {
            HStack(spacing: 11) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundColor(isDone ? Passeport.brass : Passeport.slate)
                VStack(alignment: .leading, spacing: 1) {
                    Text(stage.title)
                        .font(Passeport.body(13, weight: .medium))
                        .foregroundColor(Passeport.text)
                        .strikethrough(isDone, color: Passeport.slateDim)
                    Text(stage.detail)
                        .font(Passeport.body(11))
                        .foregroundColor(Passeport.slateDim)
                        .lineLimit(1)
                }
                Spacer()
                if isNext {
                    Text("Start").font(Passeport.mono(10.5, weight: .medium)).foregroundColor(Passeport.parchment)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Passeport.maroon).clipShape(Capsule())
                } else if !isDone {
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(Passeport.slate)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var doneCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "party.popper.fill").font(.system(size: 16)).foregroundColor(Passeport.brass)
            Text("Today's pathway complete!").font(Passeport.body(13, weight: .medium)).foregroundColor(Passeport.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    @ViewBuilder
    private func destination(for stage: Stage) -> some View {
        switch stage {
        case .vocab:
            VocabPickerView { result in
                vocabResult = result
                completed.insert(.vocab)
                if result.reviewedCount > 0 {
                    store.markHabit(date: Date(), habitId: "anki", done: true, addMinutes: 5)
                }
                onProgress()
            }
        case .grammar:
            GrammarPickerView(vocabSummary: vocabResult) { result in
                grammarResult = result
                completed.insert(.grammar)
                store.markHabit(date: Date(), habitId: "reading", done: true, addMinutes: 8)
                onProgress()
                // Route through the choice screen next, not straight to Listening — the student
                // decides there whether the passage reuses today's practiced words or the
                // existing pre-authored lab content.
                activeStage = .postVocabChoice
            }
        case .postVocabChoice:
            PostVocabChoiceView(vocabResult: vocabResult, fallbackExercise: listeningExercise) { passage in
                chosenReadingPassage = passage
                activeStage = .listening
            }
        case .listening:
            if let passage = chosenReadingPassage {
                AgentLedListeningView(passage: passage, vocabSummary: vocabResult) { result in
                    listeningResult = result
                    completed.insert(.listening)
                    if result.listeningAttempted > 0 {
                        store.markHabit(date: Date(), habitId: "listening", done: true, addMinutes: 8)
                    }
                    onProgress()
                }
            } else {
                // Nothing to read today (no vocab covered and no lab exercise available) —
                // skip straight through rather than show an empty session.
                Color.clear.onAppear {
                    listeningResult = ListeningStageResult(grammarDrillResults: [], listeningCorrect: 0, listeningAttempted: 0)
                    completed.insert(.listening)
                    activeStage = nil
                    onProgress()
                }
            }
        case .writing:
            PathwayWritingView(targetWords: writingTargets()) { result in
                writingResult = result
                completed.insert(.writing)
                store.markHabit(date: Date(), habitId: "writing", done: true, addMinutes: 5)
                onProgress()
            }
        case .speaking:
            SessionView(apiKey: geminiApiKey, lessonContext: speakingContext(), stage: "speaking")
        }
    }

    private func writingTargets() -> [VocabEntry] {
        let covered = vocabResult?.wordsCovered ?? []
        return covered.isEmpty ? Array(vocabQueue.prefix(2)) : Array(covered.shuffled().prefix(2))
    }

    /// Rich context for the closing Speaking stage, built from what actually happened across all
    /// four earlier stages — the roleplay uses real material from today, not a generic prompt.
    private func speakingContext() -> String {
        var parts: [String] = ["DAILY PATHWAY — CLOSING ROLEPLAY: have a short natural conversation using today's material in a real-world scenario relevant to TEF/TCF Canada prep."]
        if let vocabResult, !vocabResult.wordsCovered.isEmpty {
            parts.append("Vocabulary covered today: " + vocabResult.wordsCovered.map { $0.fr }.joined(separator: ", "))
        }
        if let grammarResult {
            parts.append("Grammar focus today: \(grammarResult.topicTitle).")
        }
        if let listeningResult, listeningResult.listeningAttempted > 0 {
            parts.append("Reading & listening: went through \(listeningResult.listeningAttempted) part(s) of today's passage.")
        }
        if let writingResult, let score = writingResult.score {
            parts.append("Writing score today: \(String(format: "%.1f", score))/10.")
        }
        return parts.joined(separator: "\n\n")
    }
}
