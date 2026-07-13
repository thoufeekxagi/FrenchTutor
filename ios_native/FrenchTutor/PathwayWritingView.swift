import SwiftUI

struct WritingStageResult {
    let score: Double?
}

/// Daily Pathway stage 4 — plain typed micro-writing, no live call. Writing needs typed
/// accuracy (spelling, connectors), not voice, so this deliberately has none of the
/// audio-session complexity the other stages do.
struct PathwayWritingView: View {
    let targetWords: [VocabEntry]
    var onComplete: (WritingStageResult) -> Void

    @Environment(\.dismiss) private var dismiss
    private let store = LearningStore()
    private let sessionId = UUID().uuidString

    @State private var submission = ""
    @State private var isGrading = false
    @State private var feedback: LessonAgentService.MicroWritingFeedback?
    @State private var errorText: String?

    private var prompt: String {
        "Write one or two sentences using: " + targetWords.map { $0.fr }.joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Passeport.parchmentDim.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        KickerText(text: "Quick writing check", color: Passeport.slateDim)
                        Text(prompt).font(Passeport.body(13.5)).foregroundColor(Passeport.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).passeportCard()

                    if feedback == nil {
                        TextEditor(text: $submission)
                            .font(Passeport.body(13.5))
                            .foregroundColor(Passeport.text)
                            .tint(Passeport.maroon)
                            .frame(minHeight: 160)
                            .scrollContentBackground(.hidden)
                            .background(Passeport.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Button { submit() } label: { Text(isGrading ? "Grading…" : "Submit") }
                            .buttonStyle(PasseportPrimaryButton())
                            .disabled(isGrading || submission.trimmingCharacters(in: .whitespaces).isEmpty)

                        if let errorText {
                            Text(errorText).font(Passeport.mono(11)).foregroundColor(Passeport.maroon)
                        }
                    } else if let feedback {
                        VStack(spacing: 10) {
                            Text(String(format: "%.1f / 10", feedback.scoreOutOf10))
                                .font(Passeport.display(28, weight: .medium)).foregroundColor(Passeport.maroon)
                            Text(feedback.comment).font(Passeport.body(13.5)).foregroundColor(Passeport.text).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).passeportCard()

                        Button { onComplete(WritingStageResult(score: feedback.scoreOutOf10)); dismiss() } label: { Text("Finish") }
                            .buttonStyle(PasseportPrimaryButton())
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
            .navigationTitle("Writing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Skip") { onComplete(WritingStageResult(score: nil)); dismiss() }
                        .foregroundColor(Passeport.slateDim)
                }
            }
        }
    }

    private func submit() {
        isGrading = true
        errorText = nil
        let targets = targetWords.map { $0.fr }
        let text = submission
        Task {
            do {
                let result = try await LessonAgentService.shared.gradeMicroWriting(prompt: prompt, targetWords: targets, submission: text)
                await MainActor.run {
                    feedback = result
                    isGrading = false
                    store.saveSubmission(taskId: "pathway_\(sessionId)", content: text, feedback: result.comment, score: result.scoreOutOf10)
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    isGrading = false
                }
            }
        }
    }
}
