import SwiftUI

struct ListeningStageResult {
    let grammarDrillResults: [Bool]
    let listeningCorrect: Int
    let listeningAttempted: Int
}

/// Daily Pathway stage 2 — reading/grammar review woven together with a listening passage,
/// in its own focused Gemini Live session (own small tool palette, own context) fed a summary
/// of the vocabulary just covered in stage 1. Ends when the student taps Continue, not on a
/// model-remembered tool call — more reliable than relying on the model to signal completion.
struct AgentLedListeningView: View {
    let grammarLesson: GrammarLesson?
    let grammarTopic: GrammarTopic?
    let listeningExercise: ListeningExercise?
    let vocabSummary: VocabStageResult?
    var onComplete: (ListeningStageResult) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var gemini: GeminiLiveService
    private let audio = AudioStreamingService()
    private let store = LearningStore()

    @State private var callStatus: CallStatus = .connecting
    @State private var callDuration = 0
    @State private var timer: Timer?
    @State private var errorMessage = ""
    @State private var showEndConfirm = false
    @State private var finished = false

    // Same "don't get stuck" watchdog used in the vocab stage.
    @State private var lastAudioChunkAt = Date()
    @State private var speakingWatchdog: Timer?

    @State private var highlightedVerb: String?
    @State private var activeDrillIndex: Int?
    @State private var grammarDrillResults: [Bool] = []
    @State private var listeningQuestion: (q: String, choices: [String])?
    @State private var selectedListeningChoice: Int?
    @State private var listeningAnswerResult: (choiceIndex: Int, correct: Bool)?
    @State private var listeningCorrectCount = 0
    @State private var listeningAttempted = 0

