import SwiftUI
import Combine

/// Shared state for the floating notetaker bubble — one instance mounted at both the tab-bar
/// level and inside each full-screen workshop stage, so drag position, draft text, and the
/// on/off toggle stay in sync no matter which layer is on screen.
final class NotetakerState: ObservableObject {
    static let shared = NotetakerState()

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "notetaker.enabled") }
    }
    @Published var isExpanded = false
    @Published var draftText = ""
    /// Bubble position, stored as an offset from the default bottom-trailing anchor so it survives
    /// screen rotation/size changes reasonably (re-clamped on each drag).
    @Published var offset: CGSize {
        didSet {
            UserDefaults.standard.set(Double(offset.width), forKey: "notetaker.offsetX")
            UserDefaults.standard.set(Double(offset.height), forKey: "notetaker.offsetY")
        }
    }
    /// Lesson/module label the current screen tags new notes with — set by whichever workshop
    /// screen is on top (e.g. "Vocabulary", "Listening"); defaults to "General" elsewhere.
    @Published var currentContext = "General"

    private var draftNoteId: Int64?
    private var lastAutosavedWordCount = 0
    private let storage = StorageService()

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: "notetaker.enabled") as? Bool ?? true
        let x = UserDefaults.standard.double(forKey: "notetaker.offsetX")
        let y = UserDefaults.standard.double(forKey: "notetaker.offsetY")
        offset = CGSize(width: x, height: y)
    }

    /// Called on every keystroke. Only actually touches the database once the draft has grown by
    /// another 5-6 words since the last autosave, so typing itself never triggers I/O.
    func noteDraftChanged() {
        let wordCount = draftText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        guard wordCount > 0, wordCount - lastAutosavedWordCount >= 5 else { return }
        lastAutosavedWordCount = wordCount
        draftNoteId = storage.saveNote(id: draftNoteId, tag: currentContext, text: draftText)
    }

    /// Manual Save button — commits whatever's left (even under the 5-word autosave threshold)
    /// and clears the draft so the bubble reopens empty next time.
    func commitDraft() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            storage.saveNote(id: draftNoteId, tag: currentContext, text: trimmed)
        }
        draftText = ""
        draftNoteId = nil
        lastAutosavedWordCount = 0
        isExpanded = false
    }

    /// Collapse without discarding — the partial draft (already autosaved past 5 words, or just
    /// held in memory below that) is restored next time the bubble is expanded.
    func collapse() {
        isExpanded = false
    }

    func allNotes() -> [Note] {
        storage.getAllNotes()
    }

    func deleteNote(id: Int64) {
        storage.deleteNote(id: id)
    }
}

/// The floating bubble + expandable note card. Mount once per presentation layer (tab bar root,
/// and inside each full-screen workshop cover) bound to the same `NotetakerState.shared` — drag
/// position and draft text carry over between mounts automatically.
struct FloatingNotetakerOverlay: View {
    @ObservedObject private var state = NotetakerState.shared
    @FocusState private var isFocused: Bool

    private let bubbleSize: CGFloat = 52

    var body: some View {
        GeometryReader { geo in
            if state.isEnabled {
                ZStack(alignment: .bottomTrailing) {
                    if state.isExpanded {
                        expandedCard
                            .padding(.bottom, bubbleSize + 12)
                            .padding(.trailing, 4)
                            .transition(.scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity))
                    }
                    bubble
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(clampedOffset(in: geo.size))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.isExpanded)
            }
        }
        .allowsHitTesting(state.isEnabled)
    }

    private func clampedOffset(in size: CGSize) -> CGSize {
        // The bubble is anchored bottom-trailing with 16pt padding; `offset` is a drag delta from
        // that resting position, clamped so it (and the card above it, while expanded) never
        // leaves the screen bounds.
        let topInset: CGFloat = state.isExpanded ? 240 : 16
        let minWidth = -(size.width - bubbleSize - 32)
        let minHeight = -(size.height - bubbleSize - 16 - topInset)
        return CGSize(
            width: min(max(state.offset.width, minWidth), 0),
            height: min(max(state.offset.height, minHeight), 0)
        )
    }

    private var bubble: some View {
        Circle()
            .fill(Passeport.maroon)
            .frame(width: bubbleSize, height: bubbleSize)
            .overlay(
                Image(systemName: state.isExpanded ? "chevron.down" : "pencil.and.outline")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Passeport.parchment)
            )
            .shadow(color: Passeport.ink.opacity(0.25), radius: 6, y: 3)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        state.offset = CGSize(
                            width: state.offset.width + value.translation.width,
                            height: state.offset.height + value.translation.height
                        )
                    }
            )
            .onTapGesture {
                if state.isExpanded {
                    state.collapse()
                } else {
                    state.isExpanded = true
                    isFocused = true
                }
            }
            .contextMenu {
                Button(role: .destructive) {
                    state.isEnabled = false
                } label: {
                    Label("Hide notetaker", systemImage: "eye.slash")
                }
            }
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(state.currentContext.uppercased())
                    .font(Passeport.mono(9.5, weight: .medium))
                    .foregroundColor(Passeport.maroon)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Passeport.maroon.opacity(0.1))
                    .clipShape(Capsule())
                Spacer()
                Button {
                    state.collapse()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Passeport.slateDim)
                }
            }

            TextEditor(text: Binding(
                get: { state.draftText },
                set: { newValue in
                    state.draftText = newValue
                    state.noteDraftChanged()
                }
            ))
            .focused($isFocused)
            .font(Passeport.body(13))
            .foregroundColor(Passeport.text)
            .scrollContentBackground(.hidden)
            .frame(height: 90)
            .overlay(
                Group {
                    if state.draftText.isEmpty {
                        Text("Type what you're hearing or reading…")
                            .font(Passeport.body(13))
                            .foregroundColor(Passeport.slate)
                            .padding(.top, 8).padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                },
                alignment: .topLeading
            )

            Button {
                state.commitDraft()
            } label: {
                Text("Save note")
                    .font(Passeport.body(12.5, weight: .medium))
                    .foregroundColor(Passeport.parchment)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Passeport.maroon)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(state.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .frame(width: 280)
        .background(Passeport.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Passeport.hairline, lineWidth: 1))
        .shadow(color: Passeport.ink.opacity(0.15), radius: 10, y: 4)
    }
}
