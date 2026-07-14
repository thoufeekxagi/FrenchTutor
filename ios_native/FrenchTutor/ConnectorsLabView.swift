import SwiftUI

/// Category-grouped connector rows + a 10-question quiz. Connectors are TEF-scoring
/// "articulateurs logiques" (cependant, par conséquent, etc.).
struct ConnectorsLabView: View {
    private let speech = LessonSpeechService.shared
    @State private var showQuiz = false
    @State private var showMarie = false

    private var pack: ConnectorsPack? { ContentService.shared.connectors() }

    private var categories: [String] {
        guard let pack else { return [] }
        var seen: [String] = []
        for c in pack.connectors where !seen.contains(c.category) { seen.append(c.category) }
        return seen
    }

    var body: some View {
        ZStack {
            Passeport.parchmentDim.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let pack {
                        Text(pack.tip)
                            .font(Passeport.body(12.5))
                            .foregroundColor(Passeport.slateDim)
                            .padding(.horizontal, 2)

                        Button {
                            showQuiz = true
                        } label: {
                            Text("Take the 10-question quiz")
                        }
                        .buttonStyle(PasseportPrimaryButton())

                        ForEach(categories, id: \.self) { category in
                            VStack(alignment: .leading, spacing: 8) {
                                KickerText(text: category, color: Passeport.slateDim)
                                VStack(spacing: 0) {
                                    let items = pack.connectors.filter { $0.category == category }
                                    ForEach(Array(items.enumerated()), id: \.element.id) { i, connector in
                                        connectorRow(connector)
                                        if i < items.count - 1 {
                                            Divider().overlay(Passeport.hairline)
                                        }
                                    }
                                }
                                .passeportCard(padding: 10)
                            }
                        }
                    } else {
                        Text("Connectors content unavailable.")
                            .font(Passeport.body(13))
                            .foregroundColor(Passeport.slateDim)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Connectors")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { MarieToolbarButton(showMarie: $showMarie) { speech.deactivate() } }
        .onDisappear { speech.deactivate() }
        .sheet(isPresented: $showQuiz) {
            if let pack {
                ConnectorsQuizView(connectors: pack.connectors)
            }
        }
        .fullScreenCover(isPresented: $showMarie) {
            SessionView(apiKey: geminiApiKey, lessonContext: ContentService.shared.lessonContext())
                .overlay(FloatingNotetakerOverlay())
        }
    }

    private func connectorRow(_ connector: Connector) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(connector.fr)
                        .font(Passeport.body(13.5, weight: .medium))
                        .foregroundColor(Passeport.text)
                    Text(connector.en)
                        .font(Passeport.mono(10.5))
                        .foregroundColor(Passeport.slateDim)
                }
                Text(connector.example.fr)
                    .font(Passeport.body(11.5))
                    .foregroundColor(Passeport.slateDim)
                    .italic()
            }
            Spacer()
            Button {
                speech.speak(items: [.init(text: connector.example.fr, language: "fr-FR")])
            } label: {
                Image(systemName: "speaker.wave.2").font(.system(size: 12)).foregroundColor(Passeport.brass)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }
}

/// 10-question multiple-choice quiz built on the fly from the connectors pack: match the
/// English meaning (or example sentence) to the correct French connector.
struct ConnectorsQuizView: View {
    let connectors: [Connector]
    @Environment(\.dismiss) private var dismiss

    @State private var questions: [QuizQ] = []
    @State private var index = 0
    @State private var correctCount = 0
    @State private var selected: String?
    @State private var showMarie = false

    private struct QuizQ {
        let connector: Connector
        let choices: [String]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Passeport.parchmentDim.ignoresSafeArea()
                if index < questions.count {
                    quizCard
                } else {
                    resultCard
                }
            }
            .navigationTitle("Connectors quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear { buildQuestions() }
        .onChange(of: index) { newValue in
            guard newValue == questions.count, !questions.isEmpty else { return }
            let score = Double(correctCount) / Double(questions.count)
            LearningStore().setLessonStatus("connectors_quiz", status: score >= 0.7 ? "completed" : "in_progress", score: score)
        }
    }

    private var quizCard: some View {
        let q = questions[index]
        return VStack(spacing: 18) {
            Text("\(index + 1) / \(questions.count)")
                .font(Passeport.mono(11))
                .foregroundColor(Passeport.slateDim)
            VStack(alignment: .leading, spacing: 6) {
                Text("Which connector means:")
                    .font(Passeport.body(12.5))
                    .foregroundColor(Passeport.slateDim)
                Text(q.connector.en)
                    .font(Passeport.display(18, weight: .medium))
                    .foregroundColor(Passeport.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .passeportCard()

            VStack(spacing: 8) {
                ForEach(q.choices, id: \.self) { choice in
                    Button {
                        answer(choice, q: q)
                    } label: {
                        Text(choice)
                            .font(Passeport.body(13.5, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundColor(selected == nil ? Passeport.text : color(choice, q: q))
                            .background(Passeport.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Passeport.hairline, lineWidth: 1))
                    }
                    .disabled(selected != nil)
                }
            }

            if selected != nil {
                Button {
                    withAnimation { index += 1; selected = nil }
                } label: {
                    Text(index + 1 < questions.count ? "Next" : "See results")
                }
                .buttonStyle(PasseportPrimaryButton())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
    }

    private func color(_ choice: String, q: QuizQ) -> Color {
        if choice == q.connector.fr { return Passeport.brass }
        if choice == selected { return Passeport.maroon }
        return Passeport.slate
    }

    private func answer(_ choice: String, q: QuizQ) {
        selected = choice
        if choice == q.connector.fr { correctCount += 1 }
    }

    private var resultCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundColor(Passeport.brass)
            Text("\(correctCount) / \(questions.count)")
                .font(Passeport.display(24, weight: .medium))
                .foregroundColor(Passeport.text)
            Text("Great connectors score points on TEF writing and speaking tasks.")
                .font(Passeport.body(13))
                .foregroundColor(Passeport.slateDim)
                .multilineTextAlignment(.center)
            Button {
                dismiss()
            } label: { Text("Done") }
                .buttonStyle(PasseportPrimaryButton())
                .padding(.horizontal, 60)

            Button {
                showMarie = true
            } label: {
                HStack {
                    Image(systemName: "phone.fill")
                    Text("Practice connectors with Marie")
                }
                .font(Passeport.mono(11, weight: .medium))
                .foregroundColor(Passeport.maroon)
            }
        }
        .padding(24)
        .fullScreenCover(isPresented: $showMarie) {
            SessionView(apiKey: geminiApiKey, lessonContext: ContentService.shared.lessonContext())
                .overlay(FloatingNotetakerOverlay())
        }
    }

    private func buildQuestions() {
        let pool = connectors.shuffled()
        let picked = Array(pool.prefix(10))
        questions = picked.map { connector in
            let distractors = connectors.filter { $0.id != connector.id }.shuffled().prefix(2).map { $0.fr }
            var choices = distractors + [connector.fr]
            choices.shuffle()
            return QuizQ(connector: connector, choices: choices)
        }
    }
}
