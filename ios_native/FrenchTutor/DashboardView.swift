import SwiftUI

struct DashboardView: View {
    @State private var sessions: [Session] = []
    @State private var loading = true
    @State private var showSession = false
    @State private var selectedSession: Session?
    @State private var streak = 0
    @State private var currentMonth: RoadmapMonth?
    @State private var marieLessonContext: String?

    let storage = StorageService()
    private let store = LearningStore()
    private var progressService: ProgressService { ProgressService(store: store) }

    var body: some View {
        NavigationStack {
            ZStack {
                Passeport.parchmentDim.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        header
                        dailyPathwayCard
                        callMarieCard
                        speakingTopicsCard
                        recentSessions
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: Binding(
                get: { selectedSession != nil },
                set: { if !$0 { selectedSession = nil } }
            )) {
                if let session = selectedSession {
                    HistoryView(session: session)
                }
            }
        }
        .fullScreenCover(isPresented: $showSession, onDismiss: { reload(); marieLessonContext = nil }) {
            SessionView(apiKey: geminiApiKey, lessonContext: marieLessonContext)
                .overlay(FloatingNotetakerOverlay())
                .onAppear { NotetakerState.shared.currentContext = "Speaking" }
        }
        .onAppear { reload() }
    }

    /// The Daily Pathway hub itself, embedded directly as the "Today's plan" card — not a static
    /// mirror of it that opens a separate modal copy on tap. `DailyPathwayView` owns its own
    /// stage-by-stage state and, per stage, presents exactly one full-screen session (never this
    /// same list again behind it); `onProgress` just tells the Dashboard to refresh its streak/
    /// habit badges after each stage completes.
    private var dailyPathwayCard: some View {
        DailyPathwayView(onProgress: reload)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                if let month = currentMonth {
                    KickerText(text: "Month \(month.month) · CLB 7 · TEF Canada", color: Passeport.slateDim)
                } else {
                    KickerText(text: "CLB 7 · TEF Canada", color: Passeport.slateDim)
                }
                Text("Bonjour !")
                    .font(Passeport.display(24, weight: .medium))
                    .foregroundColor(Passeport.text)
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Passeport.maroon)
                Text("\(streak)")
                    .font(Passeport.mono(12, weight: .medium))
                    .foregroundColor(Passeport.text)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Passeport.card)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Passeport.hairline, lineWidth: 1))
        }
        .padding(.top, 6)
    }

    /// Secondary/unstructured option — free-form call with no pathway stages.
    private var callMarieCard: some View {
        Button(action: { showSession = true }) {
            HStack(spacing: 10) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Passeport.brass)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Just talk to Marie")
                        .font(Passeport.body(13.5, weight: .medium))
                        .foregroundColor(Passeport.parchment)
                    Text("Unstructured practice, any topic")
                        .font(Passeport.mono(10))
                        .foregroundColor(Passeport.slate)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(Passeport.slate)
            }
            .padding(14)
            .background(Passeport.ink)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private var speakingTopicsCard: some View {
        if let topics = ContentService.shared.resources()?.speakingTopics, !topics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Discuss a topic with Marie")
                    .font(Passeport.display(15, weight: .medium))
                    .foregroundColor(Passeport.text)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(topics) { topic in
                            Button {
                                marieLessonContext = ContentService.shared.lessonContext(speakingTopic: topic)
                                showSession = true
                            } label: {
                                Text(topic.title)
                                    .font(Passeport.mono(11, weight: .medium))
                                    .foregroundColor(Passeport.maroon)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Passeport.maroon.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .passeportCard()
        }
    }


    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent sessions")
                .font(Passeport.display(16, weight: .medium))
                .foregroundColor(Passeport.text)

            if loading {
                HStack { Spacer(); ProgressView().tint(Passeport.maroon); Spacer() }
                    .padding(.vertical, 20)
            } else if sessions.isEmpty {
                Text("No calls yet. Start your first French conversation!")
                    .font(Passeport.body(13))
                    .foregroundColor(Passeport.slateDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(sessions.prefix(5)) { session in
                        SessionCard(session: session) {
                            selectedSession = session
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .passeportCard()
    }

    private func reload() {
        streak = progressService.streak()
        currentMonth = progressService.currentMonth()
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = storage.getAllSessions()
            DispatchQueue.main.async {
                sessions = loaded
                loading = false
            }
        }
    }
}

struct SessionCard: View {
    let session: Session
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Passeport.parchmentDim)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "character.bubble.fill")
                            .foregroundColor(Passeport.maroon)
                            .font(.system(size: 15))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.topic ?? "French practice")
                        .font(Passeport.body(13.5, weight: .medium))
                        .foregroundColor(Passeport.text)
                    Text(formatDate(session.startedAt))
                        .font(Passeport.mono(11))
                        .foregroundColor(Passeport.slateDim)
                }
                Spacer()
                if let stageLabel {
                    Text(stageLabel)
                        .font(Passeport.mono(9, weight: .medium))
                        .foregroundColor(Passeport.maroon)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Passeport.maroon.opacity(0.1))
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(Passeport.slate)
                    .font(.system(size: 12))
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // Every Daily Pathway stage session gets tagged (`stage` on `Session`) so Recent Sessions
    // shows what kind of session it was, not just an undifferentiated call history.
    private var stageLabel: String? {
        switch session.stage {
        case "vocab": return "Vocab"
        case "grammar": return "Grammar"
        case "reading_listening": return "Reading"
        case "writing": return "Writing"
        case "speaking": return "Speaking"
        default: return nil
        }
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let display = DateFormatter()
        display.dateFormat = "MMM d, y"
        return display.string(from: date)
    }
}
