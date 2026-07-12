import SwiftUI

/// Writing tasks grouped by type, with best-score badges from past submissions.
struct WritingLabView: View {
    private let store = LearningStore()
    @State private var refreshToken = UUID()

    private var typeLabels: [String: String] {
        ["email": "Emails", "complaint_letter": "Complaint letters",
         "opinion_essay": "Opinion essays", "formal_request": "Formal requests"]
    }

    var body: some View {
        ZStack {
            Passeport.parchmentDim.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let pack = ContentService.shared.writingTasks() {
                        ForEach(Array(groupedTypes(pack.tasks)), id: \.self) { type in
                            let tasks = pack.tasks.filter { $0.type == type }
                            VStack(alignment: .leading, spacing: 8) {
                                KickerText(text: typeLabels[type] ?? type, color: Passeport.slateDim)
                                VStack(spacing: 0) {
                                    ForEach(Array(tasks.enumerated()), id: \.element.id) { i, task in
                                        NavigationLink(destination: WritingTaskView(task: task)) {
                                            row(task)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        if i < tasks.count - 1 {
                                            Divider().overlay(Passeport.hairline)
                                        }
                                    }
                                }
                                .passeportCard(padding: 4)
                            }
                        }
                    } else {
                        Text("Writing content unavailable.")
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
        .navigationTitle("Writing")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshToken = UUID() }
    }

    private func groupedTypes(_ tasks: [WritingTask]) -> [String] {
        var seen: [String] = []
        for t in tasks where !seen.contains(t.type) { seen.append(t.type) }
        return seen
    }

    private func row(_ task: WritingTask) -> some View {
        let submissions = store.submissions(for: task.id)
        let bestScore = submissions.compactMap { $0.score }.max()
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(Passeport.body(13.5, weight: .medium))
                    .foregroundColor(Passeport.text)
                Text("Min \(task.minWords) words · \(task.targetConnectors.count) target connectors")
                    .font(Passeport.mono(10.5))
                    .foregroundColor(Passeport.slateDim)
            }
            Spacer()
            if let bestScore {
                Text(String(format: "%.1f/10", bestScore))
                    .font(Passeport.mono(10.5, weight: .medium))
                    .foregroundColor(Passeport.brass)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(Passeport.slate)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