    init(grammarLesson: GrammarLesson?, grammarTopic: GrammarTopic?, listeningExercise: ListeningExercise?, vocabSummary: VocabStageResult?, onComplete: @escaping (ListeningStageResult) -> Void) {
        self.grammarLesson = grammarLesson
        self.grammarTopic = grammarTopic
        self.listeningExercise = listeningExercise
        self.vocabSummary = vocabSummary
        self.onComplete = onComplete
        let context = AgentLedListeningView.buildContext(grammarLesson: grammarLesson, grammarTopic: grammarTopic, listening: listeningExercise, vocabSummary: vocabSummary)
        _gemini = State(initialValue: GeminiLiveService(apiKey: geminiApiKey, lessonContext: context, tools: AgentTool.listeningPalette))
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView { content.padding(.horizontal, 18).padding(.vertical, 16) }
                if !errorMessage.isEmpty {
                    Text(errorMessage).font(.system(size: 12, design: .rounded)).foregroundColor(Passeport.maroon)
                        .padding(.horizontal, 20).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                }
                continueButton
                controls
            }
        }
        .onAppear { setupCallbacks(); gemini.connect() }
        .onDisappear { finishAndReturn() }
        .alert("End this section?", isPresented: $showEndConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("End", role: .destructive) { finishAndReturn() }
        } message: { Text("Your progress so far is saved.") }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Button { showEndConfirm = true } label: {
                    Image(systemName: "xmark").font(.system(size: 18)).foregroundColor(Passeport.text)
                }
                Spacer()
                Text(formatDuration(callDuration)).font(Passeport.mono(13, weight: .medium)).foregroundColor(Passeport.slateDim)
                Spacer()
                Circle().fill(statusColor).frame(width: 10, height: 10)
            }
            .padding(.horizontal, 20).padding(.top, 12)
            VStack(spacing: 2) {
                Text("Reading & Listening").font(Passeport.display(20, weight: .semibold)).foregroundColor(Passeport.text)
                Text(statusText).font(Passeport.mono(11.5)).foregroundColor(Passeport.slateDim)
            }
            .padding(.top, 6)
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 14) {
            if let lesson = grammarLesson {
                VStack(alignment: .leading, spacing: 8) {
                    KickerText(text: "Grammar focus: \(lesson.title)", color: Passeport.slateDim)
                    ForEach(lesson.usage, id: \.self) { line in
                        Text("• \(line)").font(Passeport.body(13)).foregroundColor(Passeport.text)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).passeportCard()

                ForEach(lesson.conjugations) { conj in
                    ConjugationTableView(verb: conj.verb, group: conj.group, rows: conj.rows)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isHighlighted(conj.verb) ? Passeport.brass : .clear, lineWidth: 2))
                }

                if let index = activeDrillIndex, index < lesson.drills.count {
                    DrillView(drill: lesson.drills[index], index: index, lessonContext: ContentService.shared.lessonContext(grammarLesson: lesson)) { correct in
                        grammarDrillResults.append(correct)
                        gemini.injectContext("The student tapped an answer to that drill; it was \(correct ? "correct" : "incorrect"). Confirm this to them and continue.")
                    }
                    .passeportCard()
                }
            } else if let topic = grammarTopic {
                ForEach(topic.sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        KickerText(text: section.heading, color: Passeport.slateDim)
                        Text(section.body).font(Passeport.body(13)).foregroundColor(Passeport.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).passeportCard()
                }
            }

            if let listeningQuestion {
                VStack(alignment: .leading, spacing: 10) {
                    KickerText(text: "Comprehension", color: Passeport.slateDim)
                    Text(listeningQuestion.q).font(Passeport.body(13.5, weight: .medium)).foregroundColor(Passeport.text)
                    ForEach(Array(listeningQuestion.choices.enumerated()), id: \.offset) { i, choice in
                        Button {
                            selectedListeningChoice = i
                            gemini.injectContext("The student tapped choice \(i + 1): \"\(choice)\". Tell them if that's right and continue.")
                        } label: {
                            HStack {
                                Text(choice).font(Passeport.body(12.5))
                                Spacer()
                                if let result = listeningAnswerResult, result.choiceIndex == i {
                                    Image(systemName: result.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(result.correct ? Passeport.brass : Passeport.maroon)
                                } else if selectedListeningChoice == i {
                                    Image(systemName: "circle.fill").font(.system(size: 8)).foregroundColor(Passeport.slate)
                                }
                            }
                            .foregroundColor(Passeport.text)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Passeport.parchmentDim)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).passeportCard()
            } else if listeningExercise != nil {
                VStack(spacing: 8) {
                    Image(systemName: "headphones").font(.system(size: 24)).foregroundColor(Passeport.brass)
                    Text("Marie is reading today's passage aloud — listen closely.")
                        .font(Passeport.body(13)).foregroundColor(Passeport.slateDim).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).passeportCard()
            }
        }
    }

    private func isHighlighted(_ verb: String) -> Bool {
        guard let highlightedVerb, !highlightedVerb.isEmpty else { return false }
        return verb.lowercased().contains(highlightedVerb.lowercased()) || highlightedVerb.lowercased().contains(verb.lowercased())
    }

    private var continueButton: some View {
        Button { finishAndReturn() } label: { Text("Continue to Speaking →") }
            .buttonStyle(PasseportPrimaryButton())
            .padding(.horizontal, 18)
            .padding(.top, 4)
    }

    private var controls: some View {
        HStack(spacing: 40) {
            Button { toggleMute() } label: {
                VStack(spacing: 6) {
                    Image(systemName: callStatus == .muted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 22)).foregroundColor(.white)
                        .frame(width: 54, height: 54)
                        .background(callStatus == .muted ? Passeport.slate : Passeport.maroon)
                        .clipShape(Circle())
                    Text(callStatus == .muted ? "Muted" : "Mic on").font(Passeport.mono(10)).foregroundColor(Passeport.slateDim)
                }
            }
            .disabled(callStatus == .connecting || callStatus == .ended)
        }
        .padding(.vertical, 16)
    }

    private var statusColor: Color {
        switch callStatus {
        case .connecting: return .orange
        case .listening: return .green
        case .tutorSpeaking: return Passeport.maroon
        case .muted: return Passeport.slate
        case .ended: return Passeport.slate.opacity(0.5)
        }
    }
    private var statusText: String {
        switch callStatus {
        case .connecting: return "connecting…"
        case .listening: return "listening"
        case .tutorSpeaking: return "Marie is speaking"
        case .muted: return "muted"
        case .ended: return "ended"
        }
    }

    private func toggleMute() {
        if callStatus == .muted {
            do { try audio.startStreaming { chunk in gemini.sendAudioChunk(chunk) }; callStatus = .listening }
            catch { errorMessage = "Failed to unmute: \(error.localizedDescription)" }
        } else {
            audio.stopStreaming()
            callStatus = .muted
        }
    }

    private func formatDuration(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

    private func setupCallbacks() {
        gemini.onConnected = {
            callStatus = .listening
            if timer == nil { timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in callDuration += 1 } }
            audio.requestPermission { granted in
                if granted {
                    do { try audio.startStreaming { chunk in gemini.sendAudioChunk(chunk) } }
                    catch { errorMessage = "Mic error: \(error.localizedDescription)" }
                } else {
                    errorMessage = "Microphone permission denied"
                }
            }
        }
        gemini.onDisconnected = { if !finished { errorMessage = "Connection lost"; finishAndReturn() } }
        gemini.onError = { msg in errorMessage = msg }
        gemini.onAudioChunk = { data in
            lastAudioChunkAt = Date()
            audio.isOutputActive = true
            audio.playAudioChunk(data)
            if callStatus != .tutorSpeaking { callStatus = .tutorSpeaking }
        }
        gemini.onTurnComplete = {
            audio.isOutputActive = false
            if callStatus != .muted { callStatus = .listening }
        }
        gemini.onInterrupted = {
            audio.isOutputActive = false
            audio.stopPlayback()
            if callStatus != .muted { callStatus = .listening }
        }
        gemini.onToolCall = { name, args, callId in handleToolCall(name: name, args: args, callId: callId) }

        speakingWatchdog?.invalidate()
        speakingWatchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if callStatus == .tutorSpeaking, Date().timeIntervalSince(lastAudioChunkAt) > 2.5 {
                audio.isOutputActive = false
                callStatus = .listening
            }
        }
    }

    private func handleToolCall(name: String, args: [String: Any], callId: String) {
        switch name {
        case "show_conjugation":
            highlightedVerb = args["verb"] as? String
            gemini.sendToolResponse(callId: callId, name: name, result: ["ok": true])
        case "ask_drill":
            activeDrillIndex = args["index"] as? Int
            gemini.sendToolResponse(callId: callId, name: name, result: ["ok": true])
        case "grade_drill":
            if let correct = args["correct"] as? Bool { grammarDrillResults.append(correct) }
            gemini.sendToolResponse(callId: callId, name: name, result: ["ok": true], scheduling: "SILENT")
        case "show_question":
            listeningQuestion = (args["question"] as? String ?? "", args["choices"] as? [String] ?? [])
            selectedListeningChoice = nil
            listeningAnswerResult = nil
            gemini.sendToolResponse(callId: callId, name: name, result: ["ok": true])
        case "mark_answer":
            if let idx = args["choice_index"] as? Int, let correct = args["correct"] as? Bool {
                listeningAnswerResult = (idx, correct)
                listeningAttempted += 1
                if correct { listeningCorrectCount += 1 }
            }
            gemini.sendToolResponse(callId: callId, name: name, result: ["ok": true], scheduling: "SILENT")
        default:
            gemini.sendToolResponse(callId: callId, name: name, result: ["ok": false, "error": "unknown tool"])
        }
    }

    private func finishAndReturn() {
        guard !finished else { return }
        finished = true
        timer?.invalidate()
        speakingWatchdog?.invalidate()
        audio.stopStreaming()
        gemini.disconnect()
        callStatus = .ended
        if !grammarDrillResults.isEmpty {
            let score = Double(grammarDrillResults.filter { $0 }.count) / Double(grammarDrillResults.count)
            let id = grammarLesson?.id ?? grammarTopic?.id
            if let id { store.setLessonStatus(id, status: score >= 0.8 ? "completed" : "in_progress", score: score) }
        }
        if let exercise = listeningExercise, listeningAttempted > 0 {
            store.setLessonStatus("listening_\(exercise.id)", status: listeningCorrectCount > 0 ? "completed" : "in_progress", score: nil)
        }
        onComplete(ListeningStageResult(grammarDrillResults: grammarDrillResults, listeningCorrect: listeningCorrectCount, listeningAttempted: listeningAttempted))
        dismiss()
    }

    private static func buildContext(grammarLesson: GrammarLesson?, grammarTopic: GrammarTopic?, listening: ListeningExercise?, vocabSummary: VocabStageResult?) -> String {
        var parts: [String] = []
        parts.append("""
        READING & LISTENING STAGE — this session covers today's grammar focus and a listening \
        passage. If a VOCABULARY JUST COVERED list is provided below, naturally weave a couple of \
        those words into your discussion or examples where it fits.
        """)
        if let vocabSummary, !vocabSummary.wordsCovered.isEmpty {
            let words = vocabSummary.wordsCovered.map { $0.fr }.joined(separator: ", ")
            parts.append("VOCABULARY JUST COVERED (in the previous stage): \(words)")
        }
        if let grammarLesson {
            parts.append("GRAMMAR: walk through this tense's usage and conjugation tables verbally. Call show_conjugation with a verb name when discussing its table. Use ask_drill then grade_drill to quiz the student on 2-3 drills.")
            parts.append(ContentService.shared.lessonContext(grammarLesson: grammarLesson))
        } else if let grammarTopic {
            parts.append("GRAMMAR: discuss this topic's sections verbally with an example or two.")
            parts.append(ContentService.shared.lessonContext(topic: grammarTopic))
        }
        if let listening {
            parts.append("LISTENING: read the SCRIPT below aloud yourself, naturally, as if narrating a short story. Then call show_question with one comprehension question and 2-3 choices, wait for the student's spoken answer, and call mark_answer.")
            parts.append(ContentService.shared.lessonContext(listeningExercise: listening))
        }
        parts.append("The student will tap a Continue button when ready to move to the Speaking stage — you don't need to end the session yourself, just keep the conversation natural and responsive.")
        return parts.joined(separator: "\n\n")
    }
}
