import SwiftUI

/// Plays the script at Slow(0.35)/Normal(0.5) speed, hides the transcript until answered,
/// then MCQs and dictation (typed vs expected, normalized diff + optional LLM check).
struct ListeningExerciseView: View {
    let exercise: ListeningExercise

    private let store = LearningStore()
    private let speech = LessonSpeechService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showScript = false
    @State private var answers: [Int: Int] = [:]
    @State private var dictationInputs: [Int: String] = [:]
    @State private var dictationFeedback: [Int: String] = [:]
    @State private var isChecking = false
    @State private var sessionStart = Date()

    private var lessonContext: String { ContentService.shared.lessonContext(listeningExercise: exercise) }

    private var score: Double {
        guard !exercise.questions.isEmpty else { return 0 }
        let correct = exercise.questions.indices.filter { answers[$0] == exercise.questions[$0].answerIndex }.count
        return Double(correct) / Double(exercise.questions.count)
    }

    var body: some View {
        ZStack {
            Passeport.parchmentDim.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    playbackCard
                    if !exercise.questions.isEmpty { questionsCard }
                    if !exercise.dictation.isEmpty { dictationCard }
                    if allQuestionsAnswered {
                        Button {
                            finish()
                        } label: {
                            Text("Finish exercise")
                        }
                        .buttonStyle(PasseportPrimaryButton())
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(exercise.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { sessionStart = Date() }
        .onDisappear { speech.deactivate() }
    }

    private var allQuestionsAnswered: Bool {
        !exercise.questions.isEmpty && answers.count == exercise.questions.count
    }

    private var playbackCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            KickerText(text: "Listen", color: Passeport.slateDim)
            HStack(spacing: 12) {
                Button {
                    play(rate: 0.32)
                } label: {
                    label("Slow", icon: "tortoise.fill")
                }
                Button {
                    play(rate: 0.48)
                } label: {
                    label("Normal", icon: "hare.fill")
                }
            }
            if showScript {
                Text(exercise.script)
                    .font(Passeport.body(13))
                    .foregroundColor(Passeport.text)
                    .padding(.top, 4)
            } else {
                Button {
                    withAnimation { showScript = true }
                } label: {
                    Text("Show script")
                        .font(Passeport.mono(11, weight: .medium))
                        .foregroundColor(Passeport.maroon)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .passeportCard()
    }

    private func label(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12))
            Text(text).font(Passeport.body(12.5, weight: .medium))
        }
        .foregroundColor(Passeport.maroon)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Passeport.maroon.opacity(0.1))
        .clipShape(Capsule())
    }

    private func play(rate: Float) {
        speech.speak(items: [.init(text: exercise.script, language: "fr-FR")], rate: rate)
    }

    private var questionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            KickerText(text: "Comprehension", color: Passeport.slateDim)
            ForEach(Array(exercise.questions.enumerated()), id: \.element.id) { qi, question in
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.q)
                        .font(Passeport.body(13.5, weight: .medium))
                        .foregroundColor(Passeport.text)
                    ForEach(Array(question.choices.enumerated()), id: \.offset) { ci, choice in
                        Button {
                            guard answers[qi] == nil else { return }
                            answers[qi] = ci
                        } label: {
                            HStack {
                                Text(choice)
                                    .font(Passeport.body(12.5))
                                Spacer()
                                if let selected = answers[qi] {
                                    if ci == question.answerIndex {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(Passeport.brass)
                                    } else if ci == selected {
                                        Image(systemName: "xmark.circle.fill").foregroundColor(Passeport.maroon)
                                    }
                                }
                            }
                            .foregroundColor(Passeport.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Passeport.parchmentDim)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(answers[qi] != nil)
                    }
                }
                if qi < exercise.questions.count - 1 {
                    Divider().overlay(Passeport.hairline).padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .passeportCard()
    }

    private var dictationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            KickerText(text: "Dictation", color: Passeport.slateDim)
            ForEach(Array(exercise.dictation.enumerated()), id: \.offset) { i, sentence in
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        speech.speak(items: [.init(text: sentence, language: "fr-FR")])
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "speaker.wave.2.fill").font(.system(size: 12))
                            Text("Play sentence \(i + 1)").font(Passeport.mono(11, weight: .medium))
                        }
                        .foregroundColor(Passeport.brass)
                    }
                    TextField("Type what you hear…", text: dictationBinding(i))
                        .font(Passeport.body(13))
                        .padding(10)
                        .background(Passeport.parchmentDim)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Button {
                        checkDictation(index: i, expected: sentence)
                    } label: {
                        Text(isChecking ? "Checking…" : "Check")
                            .font(Passeport.mono(10.5, weight: .medium))
                            .foregroundColor(Passeport.maroon)
                    }
                    .disabled(isChecking)
                    if let feedback = dictationFeedback[i] {
                        Text(feedback)
                            .font(Passeport.body(12))
                            .foregroundColor(Passeport.slateDim)
                    }
                }
                if i < exercise.dictation.count - 1 {
                    Divider().overlay(Passeport.hairline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .passeportCard()
    }

    private func dictationBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { dictationInputs[index] ?? "" },
            set: { dictationInputs[index] = $0 }
        )
    }

    private func checkDictation(index: Int, expected: String) {
        let submitted = dictationInputs[index] ?? ""
        let normalizedExpected = normalize(expected)
        let normalizedSubmitted = normalize(submitted)
        if normalizedExpected == normalizedSubmitted {
            dictationFeedback[index] = "Perfect match! 🎉"
            return
        }
        isChecking = true
        Task {
            do {
                let text = try await LessonAgentService.shared.checkDictation(expected: expected, submitted: submitted)
                await MainActor.run { dictationFeedback[index] = text; isChecking = false }
            } catch {
                await MainActor.run {
                    dictationFeedback[index] = normalizedSubmitted.isEmpty
                        ? "Type your answer, then tap Check."
                        : "Not quite — expected: \"\(expected)\""
                    isChecking = false
                }
            }
        }
    }

    private func normalize(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr-FR"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[.!?,;]", with: "", options: .regularExpression)
    }

    private func finish() {
        let minutes = max(1, Int(Date().timeIntervalSince(sessionStart) / 60))
        store.markHabit(date: Date(), habitId: "listening", done: true, addMinutes: minutes)
        store.setLessonStatus("listening_\(exercise.id)", status: score >= 0.6 ? "completed" : "in_progress", score: score)
        dismiss()
    }
}
