import SwiftUI

struct HomeView: View {
    @State private var sessions: [Session] = []
    @State private var loading = true
    @State private var showSession = false
    @State private var selectedSession: Session?
    @State private var refreshTrigger = false

    let storage = StorageService()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("French Tutor")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Speak. Learn. Improve.")
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    Button(action: { showSession = true }) {
                        VStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.white)
                            Text("Call Your Tutor")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            Text("Tap to start a French voice call")
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.42, green: 0.36, blue: 0.91), Color(red: 0.55, green: 0.49, blue: 0.96)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Color(red: 0.42, green: 0.36, blue: 0.91).opacity(0.3), radius: 20, x: 0, y: 8)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 40)

                    HStack {
                        Text("Recent Sessions")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    .padding(.bottom, 12)

                    if loading {
                        Spacer()
                        ProgressView()
                            .tint(Color(red: 0.42, green: 0.36, blue: 0.91))
                        Spacer()
                    } else if sessions.isEmpty {
                        Spacer()
                        Text("No calls yet.\nStart your first French lesson!")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(sessions) { session in
                                    SessionCard(session: session) {
                                        selectedSession = session
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                        }
                    }
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
        .fullScreenCover(isPresented: $showSession, onDismiss: { loadSessions() }) {
            SessionView(apiKey: geminiApiKey)
        }
        .onAppear { loadSessions() }
    }

    private func loadSessions() {
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
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.42, green: 0.36, blue: 0.91).opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "character.bubble.fill")
                            .foregroundColor(Color(red: 0.55, green: 0.49, blue: 0.96))
                            .font(.system(size: 20))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.topic ?? "French Practice")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(formatDate(session.startedAt))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
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
