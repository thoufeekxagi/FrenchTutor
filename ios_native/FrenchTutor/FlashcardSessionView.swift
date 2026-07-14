import SwiftUI

/// One flashcard study session for a theme: French + phonetic front → swipe/tap to reveal the
/// English meaning, TTS playback (slow + normal), optional "Say it" speak-back practice,
/// Again/Good/Easy grading via SRS — graded by swiping the card left/right/up once revealed.
struct FlashcardSessionView: View {
    let phase: Int
    let theme: VocabTheme

    private let store = LearningStore()
    private let speech = LessonSpeechService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [VocabEntry] = []
    @State private var index = 0
    @State private var isRevealed = false
    @State private var reviewedCount = 0
    @State private var sessionStart = Date()
    @State private var isListeningBack = false
    @State private var sayItHint: String?
    @State private var showVocabSession = false
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Passeport.parchmentDim.ignoresSafeArea()

            if queue.isEmpty {
                summaryView
            } else if index < queue.count {
                cardView
            } else {
                summaryView
            }
        }
        .navigationTitle(theme.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { MarieToolbarButton(showMarie: $showVocabSession) { speech.deactivate() } }
        .onAppear {
            queue = SRSService(store: store).buildQueue(phase: phase, themeId: theme.id, limit: 30)
            sessionStart = Date()
            if let first = currentEntry {
                speech.speak(items: [.init(text: first.fr, language: "fr-FR")])
            }
        }
        .fullScreenCover(isPresented: $showVocabSession) {
            AgentLedVocabView(
                vocabQueue: Array(queue[index...]),
                examplesByWordId: ContentService.shared.vocabExamples(for: Array(queue[index...]))
            ) { result in
                reviewedCount += result.reviewedCount
                showVocabSession = false
            }
            .overlay(FloatingNotetakerOverlay())
        }
        .overlay(FloatingNotetakerOverlay())
        .onDisappear {
            speech.deactivate()
            logMinutes()
        }
    }

    private var currentEntry: VocabEntry? {
        index < queue.count ? queue[index] : nil
    }

    private static let swipeThreshold: CGFloat = 90

    private var cardView: some View {
        VStack(spacing: 20) {
            HStack {
                Text("\(index + 1) / \(queue.count)")
                    .font(Passeport.mono(11))
                    .foregroundColor(Passeport.slateDim)
                Spacer()
                if isRevealed {
                    Text("swipe: ← again · up easy · → good")
                        .font(Passeport.mono(9))
                        .foregroundColor(Passeport.slateDim)
                } else {
                    Text("tap or swipe up to reveal")
                        .font(Passeport.mono(9))
                        .foregroundColor(Passeport.slateDim)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 16) {
                if let entry = currentEntry {
                    VStack(spacing: 6) {
                        Text(entry.fr)
                            .font(Passeport.display(24, weight: .medium))
                            .foregroundColor(Passeport.text)
                        Text(entry.phonetic)
                            .font(Passeport.mono(13))
                            .foregroundColor(Passeport.slateDim)
                    }
                    .multilineTextAlignment(.center)

                    HStack(spacing: 16) {
                        Button {
                            speech.speak(items: [.init(text: entry.fr, language: "fr-FR")], rate: 0.3)
                        } label: {
                            Image(systemName: "tortoise.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Passeport.brass)
                                .frame(width: 44, height: 44)
                                .background(Passeport.card)
                                .clipShape(Circle())
                        }
                        Button {
                            speech.speak(items: [.init(text: entry.fr, language: "fr-FR")], rate: 0.45)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Passeport.brass)
                                .frame(width: 44, height: 44)
                                .background(Passeport.card)
                                .clipShape(Circle())
                        }
                    }

                    if isRevealed {
                        VStack(spacing: 10) {
                            Text(entry.en)
                                .font(Passeport.display(20, weight: .medium))
                                .foregroundColor(Passeport.maroon)
                            Button {
                                sayIt(entry: entry)
                            } label: {
                                Image(systemName: isListeningBack ? "mic.fill" : "mic")
                                    .font(.system(size: 18))
                                    .foregroundColor(isListeningBack ? .white : Passeport.maroon)
                                    .frame(width: 44, height: 44)
                                    .background(isListeningBack ? Passeport.maroon : Passeport.card)
                                    .clipShape(Circle())
                            }
                            if let sayItHint {
                                Text(sayItHint)
                                    .font(Passeport.mono(10.5))
                                    .foregroundColor(Passeport.slateDim)
                            }
                        }
                        .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .passeportCard(padding: 28)
            .padding(.horizontal, 18)
            .offset(dragOffset)
            .rotationEffect(.degrees(Double(dragOffset.width / 22)))
            .overlay(swipeHint)
            .gesture(cardDrag)
            .onTapGesture { revealIfNeeded() }

            Spacer()
            Spacer()
        }
    }

    @ViewBuilder
    private var swipeHint: some View {
        if isRevealed {
            if dragOffset.width < -24 {
                swipeBadge(text: "AGAIN", color: Passeport.slate)
            } else if dragOffset.width > 24 {
                swipeBadge(text: "GOOD", color: Passeport.brass)
            } else if dragOffset.height < -24 {
                swipeBadge(text: "EASY", color: Passeport.maroon)
            }
        }
    }

    private func swipeBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(Passeport.mono(13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(color)
            .clipShape(Capsule())
    }

    private func revealIfNeeded() {
        guard !isRevealed else { return }
        withAnimation { isRevealed = true }
    }

    private var cardDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                if isRevealed { dragOffset = value.translation }
            }
            .onEnded { value in
                if !isRevealed {
                    revealIfNeeded()
                    return
                }
                let t = value.translation
                withAnimation {
                    if t.height < -Self.swipeThreshold && abs(t.height) > abs(t.width) {
                        dragOffset = CGSize(width: 0, height: -600)
                        grade_(entry: currentEntry, grade: .easy)
                    } else if t.width > Self.swipeThreshold {
                        dragOffset = CGSize(width: 600, height: t.height)
                        grade_(entry: currentEntry, grade: .good)
                    } else if t.width < -Self.swipeThreshold {
                        dragOffset = CGSize(width: -600, height: t.height)
                        grade_(entry: currentEntry, grade: .again)
                    } else {
                        dragOffset = .zero
                    }
                }
            }
    }

    private func grade_(entry: VocabEntry?, grade: SRSGrade) {
        guard let entry else { return }
        SRSService(store: store).grade(entryId: entry.id, grade: grade)
        reviewedCount += 1
        sayItHint = nil
        isRevealed = false
        index += 1
        dragOffset = .zero
        if let next = currentEntry {
            speech.speak(items: [.init(text: next.fr, language: "fr-FR")])
        }
    }

    private func sayIt(entry: VocabEntry) {
        guard !isListeningBack else {
            speech.stopListening()
            isListeningBack = false
            return
        }
        isListeningBack = true
        sayItHint = nil
        speech.startListening(locale: "fr-FR", onPartial: { _ in }) { transcript in
            isListeningBack = false
            let said = fold(transcript)
            let target = fold(entry.fr)
            if said.isEmpty {
                sayItHint = "Didn't catch that — try again."
            } else if said.contains(target) || target.contains(said) {
                sayItHint = "Nice — that sounds right! 🎉"
            } else {
                sayItHint = "Close — target: \"\(entry.fr)\". This is just a hint, not graded."
            }
        }
    }

    private func fold(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr-FR"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func logMinutes() {
        guard reviewedCount > 0 else { return }
        let minutes = max(1, Int(Date().timeIntervalSince(sessionStart) / 60))
        store.markHabit(date: Date(), habitId: "anki", done: true, addMinutes: minutes)
    }

    private var summaryView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundColor(Passeport.brass)
            Text(reviewedCount > 0 ? "Session complete" : "All caught up")
                .font(Passeport.display(19, weight: .medium))
                .foregroundColor(Passeport.text)
            Text(reviewedCount > 0 ? "\(reviewedCount) cards reviewed." : "No cards due in \"\(theme.title)\" right now.")
                .font(Passeport.body(13))
                .foregroundColor(Passeport.slateDim)
            Button {
                dismiss()
            } label: {
                Text("Done")
            }
            .buttonStyle(PasseportPrimaryButton())
            .padding(.horizontal, 60)
            .padding(.top, 8)

            if reviewedCount == 0 {
                Button {
                    queue = SRSService(store: store).allEntries(phase: phase, themeId: theme.id)
                    index = 0
                } label: {
                    Text("Review all \(theme.entries.count) words anyway")
                        .font(Passeport.mono(11, weight: .medium))
                        .foregroundColor(Passeport.maroon)
                }
            }

            if reviewedCount > 0 {
                Button {
                    speech.deactivate()
                    showVocabSession = true
                } label: {
                    HStack {
                        Image(systemName: "phone.fill")
                        Text("Practice this theme with Marie")
                    }
                    .font(Passeport.mono(11, weight: .medium))
                    .foregroundColor(Passeport.maroon)
                }
            }
        }
        .padding(24)
    }
}
