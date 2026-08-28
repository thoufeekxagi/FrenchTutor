/// The renderer used for newly created Listening lessons.
///
/// Keep this as one explicit switch so a later ElevenLabs re-enable does not
/// require changing the lesson screen or the persistence flow. Gemini Live is
/// the currently supported spoken renderer; Google Lyria is not wired into
/// this app and is a music-generation API rather than a narration voice.
enum ListeningAudioProvider { geminiLive, elevenLabs }

const listeningAudioProvider = ListeningAudioProvider.geminiLive;
