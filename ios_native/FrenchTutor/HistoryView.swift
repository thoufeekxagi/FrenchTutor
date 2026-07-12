import SwiftUI

struct HistoryView: View {
    let session: Session
    @State private var messages: [(role: String, content: String)] = []
    @State private var loading = true

    private let storage = StorageService()

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            if loading {
                ProgressView()
                    .tint(Color(red: 0.42, green: 0.36, blue: 0.91))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        sessionInfo

                        if let summary = session.summary, !summary.isEmpty {
                            summaryCard(summary)
                        }

                        if !session.vocabulary.isEmpty {
                            vocabularyCard
                        }

                        Text("Full Transcript")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)

                        ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                            transcriptItem(msg)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadMessages() }
    }

    private var sessionInfo: some View {
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
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text(formatDate(session.startedAt))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func summaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "list.clipboard.fill")
                    .foregroundColor(Color(red: 0.55, green: 0.49, blue: 0.96))
                    .font(.system(size: 16))
                Text("Session Summary")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Text(summary)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(red: 0.42, green: 0.36, blue: 0.91).opacity(0.2), lineWidth: 1)
        )
    }

    private var vocabularyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "book.fill")
                    .foregroundColor(Color(red: 0.29, green: 0.87, blue: 0.50))
                    .font(.system(size: 16))
                Text("Vocabulary")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            }
            FlowLayout(spacing: 8) {
                ForEach(session.vocabulary, id: \.self) { word in
                    Text(word)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(Color(red: 0.20, green: 0.65, blue: 0.35))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.20, green: 0.65, blue: 0.35).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(red: 0.20, green: 0.65, blue: 0.35).opacity(0.2), lineWidth: 1)
        )
    }

    private func transcriptItem(_ msg: (role: String, content: String)) -> some View {
        let isUser = msg.role == "user"
        return HStack {
            if !isUser {
                Image(systemName: "graduationcap.fill")
                    .foregroundColor(Color(red: 0.55, green: 0.49, blue: 0.96))
                    .font(.system(size: 14))
            }
            if !isUser { Spacer().frame(width: 8) }

            Text(msg.content)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(isUser ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isUser
                        ? Color(red: 0.42, green: 0.36, blue: 0.91)
                        : Color(.secondarySystemGroupedBackground)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if isUser { Spacer().frame(width: 8) }
            if isUser {
                Image(systemName: "person.fill")
                    .foregroundColor(Color(red: 0.42, green: 0.36, blue: 0.91))
                    .font(.system(size: 14))
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private func loadMessages() {
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = storage.getSessionMessages(sessionId: session.id)
            DispatchQueue.main.async {
                messages = loaded
                loading = false
            }
        }
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let display = DateFormatter()
        display.dateFormat = "MMM d, y • h:mm a"
        return display.string(from: date)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
