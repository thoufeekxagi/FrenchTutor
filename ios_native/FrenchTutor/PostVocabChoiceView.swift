import SwiftUI

/// Shown right after the vocab stage ends, before Reading & Listening starts. The student picks
/// what the next stage's passage is built from — the words they just practiced (one LLM call,
/// fired here and only here, then treated as fixed pre-authored content for the rest of the
/// flow), or today's existing pre-authored lab passage. Matches STRUCTURE.md's "pre-generate
/// once, never live during teaching" rule: whichever option is picked, `AgentLedListeningView`
/// itself never calls out to a model to invent content.
struct PostVocabChoiceView: View {
    let vocabResult: VocabStageResult?
    let fallbackExercise: ListeningExercise?
    var onChoice: (ReadingPassage?) -> Void

    @State private var isBuilding = false
    @State private var buildingLabel = ""

    private var hasPracticedWords: Bool { !(vocabResult?.wordsCovered.isEmpty ?? true) }

    var body: some View {
        ZStack {
            Passeport.parchmentDim.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "book.pages.fill").font(.system(size: 30)).foregroundColor(Passeport.brass)
                    Text("Reading & Listening").font(Passeport.display(20, weight: .semibold)).foregroundColor(Passeport.text)
                    Text("Want a short passage built from the words you just practiced, or from today's lesson?")
                        .font(Passeport.body(13)).foregroundColor(Passeport.slateDim).multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(spacing: 12) {
                    Button {
                        chooseFromPracticedWords()
                    } label: {
                        VStack(spacing: 4) {
                            Text("From the words I just practiced").font(Passeport.body(14, weight: .medium))
                            if hasPracticedWords {
                                Text("\(vocabResult?.wordsCovered.count ?? 0) word(s) covered today")
                                    .font(Passeport.mono(10.5)).opacity(0.85)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PasseportPrimaryButton())
                    .disabled(!hasPracticedWords || isBuilding)

                    Button {
                        chooseFromTodaysLesson()
                    } label: {
                        Text("From today's lesson")
                            .font(Passeport.body(13, weight: .medium))
                            .foregroundColor(Passeport.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Passeport.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Passeport.hairline, lineWidth: 1))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isBuilding)
                }
                .padding(.horizontal, 24)
                Spacer()
            }

            if isBuilding {
                Color.black.opacity(0.15).ignoresSafeArea()
                VStack(spacing: 10) {
                    ProgressView().tint(Passeport.maroon)
                    Text(buildingLabel).font(Passeport.mono(11)).foregroundColor(Passeport.slateDim)
                }
                .padding(20)
                .background(Passeport.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func chooseFromTodaysLesson() {
        guard let exercise = fallbackExercise else {
            onChoice(nil)
            return
        }
        onChoice(ContentService.shared.readingPassage(fromListening: exercise))
    }

    /// Fires exactly one LLM call (never repeated, never called again during teaching), raced
    /// against a timeout the same way `VocabPickerView.beginSession` races `planVocabSession` —
    /// on failure or timeout, fall back to Option B's pre-authored lab content so the student is
    /// never blocked waiting on a model.
    private func chooseFromPracticedWords() {
        guard let words = vocabResult?.wordsCovered, !words.isEmpty else {
            chooseFromTodaysLesson()
            return
        }
        isBuilding = true
        buildingLabel = "Building today's passage…"
        Task {
            let passage = await raceForPassage(words: words)
            await MainActor.run {
                isBuilding = false
                if let passage {
                    onChoice(passage)
                } else {
                    chooseFromTodaysLesson()
                }
            }
        }
    }

    private static let raceTimeoutNanoseconds: UInt64 = 14_000_000_000

    private func raceForPassage(words: [VocabEntry]) async -> ReadingPassage? {
        await withTaskGroup(of: ReadingPassage?.self) { group in
            group.addTask { try? await LessonAgentService.shared.buildReadingPassageFromVocab(words: words) }
            group.addTask { try? await Task.sleep(nanoseconds: Self.raceTimeoutNanoseconds); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
