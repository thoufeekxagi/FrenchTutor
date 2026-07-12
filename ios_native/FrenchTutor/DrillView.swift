import SwiftUI

/// Shared fill-blank drill card: choices, immediate right/wrong feedback, and an
/// "Explain" button that asks LessonAgentService why a wrong answer was wrong.
struct DrillView: View {
    let drill: Drill
    let index: Int
    let lessonContext: String
    var onAnswered: ((Bool) -> Void)? = nil

    @State private var selected: String?
    @State private var explanation: String?
    @State private var isExplaining = false

    private var isCorrect: Bool? {
        guard let selected else { return nil }
        return selected == drill.answer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(index + 1). \(drill.prompt)")
                .font(Passeport.body(13.5))
                .foregroundColor(Passeport.text)

            HStack(spacing: 8) {
                ForEach(drill.choices, id: \.self) { choice in
                    Button {
                        guard selected == nil else { return }
                        selected = choice
                        onAnswered?(choice == drill.answer)
                    } label: {
                        Text(choice)
                            .font(Passeport.body(12.5, weight: .medium))
                            .foregroundColor(choiceColor(choice))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(choiceBackground(choice))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(choiceColor(choice).opacity(0.4), lineWidth: 1)
                            )
                    }
                    .disabled(selected != nil)
                }
            }

            if let isCorrect {
                HStack(spacing: 6) {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isCorrect ? Passeport.brass : Passeport.maroon)
                    Text(isCorrect ? "Correct" : "Correct answer: \(drill.answer)")
                        .font(Passeport.mono(11))
                        .foregroundColor(Passeport.slateDim)
                    Spacer()
                    if !isCorrect {
                        Button {
                            explain()
                        } label: {
                            Text(isExplaining ? "…" : "Explain")
                                .font(Passeport.mono(10.5, weight: .medium))
                                .foregroundColor(Passeport.maroon)
                        }
                        .disabled(isExplaining)
                    }
                }
                if let explanation {
                    Text(explanation)
                        .font(Passeport.body(12))
                        .foregroundColor(Passeport.slateDim)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func choiceColor(_ choice: String) -> Color {
        guard let selected else { return Passeport.text }
        if choice == drill.answer { return Passeport.brass }
        if choice == selected { return Passeport.maroon }
        return Passeport.slate
    }

    private func choiceBackground(_ choice: String) -> Color {
        guard selected != nil else { return Passeport.parchmentDim }
        if choice == drill.answer { return Passeport.brass.opacity(0.12) }
        if choice == selected { return Passeport.maroon.opacity(0.1) }
        return Color.clear
    }

    private func explain() {
        isExplaining = true
        Task {
            do {
                let text = try await LessonAgentService.shared.quizFeedback(
                    question: drill.prompt,
                    correctAnswer: drill.answer,
                    studentAnswer: selected ?? "",
                    lessonContext: lessonContext
                )
                await MainActor.run { explanation = text; isExplaining = false }
            } catch {
                await MainActor.run { explanation = error.localizedDescription; isExplaining = false }
            }
        }
    }
}
