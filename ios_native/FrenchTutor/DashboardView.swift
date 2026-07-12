import SwiftUI

struct DashboardView: View {
    @State private var sessions: [Session] = []
    @State private var loading = true
    @State private var showSession = false
    @State private var selectedSession: Session?
    @State private var habits: [(habit: DailyHabit, done: Bool, minutes: Int)] = []
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
                        callMarieCard
                        speakingTopicsCard
                        todaysPlan
                        monthCard
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
        }
        .onAppear { reload() }
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

    private var callMarieCard: some View {
        Button(action: { showSession = true }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Passeport.brass)
                    KickerText(text: "Speaking · live tutor")
                    Spacer()
                }
                Text("Call Marie")
                    .font(Passeport.display(21, weight: .semibold))
                    .foregroundColor(Passeport.parchment)
                Text("Real-time French conversation. Speak, get corrected, improve.")
                    .font(Passeport.body(12.5))
                    .foregroundColor(Passeport.slate)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Passeport.ink)
            .clipShape(RoundedRectangle(cornerRadius: 14))
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

    private var todaysPlan: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today's plan")
                .font(Passeport.display(16, weight: .medium))
                .foregroundColor(Passeport.text)
                .padding(.bottom, 6)

            ForEach(Array(habits.enumerated()), id: \.element.habit.id) { index, item in
                Button(action: { toggleHabit(item.habit, done: !item.done) }) {
                    HStack(spacing: 11) {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 19))
                            .foregroundColor(item.done ? Passeport.brass : Passeport.slate)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.habit.title)
                                .font(Passeport.body(13, weight: .medium))
                                .foregroundColor(Passeport.text)
                                .strikethrough(item.done, color: Passeport.slateDim)
                            Text(item.habit.detail)
                                .font(Passeport.body(11))
                                .foregroundColor(Passeport.slateDim)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("\(item.habit.minutes)m")
                            .font(Passeport.mono(10.5))
                            .foregroundColor(Passeport.slateDim)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
                if index < habits.count - 1 {
                    Divider().overlay(Passeport.hairline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .passeportCard()
    }

    @ViewBuilder
    private var monthCard: some View {
        if let month = currentMonth {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundColor(Passeport.brass)
                    KickerText(text: "Month \(month.month) focus")
                    Spacer()
                }
                Text(month.title)
                    .font(Passeport.display(14.5, weight: .medium))
                    .foregroundColor(Passeport.parchment)
                ForEach(month.goals, id: \.self) { goal in
                    HStack(alignment: .top, spacing: 7) {
                        Text("·")
                            .font(Passeport.body(12))
                            .foregroundColor(Passeport.brass)
                        Text(goal)
                            .font(Passeport.body(11.5))
                            .foregroundColor(Passeport.slate)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Passeport.ink)
            .clipShape(RoundedRectangle(cornerRadius: 14))
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

    private func toggleHabit(_ habit: DailyHabit, done: Bool) {
        store.markHabit(date: Date(), habitId: habit.id, done: done)
        habits = progressService.todaysHabits()
        streak = progressService.streak()
    }

    private func reload() {
        habits = progressService.todaysHabits()
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
                Image(systemName: "chevron.right")
                    .foregroundColor(Passeport.slate)
                    .font(.system(size: 12))
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let display = DateFormatter()
        display.dateFormat = "MMM d, y"
        return display.string(from: date)
    }
}
