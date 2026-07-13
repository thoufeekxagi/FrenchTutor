import SwiftUI

/// The daily anchor session: mixed spaced-repetition review + new words (~20-25/day) across
/// ALL phases, followed by a short recall quiz on already-known words, then an optional
/// "Discuss what I practiced" call with Marie built from today's actual queue. This is what
/// the "anki" habit on the Dashboard opens — a single mixed session instead of picking one
/// theme, matching the goal of daily cross-curriculum review.
struct DailyPracticeView: View {
    private let store = LearningStore()
    private let speech = LessonSpeechService.shared
    @Environment(\.dismiss) private var dismiss

    private enum Stage { case review, quiz, summary }

    @State private var stage: Stage = .review
    @State private var queue: [VocabEntry] = []
    @State private var index = 0
    @State private var isRevealed = false
    @State private var reviewedEntries: [VocabEntry] = []
    @State private var quizPool: [QuizItem] = []
    @State private var quizIndex = 0
    @State private var quizCorrect = 0
    @State private var quizSelected: String?
    @State private var sessionStart = Date()
    @State private var showMarie = false

    private struct QuizItem {
        let entry: VocabEntry
        let choices: [String]
    }

    var body: some View {
        ZStack {
            Passeport.parchmentDim.ignoresSafeArea()
            switch stage {
            case .review: reviewBody
            case .quiz: quizBody
            case .summary: summaryBody
            }
        }
        .navigationTitle("Daily Practice")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            sessionStart = Date()
            queue = SRSService(store: store).dailyMixedQueue()
            if queue.isEmpty { buildQuiz() }
        }
        .onDisappear { speech.deactivate(); logMinutes() }
        .fullScreenCover(isPresented: $showMarie) {
            SessionView(apiKey: geminiApiKey, lessonContext: recapContext())
        }
    }

    // MARK: - Review stage (same flashcard interaction as FlashcardSessionView)

    private var currentEntry: VocabEntry? { index < queue.count ? queue[index] : nil }

    @ViewBuilder
    private var reviewBody: some View {
        if index < queue.count {
            cardView
        } else {
            Color.clear.onAppear { buildQuiz() }
        }
    }

    private var cardView: some View {
        VStack(spacing: 20) {
            HStack {
                KickerText(text: "Today's review", color: Passeport.slateDim)
                Spacer()
                Text("\(index + 1) / \(queue.count)")
                    .font(Passeport.mono(11))
                    .foregroundColor(Passeport.slateDim)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 16) {
                if let entry = currentEntry {
                    Text(entry.en)
                        .font(Passeport.display(24, weight: .medium))
                        .foregroundColor(Passeport.text)
                        .multilineTextAlignment(.center)

                    if isRevealed {
                        VStack(spacing: 6) {
                            Text(entry.fr)
                                .font(Passeport.display(22, weight: .medium))
                                .foregroundColor(Passeport.maroon)
                            Text(entry.phonetic)
                                .font(Passeport.mono(13))
                                .foregroundColor(Passeport.slateDim)
                        }
                        .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .passeportCard(padding: 28)
            .padding(.horizontal, 18)

            Spacer()

            if !isRevealed {
                Button {
                    withAnimation { isRevealed = true }
                    if let entry = currentEntry {
                        speech.speak(items: [.init(text: entry.fr, language: "fr-FR")])
                    }
                } label: {
                    Text("Reveal")
                }
                .buttonStyle(PasseportPrimaryButton())
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            } else {
                HStack(spacing: 10) {
                    gradeButton(title: "Again", color: Passeport.slate, grade: .again)
                    gradeButton(title: "Good", color: Passeport.brass, grade: .good)
                    gradeButton(title: "Easy", color: Passeport.maroon, grade: .easy)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
    }

    private func gradeButton(title: String, color: Color, grade: SRSGrade) -> some View {
        Button {
            grade_(grade: grade)
        } label: {
            Text(title)
                .font(Passeport.body(13.5, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func grade_(grade: SRSGrade) {
        guard let entry = currentEntry else { return }
        SRSService(store: store).grade(entryId: entry.id, grade: grade)
        reviewedEntries.append(entry)
        isRevealed = false
        index += 1
    }

    // MARK: - Quiz stage (quick recall check on already-known words)

    private func buildQuiz() {
        let pool = SRSService(store: store).knownSample(limit: 5)
        let allEntries = ContentService.shared.vocabPhases.flatMap { $0.themes.flatMap { $0.entries } }
        quizPool = pool.map { entry in
            let distractors = allEntries.filter { $0.id != entry.id }.shuffled().prefix(2).map { $0.en }
            var choices = distractors + [entry.en]
            choices.shuffle()
            return QuizItem(entry: entry, choices: choices)
        }
        quizIndex = 0
        quizCorrect = 0
        quizSelected = nil
        stage = quizPool.isEmpty ? .summary : .quiz
    }

    @ViewBuilder
    private var quizBody: some View {
        if quizIndex < quizPool.count {
            let item = quizPool[quizIndex]
            VStack(spacing: 18) {
                HStack {
                    KickerText(text: "Quick recall check", color: Passeport.slateDim)
                    Spacer()
                    Text("\(quizIndex + 1) / \(quizPool.count)")
                        .font(Passeport.mono(11))
                        .foregroundColor(Passeport.slateDim)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("What does this mean?")
                        .font(Passeport.body(12.5))
                        .foregroundColor(Passeport.slateDim)
                    Text(item.entry.fr)
                        .font(Passeport.display(20, weight: .medium))
                        .foregroundColor(Passeport.text)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .passeportCard()

                VStack(spacing: 8) {
                    ForEach(item.choices, id: \.self) { choice in
                        Button {
                            answerQuiz(choice, item: item)
                        } label: {
                            Text(choice)
                                .font(Passeport.body(13.5, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundColor(quizSelected == nil ? Passeport.text : quizColor(choice, item: item))
                                .background(Passeport.card)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Passeport.hairline, lineWidth: 1))
                        }
                        .disabled(quizSelected != nil)
                    }
                }

                if quizSelected != nil {
                    Button {
                        withAnimation { quizIndex += 1; quizSelected = nil }
                        if quizIndex >= quizPool.count { stage = .summary }
                    } label: {
                        Text(quizIndex + 1 < quizPool.count ? "Next" : "Finish")
                    }
                    .buttonStyle(PasseportPrimaryButton())
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
        }
    }

    private func quizColor(_ choice: String, item: QuizItem) -> Color {
        if choice == item.entry.en { return Passeport.brass }
        if choice == quizSelected { return Passeport.maroon }
        return Passeport.slate
    }

    private func answerQuiz(_ choice: String, item: QuizItem) {
        quizSelected = choice
        if choice == item.entry.en { quizCorrect += 1 }
    }

    // MARK: - Summary

    private var summaryBody: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundColor(Passeport.brass)
            Text("Daily practice complete")
                .font(Passeport.display(19, weight: .medium))
                .foregroundColor(Passeport.text)
            if !reviewedEntries.isEmpty {
                Text("\(reviewedEntries.count) words reviewed" + (quizPool.isEmpty ? "." : " · \(quizCorrect)/\(quizPool.count) recall correct."))
                    .font(Passeport.body(13))
                    .foregroundColor(Passeport.slateDim)
            } else {
                Text("No new or due words right now — come back tomorrow, or study a specific theme in the Vocabulary lab.")
                    .font(Passeport.body(13))
                    .foregroundColor(Passeport.slateDim)
                    .multilineTextAlignment(.center)
            }
            Button {
                dismiss()
            } label: {
                Text("Done")
            }
            .buttonStyle(PasseportPrimaryButton())
            .padding(.horizontal, 60)
            .padding(.top, 8)

            if !reviewedEntries.isEmpty {
                Button {
                    speech.deactivate()
                    showMarie = true
                } label: {
                    HStack {
                        Image(systemName: "phone.fill")
                        Text("Practice today's words with Marie")
                    }
                    .font(Passeport.mono(11, weight: .medium))
                    .foregroundColor(Passeport.maroon)
                }
            }
        }
        .padding(24)
    }

    private func recapContext() -> String {
        guard !reviewedEntries.isEmpty else { return ContentService.shared.lessonContext() }
        let lines = reviewedEntries.prefix(25).map { "\($0.fr) = \($0.en)" }
        return "TODAY'S DAILY PRACTICE — the student just reviewed these words; roleplay a short real-world scenario using several of them:\n" + lines.joined(separator: ", ")
    }

    private func logMinutes() {
        guard !reviewedEntries.isEmpty else { return }
        let minutes = max(1, Int(Date().timeIntervalSince(sessionStart) / 60))
        store.markHabit(date: Date(), habitId: "anki", done: true, addMinutes: minutes)
    }
}
