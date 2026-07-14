import SwiftUI

/// Sits in front of the vocab stage so today's word list isn't always a black-box auto-pick.
/// Two modes: fully automatic (today's mixed SRS queue, unchanged default), and a category-first
/// manual picker — choose a section (Pronouns, Tech, Immigration & Health, etc.), then a sheet
/// shows just that section's words to select from. Replaces an earlier design that mixed a
/// random themed quick-pick with one giant all-45-sections scrolling list; both are gone in
/// favor of one simpler flow with far less scrolling. Already-known words (SM-2 reps ≥ 3,
/// interval ≥ 21 days — same threshold ProgressService/SRSService use elsewhere) show a green
/// check and are excluded from Auto mode by default, though they can still be manually re-picked.
struct VocabPickerView: View {
    var onComplete: (VocabStageResult) -> Void

    @Environment(\.dismiss) private var dismiss
    private let store = LearningStore()

    private enum Mode: String, CaseIterable, Identifiable {
        case auto = "Auto"
        case category = "By Category"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .auto
    @State private var manualSelection: Set<String> = []
    @State private var activeCategoryTheme: VocabTheme?
    @State private var showSession = false
    @State private var chosenQueue: [VocabEntry] = []
    @State private var focusNote: String?
    @State private var sessionExamples: [String: LessonAgentService.VocabExample] = [:]
    @State private var isPlanning = false

    private var knownIds: Set<String> {
        Set(store.allSRSStates().filter { $0.value.reps >= 3 && $0.value.intervalDays >= 21 }.map { $0.key })
    }

    private var allPhases: [VocabPhase] { ContentService.shared.vocabPhases }

    private var autoQueue: [VocabEntry] { SRSService(store: store).dailyMixedQueue() }

