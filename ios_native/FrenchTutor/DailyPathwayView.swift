import SwiftUI

/// The Daily Pathway hub: today's material is assembled once here, then handed through four
/// focused stages in sequence — each its own small, reliable agent-led (or plain typed) screen
/// rather than one giant session trying to juggle everything. Each stage is fed a summary of
/// what came before, so the whole thing behaves as one continuous feedback loop even though
/// it's technically four separate steps: Vocabulary → Reading & Listening → Speaking (the
/// existing, untouched "Discuss with Marie" call) → Writing.
struct DailyPathwayView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Stage: Int, CaseIterable, Identifiable {
        case vocab, listening, speaking, writing
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .vocab: return "Vocabulary"
            case .listening: return "Reading & Listening"
            case .speaking: return "Speaking"
            case .writing: return "Writing"
            }
        }
        var icon: String {
            switch self {
            case .vocab: return "rectangle.stack.fill"
            case .listening: return "headphones"
            case .speaking: return "phone.fill"
            case .writing: return "pencil.line"
            }
        }
    }

    private let vocabQueue: [VocabEntry]
    private let grammarLesson: GrammarLesson?
    private let grammarTopic: GrammarTopic?
    private let listeningExercise: ListeningExercise?
    private let store = LearningStore()

    @State private var completed: Set<Stage> = []
    @State private var vocabResult: VocabStageResult?
    @State private var listeningResult: ListeningStageResult?
    @State private var writingResult: WritingStageResult?

    @State private var activeStage: Stage?

    init() {
        let store = LearningStore()
        self.vocabQueue = SRSService(store: store).dailyMixedQueue()

        let grammarPack = ContentService.shared.grammar()
        let sortedLessons = grammarPack?.lessons.sorted(by: { $0.order < $1.order }) ?? []
        let incompleteLesson = sortedLessons.first { store.lessonStatus($0.id).status != "completed" }
        let incompleteTopic = grammarPack?.topics.first { store.lessonStatus($0.id).status != "completed" }
        if let incompleteLesson {
            self.grammarLesson = incompleteLesson
            self.grammarTopic = nil
        } else if let incompleteTopic {
            self.grammarLesson = nil
            self.grammarTopic = incompleteTopic
        } else {
            self.grammarLesson = sortedLessons.first
            self.grammarTopic = nil
        }

        let listeningPack = ContentService.shared.listening()
        let sortedExercises = listeningPack?.exercises.sorted(by: { $0.phase < $1.phase }) ?? []
        self.listeningExercise = sortedExercises.first { store.lessonStatus("listening_\($0.id)").status != "completed" } ?? sortedExercises.first
    }

    private var nextStage: Stage? {
        Stage.allCases.first { !completed.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Passeport.parchmentDim.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        summaryCard
                        VStack(spacing: 8) {
                            ForEach(Stage.allCases, id: \.self) { stage in
                                stageRow(stage)
                            }
                        }
                        if completed.count == Stage.allCases.count {
                            doneCard
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Daily Pathway")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .fullScreenCover(item: Binding(get: { activeStage }, set: { activeStage = $0 })) { stage in
            destination(for: stage)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            KickerText(text: "Today's session", color: Passeport.slateDim)
            Text("\(vocabQueue.count) words · \((grammarLesson?.title ?? grammarTopic?.title) ?? "review") · \(listeningExercise != nil ? "1 listening passage" : "no listening today")")
                .font(Passeport.body(13)).foregroundColor(Passeport.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .passeportCard()
    }

    private func stageRow(_ stage: Stage) -> some View {
        let isDone = completed.contains(stage)
        let isNext = stage == nextStage
        return Button {
            activeStage = stage
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isDone ? Passeport.brass : Passeport.slate)
                Image(systemName: stage.icon)
                    .font(.system(size: 14))
                    .foregroundColor(Passeport.maroon)
                    .frame(width: 20)
                Text(stage.title)
                    .font(Passeport.body(14, weight: .medium))
                    .foregroundColor(Passeport.text)
                Spacer()
                if isNext {
                    Text("Start").font(Passeport.mono(10.5, weight: .medium)).foregroundColor(Passeport.parchment)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Passeport.maroon).clipShape(Capsule())
                } else if !isDone {
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(Passeport.slate)
                }
            }
            .padding(14)
            .passeportCard(padding: 0)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var doneCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "party.popper.fill").font(.system(size: 30)).foregroundColor(Passeport.brass)
            Text("Today's pathway complete!").font(Passeport.display(17, weight: .medium)).foregroundColor(Passeport.text)
            Button { dismiss() } label: { Text("Done") }
                .buttonStyle(PasseportPrimaryButton())
                .padding(.horizontal, 60)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
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
            }
        case .listening:
            AgentLedListeningView(
                grammarLesson: grammarLesson, grammarTopic: grammarTopic,
                listeningExercise: listeningExercise, vocabSummary: vocabResult
            ) { result in
                listeningResult = result
                completed.insert(.listening)
                if grammarLesson != nil || grammarTopic != nil {
                    store.markHabit(date: Date(), habitId: "reading", done: true, addMinutes: 8)
                }
                if listeningExercise != nil {
                    store.markHabit(date: Date(), habitId: "listening", done: true, addMinutes: 8)
                }
            }
        case .speaking:
            SessionView(apiKey: geminiApiKey, lessonContext: speakingContext())
        case .writing:
            PathwayWritingView(targetWords: writingTargets()) { result in
                writingResult = result
                completed.insert(.writing)
                store.markHabit(date: Date(), habitId: "writing", done: true, addMinutes: 5)
            }
        }
    }

    private func writingTargets() -> [VocabEntry] {
        let covered = vocabResult?.wordsCovered ?? []
        return covered.isEmpty ? Array(vocabQueue.prefix(2)) : Array(covered.shuffled().prefix(2))
    }

    /// Rich context for the Speaking stage, built from what actually happened in the first two
    /// stages — the closing roleplay uses real material from today, not a generic prompt.
    private func speakingContext() -> String {
        var parts: [String] = ["DAILY PATHWAY — CLOSING ROLEPLAY: have a short natural conversation using today's material in a real-world scenario relevant to TEF/TCF Canada prep."]
        if let vocabResult, !vocabResult.wordsCovered.isEmpty {
            parts.append("Vocabulary covered today: " + vocabResult.wordsCovered.map { $0.fr }.joined(separator: ", "))
        }
        if let grammarLesson {
            parts.append("Grammar focus today: \(grammarLesson.title).")
        } else if let grammarTopic {
            parts.append("Grammar focus today: \(grammarTopic.title).")
        }
        if let listeningResult, listeningResult.listeningAttempted > 0 {
            parts.append("Listening comprehension: \(listeningResult.listeningCorrect)/\(listeningResult.listeningAttempted) correct.")
        }
        return parts.joined(separator: "\n\n")
    }
}
