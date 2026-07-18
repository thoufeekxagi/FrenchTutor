/// Transcript language filter (PILOT_EXECUTION_PLAN.md P0.1).
///
/// The app works in French and English only. When the live mic picks up speech in
/// another language, that transcript line is OMITTED — never shown in the on-screen
/// transcript, never logged to the session record, never fed to the intent judge
/// (it can only misfire on it).
///
/// Detection is script-based and fully on-device: French and English are written in
/// Latin script, so a line whose letters are substantially non-Latin (Malayalam,
/// Tamil, Arabic, Devanagari, CJK, Cyrillic, …) cannot be either. Latin-script
/// third languages (e.g. Spanish) pass through here — the prompt-level rule covers
/// those — but every non-Latin-script language is caught deterministically, with
/// zero latency and zero API cost.
library;

/// True when [text] is displayable in a French/English transcript: its letters are
/// entirely (or almost entirely) Latin script. Lines with no letters at all
/// (numbers, punctuation) are kept.
bool isFrenchEnglishTranscript(String text) {
  var latin = 0;
  var nonLatin = 0;
  for (final rune in text.runes) {
    if (_isLatinLetter(rune)) {
      latin += 1;
    } else if (_isNonLatinLetter(rune)) {
      nonLatin += 1;
    }
  }
  if (nonLatin == 0) return true;
  // A stray foreign character inside an otherwise-French line (a name, a mic
  // artifact) shouldn't nuke the line; substantially foreign lines are omitted.
  return nonLatin / (latin + nonLatin) <= 0.3;
}

bool _isLatinLetter(int rune) {
  return (rune >= 0x41 && rune <= 0x5A) || // A-Z
      (rune >= 0x61 && rune <= 0x7A) || // a-z
      (rune >= 0xC0 && rune <= 0xFF && rune != 0xD7 && rune != 0xF7) || // à é ç …
      (rune >= 0x100 && rune <= 0x17F) || // Latin Extended-A (œ, etc.)
      (rune >= 0x180 && rune <= 0x24F); // Latin Extended-B
}

bool _isNonLatinLetter(int rune) {
  return (rune >= 0x0370 && rune <= 0x03FF) || // Greek
      (rune >= 0x0400 && rune <= 0x04FF) || // Cyrillic
      (rune >= 0x0530 && rune <= 0x058F) || // Armenian
      (rune >= 0x0590 && rune <= 0x05FF) || // Hebrew
      (rune >= 0x0600 && rune <= 0x06FF) || // Arabic
      (rune >= 0x0700 && rune <= 0x074F) || // Syriac
      (rune >= 0x0750 && rune <= 0x077F) || // Arabic Supplement
      (rune >= 0x0900 && rune <= 0x097F) || // Devanagari (Hindi)
      (rune >= 0x0980 && rune <= 0x09FF) || // Bengali
      (rune >= 0x0A00 && rune <= 0x0A7F) || // Gurmukhi (Punjabi)
      (rune >= 0x0A80 && rune <= 0x0AFF) || // Gujarati
      (rune >= 0x0B00 && rune <= 0x0B7F) || // Oriya
      (rune >= 0x0B80 && rune <= 0x0BFF) || // Tamil
      (rune >= 0x0C00 && rune <= 0x0C7F) || // Telugu
      (rune >= 0x0C80 && rune <= 0x0CFF) || // Kannada
      (rune >= 0x0D00 && rune <= 0x0D7F) || // Malayalam
      (rune >= 0x0D80 && rune <= 0x0DFF) || // Sinhala
      (rune >= 0x0E00 && rune <= 0x0E7F) || // Thai
      (rune >= 0x0E80 && rune <= 0x0EFF) || // Lao
      (rune >= 0x1000 && rune <= 0x109F) || // Myanmar
      (rune >= 0x10A0 && rune <= 0x10FF) || // Georgian
      (rune >= 0x1100 && rune <= 0x11FF) || // Hangul Jamo
      (rune >= 0x1780 && rune <= 0x17FF) || // Khmer
      (rune >= 0x3040 && rune <= 0x30FF) || // Hiragana + Katakana
      (rune >= 0x3400 && rune <= 0x4DBF) || // CJK Extension A
      (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK Unified Ideographs
      (rune >= 0xAC00 && rune <= 0xD7AF); // Hangul Syllables
}
