import SwiftUI

/// Exercise list grouped by phase, with completion badges.
struct ListeningLabView: View {
    private let store = LearningStore()
    @State private var refreshToken = UUID()

    var body: some View {
        ZStack {
            Passeport.parchmentDim.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let pack = ContentService.shared.listening() {
                        ForEach([1, 2, 3], id: \.self) { phase in
                            let exercises = pack.exercises.filter { $0.phase == phase }
                            if !exercises.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    KickerText(text: "Phase \(phase)", color: Passeport.slateDim)
                                    VStack(spacing: 0) {
                                        ForEach(Array(exercises.enumerated()), id: \.element.id) { i, ex in
                                            NavigationLink(destination: ListeningExerciseView(exercise: ex)) {
                                                row(ex)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            if i < exercises.count - 1 {
                                                Divider().overlay(Passeport.hairline)
                                            }
                                        }
                                    }
                                    .passeportCard(padding: 4)
                                }
                            }
                        }
                    } else {
                        Text("Listening content unavailable.")
                            .font(Passeport.body(13))
                            .foregroundColor(Passeport.slateDim)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .id(refreshToken)
        .navigationTitle("Listening")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshToken = UUID() }
    }

    private func row(_ ex: ListeningExercise) -> some View {
        let done = store.lessonStatus("listening_\(ex.id)").status == "completed"
        return HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.seal.fill" : "seal")
                .font(.system(size: 15))
                .foregroundColor(done ? Passeport.brass : Passeport.slate)
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.title)
                    .font(Passeport.body(13.5, weight: .medium))
                    .foregroundColor(Passeport.text)
                Text("\(ex.questions.count) questions · \(ex.dictation.count) dictation")
                    .font(Passeport.mono(10.5))
                    .foregroundColor(Passeport.slateDim)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(Passeport.slate)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
