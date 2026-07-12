import SwiftUI

struct LabInfo: Identifiable {
    let id: String
    let name: String
    let icon: String
    let desc: String
}

struct LabsView: View {
    private var labs: [LabInfo] {
        let content = ContentService.shared
        let vocabCount = content.vocabPhases.reduce(0) { $0 + $1.totalEntries }
        let vocabDesc = vocabCount > 0
            ? "3 phases · \(vocabCount) words with spaced repetition and pronunciation."
            : "3 phases of flashcards with spaced repetition and pronunciation."
        let tenseCount = content.grammar()?.lessons.count ?? 7
        let connectorCount = content.connectors()?.connectors.count ?? 30
        let listeningCount = content.listening()?.exercises.count ?? 12
        let writingCount = content.writingTasks()?.tasks.count ?? 12
        return [
            LabInfo(id: "vocab", name: "Vocabulary lab", icon: "rectangle.stack.fill", desc: vocabDesc),
            LabInfo(id: "grammar", name: "Grammar lab", icon: "text.book.closed.fill", desc: "\(tenseCount) tenses, irregular verbs, pronouns — narrated lessons and drills."),
            LabInfo(id: "connectors", name: "Connectors lab", icon: "link", desc: "\(connectorCount) articulateurs logiques that score points in TEF writing."),
            LabInfo(id: "listening", name: "Listening lab", icon: "headphones", desc: "\(listeningCount) exercises — comprehension and dictation, slow or normal speed."),
            LabInfo(id: "writing", name: "Writing lab", icon: "pencil.line", desc: "\(writingCount) TEF-style tasks graded with rubric feedback."),
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Passeport.parchmentDim.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(labs) { lab in
                            NavigationLink(destination: destination(for: lab)) {
                                LabCard(lab: lab)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Labs")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func destination(for lab: LabInfo) -> some View {
        switch lab.id {
        case "vocab":
            VocabLabView()
        case "grammar":
            GrammarLabView()
        case "connectors":
            ConnectorsLabView()
        case "listening":
            ListeningLabView()
        case "writing":
            WritingLabView()
        default:
            ComingSoonView(title: lab.name)
        }
    }
}

struct LabCard: View {
    let lab: LabInfo

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Passeport.parchmentDim)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: lab.icon)
                        .foregroundColor(Passeport.maroon)
                        .font(.system(size: 17))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(lab.name)
                    .font(Passeport.display(14.5, weight: .medium))
                    .foregroundColor(Passeport.text)
                Text(lab.desc)
                    .font(Passeport.body(11.5))
                    .foregroundColor(Passeport.slateDim)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(Passeport.slate)
                .font(.system(size: 13))
        }
        .passeportCard(padding: 14)
    }
}

struct ComingSoonView: View {
    let title: String
    var body: some View {
        ZStack {
            Passeport.parchmentDim.ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Passeport.brass)
                Text(title)
                    .font(Passeport.display(18, weight: .medium))
                    .foregroundColor(Passeport.text)
                Text("Coming soon")
                    .font(Passeport.mono(11))
                    .foregroundColor(Passeport.slateDim)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
