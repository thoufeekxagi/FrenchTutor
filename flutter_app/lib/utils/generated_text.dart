String normalizeGeneratedText(String value) => value
    .replaceAll('—', ',')
    .replaceAll('–', ',')
    .replaceAll(RegExp(r'\s+,\s+'), ', ')
    .replaceAll(RegExp(r',{2,}'), ',')
    .trim();
