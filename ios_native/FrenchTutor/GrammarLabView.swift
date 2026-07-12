import SwiftUI

/// 7 tenses + irregular verbs + grammar topics (pronouns, passive voice), each with a
/// completion badge sourced from LearningStore.
struct GrammarLabView: View {
    private let store = LearningStore()
    @State private var refreshToken = UUID()

    var body: some View {
        ZStack {
            Passeport.parchmentDim.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let grammar = ContentService.shared.grammar() {
                        section(title: "Tenses") {
                            ForEach(grammar.lessons.sorted(by: { $0.order < $1.order })) { lesson in
                                NavigationLink(destination: GrammarLessonView(lesson: lesson)) {
                                    row(title: lesson.title, subtitle: lesson.subtitle, id: lesson.id)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }

                        section(title: "Topics") {
                            ForEach(grammar.topics) { topic in
                                NavigationLink(destination: TopicLessonView(topic: topic)) {
                                    row(title: topic.title, subtitle: "\(topic.sections.count) sections", id: topic.id)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }

                        section(title: "Irregular verbs") {
                            NavigationLink(destination: IrregularVerbsView(verbs: grammar.irregularVerbs)) {
                                row(title: "12 essential irregular verbs", subtitle: "être, avoir, aller, faire…", id: nil)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    } else {
                        Text("Grammar content unavailable.")
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
        .navigationTitle("Grammar")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshToken = UUID() }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            KickerText(text: title, color: Passeport.slateDim)
            VStack(spacing: 0) { content() }
                .passeportCard(padding: 4)
        }
    }

    private func row(title: String, subtitle: String, id: String?) -> some View {
        let done = id.map { store.lessonStatus($0).status == "completed" } ?? false
        return HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.seal.fill" : "seal")
                .font(.system(size: 15))
                .foregroundColor(done ? Passeport.brass : Passeport.slate)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Passeport.body(13.5, weight: .medium))
                    .foregroundColor(Passeport.text)
                Text(subtitle)
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

struct IrregularVerbsView: View {
    let verbs: [IrregularVerb]
    @StateObject private var speechBox = SpeechServiceBox()

    var body: some View {
        ZStack {
            Passeport.parchmentDim.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(verbs) { verb in
                        IrregularVerbTableView(verb: verb) { text in
                            speechBox.speech.speak(items: [.init(text: text, language: "fr-FR")])
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Irregular verbs")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { speechBox.speech.deactivate() }
    }
}

/// Shared ObservableObject box so SwiftUI views can own a LessonSpeechService instance.
final class SpeechServiceBox: ObservableObject {
    let speech = LessonSpeechService()
}
