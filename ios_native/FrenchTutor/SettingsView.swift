import SwiftUI

private let availableModels = [
    "meta-llama/llama-3.3-70b-instruct:free",
    "google/gemma-3-27b-it:free",
    "mistralai/mistral-small-3.1-24b-instruct:free"
]

struct SettingsView: View {
    @AppStorage("openrouter_model_override") private var modelOverride = ""
    @AppStorage("lesson_narration_rate") private var narrationRate: Double = 0.42
    @AppStorage("srs_new_cards_per_day") private var newCardsPerDay = 20
    @AppStorage("roadmap_start_date") private var roadmapStartTimestamp: Double = Date().timeIntervalSinceReferenceDate

    @State private var testResult: String?
    @State private var isTesting = false

    @ObservedObject private var notetaker = NotetakerState.shared

    private var roadmapStartDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSinceReferenceDate: roadmapStartTimestamp) },
            set: { roadmapStartTimestamp = $0.timeIntervalSinceReferenceDate }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Passeport.parchmentDim.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        VStack(spacing: 0) {
                            SettingsRow(label: "Exam", value: "TEF Canada")
                            Divider().overlay(Passeport.hairline)
                            SettingsRow(label: "Target", value: "CLB 7")
                        }
                        .passeportCard(padding: 14)

                        VStack(alignment: .leading, spacing: 10) {
                            KickerText(text: "Roadmap", color: Passeport.slateDim)
                            DatePicker("Start date", selection: roadmapStartDate, displayedComponents: .date)
                                .font(Passeport.body(12.5))
                                .tint(Passeport.maroon)
                        }
                        .passeportCard(padding: 14)

                        VStack(alignment: .leading, spacing: 10) {
                            KickerText(text: "Lesson voice", color: Passeport.slateDim)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Narration rate")
                                    .font(Passeport.body(12.5))
                                    .foregroundColor(Passeport.slateDim)
                                Slider(value: $narrationRate, in: 0.3...0.55)
                                    .tint(Passeport.maroon)
                            }
                            Stepper("New cards/day: \(newCardsPerDay)", value: $newCardsPerDay, in: 5...50, step: 5)
                                .font(Passeport.body(12.5))
                                .foregroundColor(Passeport.text)
                        }
                        .passeportCard(padding: 14)

                        VStack(alignment: .leading, spacing: 10) {
                            KickerText(text: "AI tutor (OpenRouter)", color: Passeport.slateDim)
                            SettingsRow(label: "Key status", value: openRouterApiKey.isEmpty ? "Not set" : "Configured")
                            Divider().overlay(Passeport.hairline)
                            Picker("Preferred model", selection: $modelOverride) {
                                Text("Auto (fallback chain)").tag("")
                                ForEach(availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .font(Passeport.body(12.5))
                            .tint(Passeport.maroon)

                            #if DEBUG
                            Divider().overlay(Passeport.hairline)
                            Button {
                                testOpenRouter()
                            } label: {
                                HStack {
                                    Text(isTesting ? "Testing…" : "Test OpenRouter")
                                        .font(Passeport.body(12.5, weight: .medium))
                                    if isTesting { Spacer(); ProgressView() }
                                }
                            }
                            .disabled(isTesting)
                            .foregroundColor(Passeport.maroon)
                            if let testResult {
                                Text(testResult)
                                    .font(Passeport.mono(10.5))
                                    .foregroundColor(Passeport.slateDim)
                            }
                            #endif
                        }
                        .passeportCard(padding: 14)

                        VStack(alignment: .leading, spacing: 10) {
                            KickerText(text: "Notetaker", color: Passeport.slateDim)
                            Toggle("Floating notetaker", isOn: $notetaker.isEnabled)
                                .font(Passeport.body(12.5))
                                .tint(Passeport.maroon)
                            Text("Shows a draggable note bubble during lessons so you can jot things down while listening or writing.")
                                .font(Passeport.body(11))
                                .foregroundColor(Passeport.slateDim)
                        }
                        .passeportCard(padding: 14)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    #if DEBUG
    private func testOpenRouter() {
        isTesting = true
        testResult = nil
        Task {
            do {
                let reply = try await LessonAgentService.shared.askQuestion(
                    lessonContext: "LESSON: greetings — bonjour, salut, bonsoir.",
                    question: "Say hello in French and explain briefly."
                )
                await MainActor.run {
                    testResult = "✓ " + reply
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "✗ " + (error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }
    #endif
}

struct SettingsRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(Passeport.body(12.5))
                .foregroundColor(Passeport.slateDim)
            Spacer()
            Text(value)
                .font(Passeport.mono(12, weight: .medium))
                .foregroundColor(Passeport.text)
        }
        .padding(.vertical, 11)
    }
}
