import SwiftUI

/// Prompt (FR + EN reveal), connector chips that live-highlight as used, text editor with
/// word count, and OpenRouter grading (score, corrections, connector feedback, improved version).
struct WritingTaskView: View {
    let task: WritingTask

    private let store = LearningStore()
    private let speech = LessonSpeechService.shared
    @State private var showEnglish = false
    @State private var content = ""
    @State private var isGrading = false
    @State private var feedback: LessonAgentService.WritingFeedback?
    @State private var errorText: String?
    @State private var showQA = false
    @State private var showMarie = false
    @State private var sessionStart = Date()

    private var wordCount: Int {
        content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private var targetConnectorObjects: [Connector] {
        ContentService.shared.connectors()?.connectors.filter { task.targetConnectors.contains($0.id) } ?? []
    }

    private var lessonContext: String { ContentService.shared.lessonContext(writingTask: task) }

    var body: some View {
        ZStack {
            Passeport.parchmentDim.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    promptCard
                    connectorsCard
                    editorCard
                    if isGrading {
                        HStack { Spacer(); ProgressView().tint(Passeport.maroon); Spacer() }
                            .padding(.vertical, 8)
                    }
                    if let feedback {
                        feedbackCard(feedback)
                    }
                    if let errorText {
                        Text(errorText)
                            .font(Passeport.mono(11))
                            .foregroundColor(Passeport.maroon)
                    }
                    Button {
                        submit()
                    } label: {
                        Text(feedback == nil ? "Submit for grading" : "Re-submit")
                    }
                    .buttonStyle(PasseportPrimaryButton())
                    .disabled(isGrading || wordCount < 5)

                    if feedback != nil {
                        Button {
                            speech.deactivate()
                            showMarie = true
                        } label: {
                            HStack {
                                Image(systemName: "phone.fill")
                                Text("Discuss feedback with Marie")
                            }
                            .font(Passeport.mono(11, weight: .medium))
                            .foregroundColor(Passeport.maroon)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(task.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showQA = true
                } label: {
                    Image(systemName: "mic.fill").foregroundColor(Passeport.brass)
                }
            }
            MarieToolbarButton(showMarie: $showMarie) { speech.deactivate() }
        }
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

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            KickerText(text: "Prompt", color: Passeport.slateDim)
            Text(task.promptFr)
                .font(Passeport.body(14))
                .foregroundColor(Passeport.text)
            if showEnglish {
                Text(task.promptEn)
                    .font(Passeport.body(12.5))
                    .foregroundColor(Passeport.slateDim)
            } else {
                Button {
                    withAnimation { showEnglish = true }
                } label: {
                    Text("Show English")
                        .font(Passeport.mono(10.5, weight: .medium))
                        .foregroundColor(Passeport.maroon)
                }
            }
            if !task.rubricHints.isEmpty {
                Divider().overlay(Passeport.hairline).padding(.vertical, 2)
                ForEach(task.rubricHints, id: \.self) { hint in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundColor(Passeport.brass)
                        Text(hint).font(Passeport.mono(10.5)).foregroundColor(Passeport.slateDim)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .passeportCard()
    }

    private var connectorsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            KickerText(text: "Target connectors", color: Passeport.slateDim)
            FlexibleChips(items: targetConnectorObjects, isUsed: { connectorUsed($0) })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .passeportCard()
    }

    private func connectorUsed(_ connector: Connector) -> Bool {
        content.lowercased().contains(connector.fr.lowercased().split(separator: "...").first.map(String.init) ?? connector.fr.lowercased())
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                KickerText(text: "Your response", color: Passeport.slateDim)
                Spacer()
                Text("\(wordCount) / \(task.minWords) words")
                    .font(Passeport.mono(10.5))
                    .foregroundColor(wordCount >= task.minWords ? Passeport.brass : Passeport.slateDim)
            }
            TextEditor(text: $content)
                .font(Passeport.body(13.5))
                .foregroundColor(Passeport.text)
                .tint(Passeport.maroon)
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .background(Passeport.parchmentDim)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .passeportCard()
    }

    private func feedbackCard(_ feedback: LessonAgentService.WritingFeedback) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                KickerText(text: "Feedback", color: Passeport.slateDim)
                Spacer()
                Text(String(format: "%.1f / 10", feedback.scoreOutOf10))
                    .font(Passeport.display(16, weight: .medium))
                    .foregroundColor(Passeport.maroon)
            }

            if !feedback.strengths.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Strengths").font(Passeport.body(12, weight: .medium)).foregroundColor(Passeport.text)
                    ForEach(feedback.strengths, id: \.self) { s in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(Passeport.brass)
                            Text(s).font(Passeport.body(12)).foregroundColor(Passeport.slateDim)
                        }
                    }
                }
            }

            if !feedback.corrections.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Corrections").font(Passeport.body(12, weight: .medium)).foregroundColor(Passeport.text)
                    ForEach(Array(feedback.corrections.enumerated()), id: \.offset) { _, c in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(c.original).font(Passeport.body(11.5)).foregroundColor(Passeport.maroon).strikethrough()
                                Image(systemName: "arrow.right").font(.system(size: 9)).foregroundColor(Passeport.slate)
                                Text(c.fixed).font(Passeport.body(11.5, weight: .medium)).foregroundColor(Passeport.brass)
                            }
                            if !c.why.isEmpty {
                                Text(c.why).font(Passeport.mono(10)).foregroundColor(Passeport.slateDim)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if !feedback.connectorFeedback.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connectors").font(Passeport.body(12, weight: .medium)).foregroundColor(Passeport.text)
                    Text(feedback.connectorFeedback).font(Passeport.body(12)).foregroundColor(Passeport.slateDim)
                }
            }

            if !feedback.improvedVersion.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Improved version").font(Passeport.body(12, weight: .medium)).foregroundColor(Passeport.text)
                        Spacer()
                        Button {
                            speech.speak(items: LessonSpeechService.speechItems(from: feedback.improvedVersion))
                        } label: {
                            Image(systemName: "speaker.wave.2").font(.system(size: 11)).foregroundColor(Passeport.brass)
                        }
                    }
                    Text(feedback.improvedVersion).font(Passeport.body(12.5)).foregroundColor(Passeport.slateDim)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .passeportCard()
    }

    private func submit() {
        isGrading = true
        errorText = nil
        let submittedText = content
        Task {
            do {
                let result = try await LessonAgentService.shared.gradeWriting(task: task, submission: submittedText)
                await MainActor.run {
                    feedback = result
                    isGrading = false
                    store.saveSubmission(taskId: task.id, content: submittedText, feedback: result.improvedVersion, score: result.scoreOutOf10)
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    isGrading = false
                }
            }
        }
    }

    private func logMinutes() {
        let minutes = max(1, Int(Date().timeIntervalSince(sessionStart) / 60))
        guard minutes > 0, !content.isEmpty else { return }
        store.markHabit(date: Date(), habitId: "writing", done: true, addMinutes: minutes)
    }
}

/// Simple wrapping chip row for target connectors, highlighting ones the student has used.
private struct FlexibleChips: View {
    let items: [Connector]
    let isUsed: (Connector) -> Bool

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 90), spacing: 8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items) { connector in
                Text(connector.fr)
                    .font(Passeport.mono(10.5, weight: .medium))
                    .foregroundColor(isUsed(connector) ? .white : Passeport.maroon)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isUsed(connector) ? Passeport.brass : Passeport.maroon.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
    }
}
