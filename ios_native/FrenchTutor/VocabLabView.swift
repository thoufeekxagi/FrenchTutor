import SwiftUI

/// Phase list → theme decks, each showing due/new/known counts. Tapping a deck starts a
/// flashcard session for that theme.
struct VocabLabView: View {
    private let store = LearningStore()
    @State private var refreshToken = UUID()

    var body: some View {
        ZStack {
            Passeport.parchmentDim.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ContentService.shared.vocabPhases, id: \.phase) { phase in
                        VStack(alignment: .leading, spacing: 8) {
                            KickerText(text: "Phase \(phase.phase) — \(phase.title)", color: Passeport.slateDim)
                            VStack(spacing: 0) {
                                ForEach(Array(phase.themes.enumerated()), id: \.element.id) { index, theme in
                                    NavigationLink(destination: FlashcardSessionView(phase: phase.phase, theme: theme)) {
                                        deckRow(theme: theme, phase: phase.phase)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    if index < phase.themes.count - 1 {
                                        Divider().overlay(Passeport.hairline)
                                    }
                                }
                            }
                            .passeportCard(padding: 4)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .id(refreshToken)
        .navigationTitle("Vocabulary")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshToken = UUID() }
    }

    private func deckRow(theme: VocabTheme, phase: Int) -> some View {
        let counts = SRSService(store: store).counts(phase: phase, themeId: theme.id)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.title)
                    .font(Passeport.body(13.5, weight: .medium))
                    .foregroundColor(Passeport.text)
                Text("\(theme.entries.count) words · \(counts.known) known")
                    .font(Passeport.mono(10.5))
                    .foregroundColor(Passeport.slateDim)
            }
            Spacer()
            if counts.due > 0 {
                Badge(text: "\(counts.due) due", color: Passeport.maroon)
            }
            if counts.unseen > 0 {
                Badge(text: "\(counts.unseen) new", color: Passeport.brass)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(Passeport.slate)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(Passeport.mono(9.5, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
