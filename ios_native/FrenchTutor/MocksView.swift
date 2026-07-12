import SwiftUI

struct MocksView: View {
    private let sections: [(name: String, icon: String, time: String, labId: String)] = [
        ("Listening", "headphones", "40 min", "listening"),
        ("Reading", "book.fill", "60 min", "connectors"),
        ("Writing", "pencil.line", "60 min", "writing"),
        ("Speaking", "mic.fill", "15 min", "marie"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Passeport.parchmentDim.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 8) {
                            KickerText(text: "Full simulation")
                            Text("TEF Canada mock exam")
                                .font(Passeport.display(18, weight: .medium))
                                .foregroundColor(Passeport.text)
                            Text("All four skills, timed like the real exam. Coming soon — build your foundations in the Labs first.")
                                .font(Passeport.body(12))
                                .foregroundColor(Passeport.slateDim)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .passeportCard()

                        ForEach(sections, id: \.name) { section in
                            NavigationLink(destination: destination(for: section.labId)) {
                                HStack(spacing: 11) {
                                    Image(systemName: section.icon)
                                        .foregroundColor(Passeport.maroon)
                                        .font(.system(size: 14))
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(section.name)
                                            .font(Passeport.body(13))
                                            .foregroundColor(Passeport.text)
                                        Text("Practice in the lab first")
                                            .font(Passeport.mono(9.5))
                                            .foregroundColor(Passeport.slateDim)
                                    }
                                    Spacer()
                                    Text(section.time)
                                        .font(Passeport.mono(11))
                                        .foregroundColor(Passeport.slateDim)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11))
                                        .foregroundColor(Passeport.slate)
                                }
                                .passeportCard(padding: 13)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Mocks")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func destination(for labId: String) -> some View {
        switch labId {
        case "listening": ListeningLabView()
        case "writing": WritingLabView()
        case "connectors": ConnectorsLabView()
        default: ComingSoonView(title: "Speaking mock")
        }
    }
}
