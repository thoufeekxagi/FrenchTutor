/// Diacritic-insensitive, lowercased fold — Dart has no built-in equivalent to Swift's
/// `String.folding(options: .diacriticInsensitive, locale:)`, so this is a manual accent
/// map covering French. Used by the gate systems (vocab/grammar/listening) to match spoken
/// intent keywords and target words regardless of accents.
const Map<String, String> frenchDiacriticMap = {
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'à': 'a', 'â': 'a', 'ä': 'a',
  'ç': 'c',
  'î': 'i', 'ï': 'i',
  'ô': 'o', 'ö': 'o',
  'û': 'u', 'ù': 'u', 'ü': 'u',
  'œ': 'oe', 'æ': 'ae',
  'ñ': 'n',
};

String foldFrench(String text) {
  var result = text.toLowerCase().trim();
  frenchDiacriticMap.forEach((accented, plain) {
    result = result.replaceAll(accented, plain);
  });
  return result;
}
