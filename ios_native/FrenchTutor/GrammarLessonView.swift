import SwiftUI

/// The voice-lesson pattern: narrated cards (usage → conjugation tables → examples) with
/// play/pause, a mic button that opens LessonQAOverlay, fill-blank drills, and completion
/// tracking (≥80% on drills marks the lesson done).
struct GrammarLessonView: View {
    let lesson: GrammarLesson

    private let store = LearningStore()
    private let speech = LessonSpeechService.shared
    @State private var isPlaying = false
    @State private var highlightedCard = 0
    @State private var showQA = false
    @State private var showMarie = false
    @State private var drillResults: [Bool] = []
    @State private var engaged = false
    @State private var sessionStart = Date()

    private var lessonContext: String { ContentService.shared.lessonContext(grammarLesson: lesson) }

    /// Cards: 0 = usage, 1..n = conjugations, last = examples.
    private var cardCount: Int { 1 + lesson.conjugations.count + 1 }

    var body: some View {
        ZStack {
            Passeport.parchmentDim.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        usageCard.id(0)
                        ForEach(Array(lesson.conjugations.enumerated()), id: \.element.id) { i, conj in
                            ConjugationTableView(
                                verb: conj.verb, group: conj.group, rows: conj.rows,
                                highlightedPronoun: nil,
                                onSpeak: { text in speech.speak(items: [.init(text: text, language: "fr-FR")]) }
                            )
                            .id(i + 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(highlightedCard == i + 1 ? Passeport.brass : .clear, lineWidth: 2)
                            )
                        }
                        examplesCard.id(cardCount - 1)
                        drillsSection
                        discussWithMarieButton
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
                .onChange(of: highlightedCard) { newValue in
                    withAnimation { proxy.scrollTo(newValue, anchor: .top) }
                }
            }

            VStack {
                Spacer()
                controlBar
            }
        }
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { MarieToolbarButton(showMarie: $showMarie) { speech.deactivate() } }
        .onAppear { sessionStart = Date() }
        .onDisappear { speech.deactivate(); logMinutes() }
        .sheet(isPresented: $showQA) {
            LessonQAOverlay(lessonContext: lessonContext, speech: speech, isPresented: $showQA)
                .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showMarie) {
            SessionView(apiKey: geminiApiKey, lessonContext: lessonContext)
        }
    }

    private var discussWithMarieButton: some View {
        Button {
            speech.deactivate()
            showMarie = true
        } label: {
            HStack {
                Image(systemName: "phone.fill")
                Text("Discuss with Marie")
            }
        }
        .buttonStyle(PasseportPrimaryButton())
    }

    private func logMinutes() {
        guard engaged else { return }
        let minutes = max(1, Int(Date().timeIntervalSince(sessionStart) / 60))
        store.markHabit(date: Date(), habitId: "reading", done: true, addMinutes: minutes)
    }

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            KickerText(text: "Usage", color: Passeport.slateDim)
            ForEach(lesson.usage, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Text("•").foregroundColor(Passeport.brass)
                    Text(line)
                        .font(Passeport.body(13))
                        .foregroundColor(Passeport.text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .passeportCard()
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(highlightedCard == 0 ? Passeport.brass : .clear, lineWidth: 2)
        )
    }

    private var examplesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            KickerText(text: "Examples", color: Passeport.slateDim)
            ForEach(lesson.examples) { ex in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ex.fr).font(Passeport.body(13.5, weight: .medium)).foregroundColor(Passeport.text)
                        Text(ex.en).font(Passeport.mono(10.5)).foregroundColor(Passeport.slateDim)
                    }
                    Spacer()
                    Button {
                        speech.speak(items: [.init(text: ex.fr, language: "fr-FR")])
                    } label: {
                        Image(systemName: "speaker.wave.2").font(.system(size: 12)).foregroundColor(Passeport.brass)
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .passeportCard()
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(highlightedCard == cardCount - 1 ? Passeport.brass : .clear, lineWidth: 2)
        )
    }

    private var drillsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            KickerText(text: "Practice", color: Passeport.slateDim)
            VStack(spacing: 0) {
                ForEach(Array(lesson.drills.enumerated()), id: \.element.id) { i, drill in
                    DrillView(drill: drill, index: i, lessonContext: lessonContext) { correct in
                        recordDrillResult(correct)
                    }
                    if i < lesson.drills.count - 1 {
                        Divider().overlay(Passeport.hairline)
                    }
                }
            }
            .passeportCard(padding: 12)
        }
    }

    private var controlBar: some View {
        HStack(spacing: 16) {
            Button {
                togglePlay()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 52, height: 52)
                    .background(Passeport.maroon)
                    .clipShape(Circle())
            }
            Text(isPlaying ? "Narrating…" : "Play lesson")
                .font(Passeport.mono(11))
                .foregroundColor(Passeport.slateDim)
            Spacer()
            Button {
                speech.pause()
                isPlaying = false
                showQA = true
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Passeport.brass)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Passeport.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    private func togglePlay() {
        if isPlaying {
            speech.pause()
            isPlaying = false
            return
        }
        if speech.isSpeaking {
            speech.resume()
            isPlaying = true
            return
        }
        isPlaying = true
        engaged = true
        let items = LessonSpeechService.speechItems(from: lesson.narration)
        // Map narration item index proportionally onto the card range for scroll highlight.
        speech.speak(
            items: items,
            onItemStart: { idx in
                let card = min(cardCount - 1, (idx * cardCount) / max(1, items.count))
                highlightedCard = card
            },
            onFinished: { isPlaying = false }
        )
    }

    private func recordDrillResult(_ correct: Bool) {
        engaged = true
        drillResults.append(correct)
        guard drillResults.count == lesson.drills.count else { return }
        let score = Double(drillResults.filter { $0 }.count) / Double(drillResults.count)
        if score >= 0.8 {
            store.setLessonStatus(lesson.id, status: "completed", score: score)
        } else {
            store.setLessonStatus(lesson.id, status: "in_progress", score: score)
        }
    }
}

