import SwiftUI

/// Bottom-sheet voice Q&A used by every lab: mic → STT → LessonAgentService → TTS reply.
/// Owns a single LessonSpeechService instance passed in by the caller so narration and
/// Q&A share one audio-session owner.
struct LessonQAOverlay: View {
    let lessonContext: String
    let speech: LessonSpeechService
    var sttLocale: String = "en-US"
    @Binding var isPresented: Bool

    @State private var partialTranscript = ""
    @State private var answer: String?
    @State private var errorText: String?
    @State private var isListening = false
    @State private var isThinking = false
    @State private var history: [(role: String, text: String)] = []

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(Passeport.hairline)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            HStack {
                Text("Ask Marie's assistant")
                    .font(Passeport.display(15, weight: .medium))
                    .foregroundColor(Passeport.text)
                Spacer()
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Passeport.slate)
                        .font(.system(size: 20))
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !partialTranscript.isEmpty || isListening {
                        Text(partialTranscript.isEmpty ? "Listening…" : partialTranscript)
                            .font(Passeport.body(13.5))
                            .foregroundColor(Passeport.slateDim)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    if let answer {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundColor(Passeport.brass)
                                .font(.system(size: 13))
                            Text(answer)
                                .font(Passeport.body(13.5))
                                .foregroundColor(Passeport.text)
                        }
                    }
                    if let errorText {
                        Text(errorText)
                            .font(Passeport.mono(11))
                            .foregroundColor(Passeport.maroon)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)

            HStack(spacing: 16) {
                if answer != nil {
                    Button {
                        replay()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Passeport.slateDim)
                            .frame(width: 44, height: 44)
                            .background(Passeport.parchmentDim)
                            .clipShape(Circle())
                    }
                }

                Button {
                    toggleMic()
                } label: {
                    Image(systemName: isListening ? "mic.fill" : "mic")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .frame(width: 64, height: 64)
                        .background(isThinking ? Passeport.slate : Passeport.brass)
                        .clipShape(Circle())
                }
                .disabled(isThinking)

                if isThinking {
                    ProgressView().tint(Passeport.maroon)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
        .background(Passeport.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onDisappear { speech.stopListening() }
    }

    private func toggleMic() {
        if isListening {
            speech.stopListening()
            isListening = false
            return
        }
        speech.stop() // don't listen while narration is speaking
        errorText = nil
        isListening = true
        speech.startListening(
            locale: sttLocale,
            onPartial: { text in partialTranscript = text },
            onFinal: { finalText in
                isListening = false
                guard !finalText.trimmingCharacters(in: .whitespaces).isEmpty else {
                    partialTranscript = ""
                    return
                }
                ask(finalText)
            }
        )
    }

    private func ask(_ question: String) {
        isThinking = true
        answer = nil
        errorText = nil
        Task {
            do {
                let reply = try await LessonAgentService.shared.askQuestion(
                    lessonContext: lessonContext,
                    question: question,
                    history: history
                )
                await MainActor.run {
                    history.append((role: "user", text: question))
                    history.append((role: "assistant", text: reply))
                    answer = reply
                    partialTranscript = ""
                    isThinking = false
                    speech.speak(items: [.init(text: reply, language: "en-US")])
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    isThinking = false
                }
            }
        }
    }

    private func replay() {
        guard let answer else { return }
        speech.speak(items: [.init(text: answer, language: "en-US")])
    }

    private func close() {
        speech.stopListening()
        isPresented = false
    }
}