    var body: some View {
        NavigationStack {
            ZStack {
                Passeport.parchmentDim.ignoresSafeArea()
                VStack(spacing: 0) {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)

                    switch mode {
                    case .auto: autoBody
                    case .category: categoryBody
                    }
                }

                if isPlanning {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView().tint(Passeport.maroon)
                        Text("Personalizing today's session…").font(Passeport.mono(11)).foregroundColor(Passeport.slateDim)
                    }
                    .padding(20)
                    .background(Passeport.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .navigationTitle("Today's Words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
            }
        }
        .fullScreenCover(isPresented: $showSession) {
            AgentLedVocabView(vocabQueue: chosenQueue, focusNote: focusNote, examplesByWordId: sessionExamples) { result in
                onComplete(result)
                dismiss()
            }
            .overlay(FloatingNotetakerOverlay())
        }
    }

    // MARK: - Auto mode

    private var autoBody: some View {
        VStack(spacing: 16) {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 30)).foregroundColor(Passeport.brass)
                Text("\(autoQueue.count) words today").font(Passeport.display(20, weight: .medium)).foregroundColor(Passeport.text)
                Text("A mix of words due for review plus new ones, in curriculum order — the same set Marie would pick for you.")
                    .font(Passeport.body(13)).foregroundColor(Passeport.slateDim).multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .frame(maxWidth: .infinity).passeportCard(padding: 24)
            Spacer()
            startButton(count: autoQueue.count) { beginSession(with: autoQueue) }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    // MARK: - Category mode: choose a section up top, select words from a sheet

    private var categoryBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(allPhases, id: \.phase) { phase in
                        VStack(alignment: .leading, spacing: 8) {
                            KickerText(text: "Phase \(phase.phase) · \(phase.title)", color: Passeport.slateDim)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                                ForEach(phase.themes) { theme in
                                    categoryChip(theme: theme)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            startButton(count: manualSelection.count) {
                let all = allPhases.flatMap { $0.themes.flatMap { $0.entries } }
                beginSession(with: all.filter { manualSelection.contains($0.id) })
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Passeport.parchmentDim)
        }
        .sheet(item: $activeCategoryTheme) { theme in
            categoryWordSheet(theme: theme)
        }
    }

    private func selectedCount(in theme: VocabTheme) -> Int {
        theme.entries.filter { manualSelection.contains($0.id) }.count
    }

    private func categoryChip(theme: VocabTheme) -> some View {
        let selected = selectedCount(in: theme)
        let hasSelection = selected > 0
        return Button {
            activeCategoryTheme = theme
        } label: {
            VStack(spacing: 3) {
                Text(theme.title)
                    .font(Passeport.body(12.5, weight: .medium))
                    .foregroundColor(hasSelection ? Passeport.parchment : Passeport.text)
                    .lineLimit(1)
                Text(hasSelection ? "\(selected) of \(theme.entries.count) picked" : "\(theme.entries.count) words")
                    .font(Passeport.mono(9))
                    .foregroundColor(hasSelection ? Passeport.parchment.opacity(0.85) : Passeport.slateDim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(hasSelection ? Passeport.maroon : Passeport.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Passeport.hairline, lineWidth: hasSelection ? 0 : 1))
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Same card-grid structure as the category picker itself, just one level deeper — a compact
    /// 2-column grid of word chips fits far more words on screen than a row-per-word list did.
    private func categoryWordSheet(theme: VocabTheme) -> some View {
        let allSelected = theme.entries.allSatisfy { manualSelection.contains($0.id) }
        return NavigationStack {
            ZStack {
                Passeport.parchmentDim.ignoresSafeArea()
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(theme.entries) { entry in
                            wordChip(entry)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle(theme.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(allSelected ? "Deselect All" : "Select All") {
                        if allSelected {
                            theme.entries.forEach { manualSelection.remove($0.id) }
                        } else {
                            theme.entries.forEach { manualSelection.insert($0.id) }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { activeCategoryTheme = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func wordChip(_ entry: VocabEntry) -> some View {
        let isKnown = knownIds.contains(entry.id)
        let isSelected = manualSelection.contains(entry.id)
        return Button {
            if isSelected { manualSelection.remove(entry.id) } else { manualSelection.insert(entry.id) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(entry.fr)
                        .font(Passeport.body(12.5, weight: .medium))
                        .foregroundColor(isSelected ? Passeport.parchment : Passeport.text)
                        .lineLimit(1)
                    Spacer()
                    if isKnown {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 10)).foregroundColor(.green)
                    }
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? Passeport.parchment : Passeport.slate)
                }
                Text(entry.en)
                    .font(Passeport.mono(9.5))
                    .foregroundColor(isSelected ? Passeport.parchment.opacity(0.85) : Passeport.slateDim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? Passeport.maroon : Passeport.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Passeport.hairline, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Shared

    private func startButton(count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(count > 0 ? "Start with \(count) word\(count == 1 ? "" : "s")" : "Pick some words first")
        }
        .buttonStyle(PasseportPrimaryButton())
        .disabled(count == 0)
    }

    /// Briefly personalizes the session before it starts — the planner call is raced against a
    /// short timeout so a slow/failed OpenRouter call never blocks getting into practice. Example
    /// sentences are no longer generated here at all — they're pre-authored once, offline, for
    /// the entire word bank and looked up instantly via ContentService, so there's nothing to
    /// wait on or fail for that part.
    private func beginSession(with words: [VocabEntry]) {
        guard !words.isEmpty else { return }
        isPlanning = true
        let mistakeTags = store.topMistakeTags()
        let diary = store.recentDiaryEntries()
        Task {
            let planResult = await raceForPlan(words: words, mistakeTags: mistakeTags, diary: diary)
            await MainActor.run {
                if let planResult {
                    focusNote = planResult.focusNote.isEmpty ? nil : planResult.focusNote
                    if let ids = planResult.prioritizedWordIds {
                        let byId = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
                        chosenQueue = ids.compactMap { byId[$0] }
                    } else {
                        chosenQueue = words
                    }
                } else {
                    chosenQueue = words
                }
                sessionExamples = ContentService.shared.vocabExamples(for: words)
                isPlanning = false
                showSession = true
            }
        }
    }

    private static let raceTimeoutNanoseconds: UInt64 = 14_000_000_000

    private func raceForPlan(words: [VocabEntry], mistakeTags: [(tag: String, description: String, count: Int)], diary: [String]) async -> LessonAgentService.SessionPlan? {
        await withTaskGroup(of: LessonAgentService.SessionPlan?.self) { group in
            group.addTask { try? await LessonAgentService.shared.planVocabSession(candidateWords: words, mistakeTags: mistakeTags, recentDiary: diary) }
            group.addTask { try? await Task.sleep(nanoseconds: Self.raceTimeoutNanoseconds); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