/// Same voice-lesson pattern for a GrammarTopic (pronouns, passive voice) — sections
/// instead of conjugation tables.
struct TopicLessonView: View {
    let topic: GrammarTopic

    private let store = LearningStore()
    private let speech = LessonSpeechService.shared
    @State private var isPlaying = false
    @State private var showQA = false
    @State private var showMarie = false
    @State private var drillResults: [Bool] = []
    @State private var engaged = false
    @State private var sessionStart = Date()

    private var lessonContext: String { ContentService.shared.lessonContext(topic: topic) }

    var body: some View {
        ZStack {
            Passeport.parchmentDim.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(topic.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            KickerText(text: section.heading, color: Passeport.slateDim)
                            Text(section.body)
                                .font(Passeport.body(13))
                                .foregroundColor(Passeport.text)
                            ForEach(section.examples) { ex in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(ex.fr).font(Passeport.body(13.5, weight: .medium)).foregroundColor(Passeport.text)
                                        Text(ex.en).font(Passeport.mono(10.5)).foregroundColor(Passeport.slateDim)
                                    }
                                    Spacer()
                                    Button {
                                        speech.speak(items: [.init(text: ex.fr, language: "fr-FR")])
                                    } label: {
                                        Image(systemName: "speaker.wave.2").font(.system(size: 12)).foregroundColor(Passeport.brass)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .passeportCard()
                    }

                    if !topic.drills.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            KickerText(text: "Practice", color: Passeport.slateDim)
                            VStack(spacing: 0) {
                                ForEach(Array(topic.drills.enumerated()), id: \.element.id) { i, drill in
                                    DrillView(drill: drill, index: i, lessonContext: lessonContext) { correct in
                                        recordDrillResult(correct)
                                    }
                                    if i < topic.drills.count - 1 {
                                        Divider().overlay(Passeport.hairline)
                                    }
                                }
                            }
                            .passeportCard(padding: 12)
                        }
                    }

                    Button {
                        speech.deactivate()
                        showMarie = true
                    } label: {
                        HStack {
                            Image(systemName: "phone.fill")
                            Text("Discuss with Marie")
                        }
                    }
                    .buttonStyle(PasseportPrimaryButton())
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }

            VStack {
                Spacer()
                HStack(spacing: 16) {
                    Button { togglePlay() } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18)).foregroundColor(.white)
                            .frame(width: 52, height: 52).background(Passeport.maroon).clipShape(Circle())
                    }
                    Text(isPlaying ? "Narrating…" : "Play lesson")
                        .font(Passeport.mono(11)).foregroundColor(Passeport.slateDim)
                    Spacer()
                    Button {
                        speech.pause(); isPlaying = false; showQA = true
                    } label: {
                        Image(systemName: "mic.fill").font(.system(size: 16)).foregroundColor(.white)
                            .frame(width: 44, height: 44).background(Passeport.brass).clipShape(Circle())
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Passeport.card).clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 18).padding(.bottom, 12)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            }
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { MarieToolbarButton(showMarie: $showMarie) { speech.deactivate() } }
        .onAppear { sessionStart = Date() }
        .onDisappear { speech.deactivate(); logMinutes() }
        .sheet(isPresented: $showQA) {
            LessonQAOverlay(lessonContext: lessonContext, speech: speech, isPresented: $showQA)
                .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showMarie) {
            SessionView(apiKey: geminiApiKey, lessonContext: lessonContext)
        }
    }

    private func togglePlay() {
        if isPlaying { speech.pause(); isPlaying = false; return }
        if speech.isSpeaking { speech.resume(); isPlaying = true; return }
        isPlaying = true
        engaged = true
        let items = LessonSpeechService.speechItems(from: topic.narration)
        speech.speak(items: items, onFinished: { isPlaying = false })
    }

    private func recordDrillResult(_ correct: Bool) {
        engaged = true
        drillResults.append(correct)
        guard drillResults.count == topic.drills.count else { return }
        let score = Double(drillResults.filter { $0 }.count) / Double(drillResults.count)
        store.setLessonStatus(topic.id, status: score >= 0.8 ? "completed" : "in_progress", score: score)
    }

    private func logMinutes() {
        guard engaged else { return }
        let minutes = max(1, Int(Date().timeIntervalSince(sessionStart) / 60))
        store.markHabit(date: Date(), habitId: "reading", done: true, addMinutes: minutes)
    }
}
