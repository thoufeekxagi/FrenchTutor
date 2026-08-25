/// Deterministic word alignment for the authored Guided Speaking catalog.
///
/// Guided Speaking uses an explicit alignment for every source word. There is
/// deliberately no positional or whole-sentence fallback: a phrase that is
/// not mapped is invalid lesson data and must be fixed before it reaches the
/// learner.
class SpeakingTranslationAlignment {
  const SpeakingTranslationAlignment._();

  static List<List<int>> forPhrase(String source, String translation) {
    final sourceWords = _words(source);
    final translationWords = _words(translation);
    final alignment = List.generate(
      sourceWords.length,
      (_) => <int>[],
      growable: false,
    );
    if (sourceWords.isEmpty || translationWords.isEmpty) return alignment;

    final usedSource = <int>{};
    final orderedRules = [
      ..._rules,
    ]..sort((left, right) => right.source.length.compareTo(left.source.length));
    for (final rule in orderedRules) {
      for (
        var start = 0;
        start <= sourceWords.length - rule.source.length;
        start++
      ) {
        final sourceIndexes = [
          for (var offset = 0; offset < rule.source.length; offset++)
            start + offset,
        ];
        if (sourceIndexes.any(usedSource.contains)) continue;
        var matches = true;
        for (var offset = 0; offset < rule.source.length; offset++) {
          if (sourceWords[start + offset] != _fold(rule.source[offset])) {
            matches = false;
            break;
          }
        }
        if (!matches) continue;

        final matchedTargets = <List<int>>[];
        for (var offset = 0; offset < rule.translation.length; offset++) {
          final target = _findPhrase(
            translationWords,
            rule.translation[offset],
          );
          matchedTargets.add(target);
          if (target.isNotEmpty) {
            alignment[start + offset].addAll(target);
          }
        }
        final lastTarget = matchedTargets.lastWhere(
          (target) => target.isNotEmpty,
          orElse: () => const [],
        );
        for (final sourceIndex in sourceIndexes) {
          if (alignment[sourceIndex].isEmpty && lastTarget.isNotEmpty) {
            alignment[sourceIndex].addAll(lastTarget);
          }
        }
        usedSource.addAll(sourceIndexes);
      }
    }

    for (var sourceIndex = 0; sourceIndex < sourceWords.length; sourceIndex++) {
      if (usedSource.contains(sourceIndex)) continue;
      // Punctuation is kept in the list so its indexes stay aligned with the
      // rendered text, but it is not a translatable word and should never be
      // forced onto an English word.
      if (sourceWords[sourceIndex].isEmpty) continue;
      final target = _singleWordMeaningFor(sourceWords[sourceIndex]);
      final matches = target == null
          ? _findPhrase(translationWords, sourceWords[sourceIndex])
          : _findPhrase(translationWords, target);
      if (matches.isEmpty) {
        throw StateError(
          'No Guided Speaking translation alignment for '
          '"$source" → "$translation" at source word '
          '"${sourceWords[sourceIndex]}".',
        );
      }
      alignment[sourceIndex].addAll(matches);
    }
    final result = [for (final indexes in alignment) indexes.toSet().toList()];
    return result;
  }

  static List<String> _words(String text) => text
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map(_fold)
      .toList(growable: false);

  static String _fold(String value) => value
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'''[.,!?;:«»'()…"]'''), '')
      .replaceAll('-', ' ')
      .trim();

  static List<int> _findPhrase(List<String> words, String phrase) {
    final target = _words(phrase);
    if (target.isEmpty) return const [];
    for (var start = 0; start <= words.length - target.length; start++) {
      var matches = true;
      for (var offset = 0; offset < target.length; offset++) {
        if (words[start + offset] != target[offset]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return [
          for (var offset = 0; offset < target.length; offset++) start + offset,
        ];
      }
    }
    return const [];
  }

  static String? _singleWordMeaningFor(String sourceWord) {
    final direct = _singleWordMeanings[sourceWord];
    if (direct != null) return direct;
    for (final entry in _singleWordMeanings.entries) {
      if (_fold(entry.key) == sourceWord) return entry.value;
    }
    return null;
  }

  static const _singleWordMeanings = <String, String>{
    'bonjour': 'hello',
    'je': 'i',
    "j'ai": 'i have',
    "j'aime": 'i like',
    "j'habite": 'i live',
    "m'appelle": 'name',
    'comment': 'what',
    'appelez-vous': 'name',
    'viens': 'am',
    'ça': 'that',
    'et': 'and',
    'habitez': 'live',
    'pardon': 'sorry',
    'excusez-moi': 'excuse me',
    'merci': 'thank you',
    'beaucoup': 'very much',
    'bien': 'well',
    'bientôt': 'soon',
    'lentement': 'slowly',
    'aide': 'help',
    'pouvez-vous': 'can you',
    'pouvez': 'can',
    'peux': 'can i',
    'répéter': 'repeat',
    'conseillez': 'recommend',
    'plus': 'more',
    "s'il": 'please',
    'vous': 'you',
    'ou': 'or',
    'sur': 'for',
    'place': 'here',
    'à': 'at',
    'emporter': 'go',
    'la': 'the',
    'le': 'the',
    'les': 'the',
    'du': 'of the',
    'un': 'a',
    'une': 'a',
    'mon': 'my',
    'ma': 'my',
    'votre': 'your',
    'ce': 'this',
    'cet': 'this',
    'que': 'do',
    'est': 'is',
    "c'est": 'is',
    'part': 'leave',
    'va': 'go',
    'au': 'to the',
    'tout': 'straight',
    'allez': 'go',
    'tournez': 'turn',
    'où': 'where',
    'ici': 'here',
    'pour': 'for',
    'avec': 'with',
    'besoin': 'need',
    'ne': 'not',
    'pas': 'not',
    'y': 'there',
    'a': 'a',
    'oui': 'yes',
    'non': 'no',
    'bonne': 'good',
    'journée': 'day',
    'demain': 'tomorrow',
    'possible': 'possible',
    'trois': 'three',
    'quatre': 'four',
    'cinq': 'five',
    'dix': 'ten',
    'neuf': 'nine',
    'trente': 'thirty',
    'deux': 'two',
    'ans': 'years old',
    'aussi': 'also',
    'un peu': 'a little',
    'parle': 'speak',
    'parlez': 'speak',
    'aimez': 'like',
    'aime': 'like',
    'fait': 'is',
    'fait-il': 'is',
    'aujourd’hui': 'today',
    'ouvrez': 'open',
    'ouvrons': 'open',
    'fermez': 'close',
    'cherche': 'looking',
    'prendre': 'take',
    'rendez-vous': 'appointment',
    'd’accord': 'okay',
    'coule': 'running',
    'suis': 'am',
    'voisin': 'neighbour',
    'correct': 'correct',
    'comprendre': 'understanding',
    'taille': 'size',
    'grande': 'larger',
    'trop': 'too',
    'cette': 'this',
    'me': 'me',
    'plaît': 'like',
    'davantage': 'more',
    'préfère': 'prefer',
    'celui-ci': 'this one',
    'moins': 'less',
    'cher': 'expensive',
    'retourner': 'return',
    'article': 'item',
    'fonctionne': 'work',
    'reçu': 'receipt',
    'vais': 'will',
    'payer': 'pay',
    'acceptez': 'accept',
    'espèces': 'cash',
    'matin': 'morning',
    'travaillé': 'worked',
    'midi': 'noon',
    'déjeuné': 'had lunch',
    'ami': 'friend',
    'soir': 'evening',
    'reposer': 'rest',
    'tu': 'you',
    'veux': 'want',
    'on': 'we',
    'peut': 'can',
    'se': 'meet',
    'retrouve': 'meet',
    'retrouver': 'meet',
    'samedi': 'saturday',
    'te': 'you',
    'convient': 'works',
    'libre': 'free',
    'après': 'after',
    'parfait': 'perfect',
    'devant': 'in front of',
    'venir': 'come',
    'reporter': 'postpone',
    'dimanche': 'sunday',
    'mieux': 'better',
    'ambiance': 'atmosphere',
    'calme': 'calm',
    'toi': 'you',
    'préfères': 'prefer',
    'café': 'coffee',
    'lait': 'milk',
    'plat': 'dish',
    'jour': 'day',
    'addition': 'bill',
    'carte': 'card',
    'menu': 'menu',
    'combien': 'how much',
    'coûte': 'cost',
    'euros': 'euros',
    'gare': 'station',
    'droit': 'straight',
    'gauche': 'left',
    'droite': 'right',
    'billet': 'ticket',
    'simple': 'one way',
    'heure': 'time',
    'heures': 'time',
    'train': 'train',
    'quai': 'platform',
    'bus': 'bus',
    'arrêt': 'stop',
    'frère': 'brother',
    'sœur': 'sister',
    'famille': 'family',
    'âge': 'age',
    'numéro': 'number',
    'français': 'french',
    'anglais': 'english',
    'musique': 'music',
    'cinéma': 'movies',
    'temps': 'weather',
    'beau': 'nice',
    'froid': 'cold',
    'pharmacie': 'pharmacy',
    'médicaments': 'medicine',
    'problème': 'problem',
    'eau': 'water',
    'question': 'question',
    'désolé': 'sorry',
    'retard': 'late',
    'chemise': 'shirt',
    'bleue': 'blue',
    'modèle': 'model',
    'petit': 'small',
    'couleur': 'color',
    'restaurant': 'restaurant',
    'alex': 'alex',
    'sam': 'sam',
    'toronto': 'toronto',
    'montréal': 'montreal',
    'ottawa': 'ottawa',
    'lyon': 'lyon',
  };

  static const _rules = <_AlignmentRule>[
    _AlignmentRule(['je', "m'appelle"], ['my', 'name is']),
    _AlignmentRule(
      ["qu'est-ce", 'que', 'vous', 'conseillez'],
      ['what', 'do', 'you', 'recommend'],
    ),
    _AlignmentRule(
      ['comment', 'vous', 'appelez-vous'],
      ['what', 'your', 'name'],
    ),
    _AlignmentRule(['je', 'viens', 'de'], ['i', 'am', 'from']),
    _AlignmentRule(
      ["j'ai", 'trente', 'ans', 'aussi'],
      ['i am', 'thirty', 'years old', 'too'],
    ),
    _AlignmentRule(
      ['je', 'suis', 'disponible', 'mardi', 'matin'],
      ['i', 'am', 'available', 'tuesday', 'morning'],
    ),
    _AlignmentRule(
      ['est-ce', 'que', 'dix', 'heures', 'vous', 'convient'],
      ['does', 'ten', "o'clock", 'work', 'for', 'you'],
    ),
    _AlignmentRule(
      ['je', 'me', 'lève', 'à', 'sept', 'heures'],
      ['i', 'get up', 'get up', 'at', 'seven', "o'clock"],
    ),
    _AlignmentRule(
      ['je', 'travaille', 'le', 'matin'],
      ['i', 'work', 'in the', 'morning'],
    ),
    _AlignmentRule(
      ['le', 'soir', 'je', 'prépare', 'le', 'dîner'],
      ['in the', 'evening', 'i', 'prepare', 'the', 'dinner'],
    ),
    _AlignmentRule(
      ['le', 'week-end', 'je', 'me', 'repose'],
      ['on', 'the weekend', 'i', 'rest', 'rest'],
    ),
    _AlignmentRule(
      ['je', 'préfère', 'cette', 'option'],
      ['i', 'prefer', 'this', 'option'],
    ),
    _AlignmentRule(
      ["c'est", 'plus', 'simple', 'pour', 'moi'],
      ['it is', 'simpler', 'for', 'for', 'me'],
    ),
    _AlignmentRule(
      ['je', 'choisis', 'le', 'billet', 'aller-retour'],
      ['i', 'choose', 'the', 'return', 'ticket'],
    ),
    _AlignmentRule(
      ['merci', 'pour', 'votre', 'conseil'],
      ['thank you', 'for', 'your', 'advice'],
    ),
    _AlignmentRule(
      ['demain', 'je', 'vais', 'travailler'],
      ['tomorrow', 'i', 'am going to', 'work'],
    ),
    _AlignmentRule(
      ['je', 'voudrais', 'visiter', 'le', 'musée'],
      ['i', 'would like', 'to visit', 'the', 'museum'],
    ),
    _AlignmentRule(
      ['si', "j'ai", 'le', 'temps', 'je', 'prendrai', 'un', 'café'],
      ['if', 'i', 'have', 'time', 'i', 'will', 'have a', 'coffee'],
    ),
    _AlignmentRule(
      ['on', 'peut', 'se', 'retrouver', 'à', 'midi'],
      ['we', 'can', 'meet', 'meet', 'at', 'noon'],
    ),
    _AlignmentRule(
      ["j'ai", 'un', 'petit', 'problème'],
      ['i have', 'a', 'small', 'problem'],
    ),
    _AlignmentRule(
      ['la', 'porte', 'ne', 'ferme', 'pas'],
      ['the', 'door', 'does not', 'close', 'close'],
    ),
    _AlignmentRule(
      ['pouvez-vous', "m'aider", "s'il", 'vous', 'plaît'],
      ['can you', 'help me', 'please', 'please', 'please'],
    ),
    _AlignmentRule(
      ['merci', 'beaucoup', 'pour', 'votre', 'aide'],
      ['thank you', 'very much', 'for', 'your', 'help'],
    ),
    _AlignmentRule(
      ['à', 'mon', 'avis', "c'est", 'une', 'bonne', 'idée'],
      ['in', 'my', 'opinion', 'it is', 'a', 'good', 'idea'],
    ),
    _AlignmentRule(
      ['parce', "qu'elle", 'est', 'simple', 'et', 'pratique'],
      ['because', 'it is', 'simple', 'and', 'practical', 'practical'],
    ),
    _AlignmentRule(
      ['et', 'vous', "qu'en", 'pensez-vous'],
      ['and', 'you', 'what', 'do you think'],
    ),
    _AlignmentRule(
      ['excusez-moi', 'où', 'est', 'la', 'gare'],
      ['excuse me', 'where', 'is', 'the', 'station'],
    ),
    _AlignmentRule(
      ['allez', 'tout', 'droit', 'puis', 'tournez', 'à', 'gauche'],
      ['go', 'straight', 'straight', 'then', 'turn', 'turn', 'left'],
    ),
    _AlignmentRule(["c'est", 'loin', "d'ici"], ['is it', 'far', 'from here']),
    _AlignmentRule(
      ['merci', 'je', 'vais', 'trouver'],
      ['thank you', 'i', 'will', 'find it'],
    ),
    _AlignmentRule(
      ["j'aime", 'le', 'thé', 'mais', 'je', 'préfère', 'le', 'café'],
      ['i like', 'tea', 'tea', 'but', 'i', 'prefer', 'coffee', 'coffee'],
    ),
    _AlignmentRule(
      ['je', 'préfère', 'une', 'table', 'près', 'de', 'la', 'fenêtre'],
      ['i', 'prefer', 'a', 'table', 'near', 'the', 'the', 'window'],
    ),
    _AlignmentRule(
      ["qu'est-ce", 'que', 'vous', 'aimez'],
      ['what', 'do', 'you', 'like'],
    ),
    _AlignmentRule(
      ['nous', 'avons', 'les', 'mêmes', 'goûts'],
      ['we', 'have', 'the', 'same', 'tastes'],
    ),
    _AlignmentRule(
      ['pourriez-vous', "m'aider", "s'il", 'vous', 'plaît'],
      ['could you', 'help me', 'please', 'please', 'please'],
    ),
    _AlignmentRule(
      ["j'aurais", 'besoin', "d'une", 'information'],
      ['i would', 'need', 'some', 'information'],
    ),
    _AlignmentRule(
      ['est-ce', 'que', 'vous', 'pouvez', 'vérifier'],
      ['can', 'you', 'can', 'check', 'check'],
    ),
    _AlignmentRule(
      ['merci', 'pour', 'votre', 'temps'],
      ['thank you', 'for', 'your', 'time'],
    ),
    _AlignmentRule(
      ['hier', 'je', 'suis', 'allé', 'au', 'marché'],
      ['yesterday', 'i', 'went', 'to', 'the', 'market'],
    ),
    _AlignmentRule(
      ["j'ai", 'acheté', 'des', 'légumes', 'frais'],
      ['i', 'bought', 'some', 'vegetables', 'vegetables'],
    ),
    _AlignmentRule(
      ['ensuite', 'je', 'suis', 'rentré', 'chez', 'moi'],
      ['then', 'i', 'went', 'home', 'home', 'home'],
    ),
    _AlignmentRule(
      ["c'était", 'une', 'matinée', 'agréable'],
      ['it was', 'a', 'pleasant', 'morning'],
    ),
    _AlignmentRule(
      ['les', 'amis', 'arrivent', 'à', 'huit', 'heures'],
      ['the', 'friends', 'arrive', 'at', 'eight', "o'clock"],
    ),
    _AlignmentRule(
      ['nous', 'allons', 'écouter', 'la', 'liaison'],
      ['we', 'are going to', 'listen to', 'the', 'liaison'],
    ),
    _AlignmentRule(
      ['je', 'parle', 'lentement', 'et', 'clairement'],
      ['i', 'speak', 'slowly', 'and', 'clearly'],
    ),
    _AlignmentRule(
      ['je', 'recommence', 'avec', 'un', 'rythme', 'naturel'],
      ['i', 'start again', 'with', 'a', 'natural', 'rhythm'],
    ),
    _AlignmentRule(
      ['je', 'voudrais', 'sortir', 'mais', 'il', 'pleut'],
      ['i', 'would like', 'to go out', 'but', 'it is', 'raining'],
    ),
    _AlignmentRule(
      [
        'je',
        'reste',
        'à',
        'la',
        'maison',
        'parce',
        'que',
        'je',
        'suis',
        'fatigué',
      ],
      [
        'i',
        'stay',
        'at',
        'the',
        'home',
        'because',
        'because',
        'i',
        'am',
        'tired',
      ],
    ),
    _AlignmentRule(
      ['donc', 'je', 'vais', 'lire', 'un', 'livre'],
      ['so', 'i', 'am going to', 'read', 'a', 'book'],
    ),
    _AlignmentRule(
      ['après', 'cela', 'je', 'préparerai', 'le', 'dîner'],
      ['after', 'that', 'i', 'will', 'prepare', 'dinner'],
    ),
    _AlignmentRule(['bonjour', 'ça', 'va'], ['hello', 'how are you']),
    _AlignmentRule(['ça', 'va', 'bien'], ['i am', 'well', '']),
    _AlignmentRule(['à', 'bientôt'], ['see you', 'soon']),
    _AlignmentRule(
      ['merci', 'à', 'mardi'],
      ['thank you', 'see you', 'tuesday'],
    ),
    _AlignmentRule(
      ['merci', 'maintenant', 'je', 'comprends'],
      ['thank you', 'now', 'i', 'understand'],
    ),
    _AlignmentRule(
      ['enchanté', 'de', 'vous', 'rencontrer'],
      ['nice', 'to', 'meet', 'you'],
    ),
    _AlignmentRule(["j'habite", 'à'], ['i live', 'in']),
    _AlignmentRule(
      ['et', 'vous', 'vous', 'habitez', 'où'],
      [
        'and',
        'you',
        'where do you live',
        'where do you live',
        'where do you live',
      ],
    ),
    _AlignmentRule(
      ["j'habite", 'près', 'du', 'centre'],
      ['i live', 'near', 'downtown', 'downtown'],
    ),
    _AlignmentRule(['pouvez-vous', 'répéter'], ['can you', 'repeat']),
    _AlignmentRule(
      ['pouvez-vous', 'parler', 'plus', 'lentement'],
      ['can you', 'speak', 'more', 'slowly'],
    ),
    _AlignmentRule(
      ['je', "n'ai", 'pas', 'compris', 'la', 'dernière', 'phrase'],
      ['i', 'did not', 'did not', 'understand', 'the', 'last', 'sentence'],
    ),
    _AlignmentRule(['plus', 'lentement'], ['more', 'slowly']),
    _AlignmentRule(['pouvez-vous', "m'aider"], ['can you', 'help me']),
    _AlignmentRule(["s'il", 'vous', 'plaît'], ['please', 'please', 'please']),
    _AlignmentRule(['je', 'voudrais'], ['i', 'would like']),
    _AlignmentRule(['avec', 'du', 'lait'], ['with', 'milk', 'milk']),
    _AlignmentRule(
      ["qu'est-ce", 'que', 'vous', 'recommandez'],
      ['what', 'do', 'you', 'recommend'],
    ),
    _AlignmentRule(["l'addition"], ['the bill']),
    _AlignmentRule(
      ['sur', 'place', 'ou', 'à', 'emporter'],
      ['for here', 'for here', 'or', 'to go', 'to go'],
    ),
    _AlignmentRule(['à', 'emporter'], ['to', 'go']),
    _AlignmentRule(['la', 'carte'], ['the', 'menu']),
    _AlignmentRule(['je', 'prends', 'ça'], ['i will have', 'have', 'that']),
    _AlignmentRule(['combien', 'ça', 'coûte'], ['how much', 'does', 'cost']),
    _AlignmentRule(["d'accord"], ['okay']),
    _AlignmentRule(
      ['je', 'peux', 'payer', 'par', 'carte'],
      ['can i', 'pay', 'pay', 'by', 'card'],
    ),
    _AlignmentRule(['bonne', 'journée'], ['good', 'day']),
    _AlignmentRule(
      ['où', 'est', 'la', 'gare'],
      ['where', 'is', 'the', 'station'],
    ),
    _AlignmentRule(["c'est", 'près', "d'ici"], ['is it', 'near', 'here']),
    _AlignmentRule(
      ['merci', 'pour', 'votre', 'aide'],
      ['thank you', 'for', 'your', 'help'],
    ),
    _AlignmentRule(['allez', 'tout', 'droit'], ['go', 'straight', '']),
    _AlignmentRule(['tournez', 'à', 'gauche'], ['turn', 'left', 'left']),
    _AlignmentRule(['tournez', 'à', 'droite'], ['turn', 'right', 'right']),
    _AlignmentRule(['un', 'billet', 'pour'], ['one', 'ticket', 'to']),
    _AlignmentRule(['aller', 'simple'], ['one way', 'one way']),
    _AlignmentRule(
      ['à', 'quelle', 'heure'],
      ['what time', 'what time', 'what time'],
    ),
    _AlignmentRule(
      ['quel', 'est', 'le', 'quai'],
      ['which', 'is', 'the', 'platform'],
    ),
    _AlignmentRule(['le', 'quai', 'numéro'], ['platform', 'number', 'number']),
    _AlignmentRule(
      ['le', 'train', 'est', 'à', "l'heure"],
      ['the', 'train', 'is', 'on time'],
    ),
    _AlignmentRule(
      ['ce', 'bus', 'va', 'au', 'centre-ville'],
      ['does this', 'bus', 'go', 'downtown', 'downtown'],
    ),
    _AlignmentRule(['où', 'est', "l'arrêt"], ['where', 'is', 'the stop']),
    _AlignmentRule(['je', 'descends', 'ici'], ['i', 'get off', 'here']),
    _AlignmentRule(["j'ai", 'un', 'frère'], ['i have', 'a', 'brother']),
    _AlignmentRule(
      ['ma', 'sœur', 'habite', 'à'],
      ['my', 'sister', 'lives', 'in'],
    ),
    _AlignmentRule(
      ['nous', 'sommes', 'une', 'petite', 'famille'],
      ['we are', 'we are', 'a', 'small', 'family'],
    ),
    _AlignmentRule(["j'ai", 'trente', 'ans'], ['i am', 'thirty', 'years old']),
    _AlignmentRule(
      ['quel', 'âge', 'avez-vous'],
      ['how old', 'how old', 'are you'],
    ),
    _AlignmentRule(
      ['quel', 'est', 'votre', 'numéro'],
      ['what', 'is', 'your', 'number'],
    ),
    _AlignmentRule(['mon', 'numéro', 'est'], ['my', 'number', 'is']),
    _AlignmentRule(
      ['mon', 'numéro', 'est', 'le', 'cinq', 'quatre', 'deux'],
      ['my', 'number', 'is', 'five', 'four', 'two', 'two'],
    ),
    _AlignmentRule(
      ['je', 'peux', 'vous', 'appeler'],
      ['can i', 'call', 'you', 'call'],
    ),
    _AlignmentRule(
      ['vous', 'parlez', 'français'],
      ['do you speak', 'speak', 'french'],
    ),
    _AlignmentRule(
      ['je', 'parle', 'un', 'peu', 'français'],
      ['i speak', 'speak', 'a little', 'a little', 'french'],
    ),
    _AlignmentRule(
      ['je', 'parle', 'aussi', 'anglais'],
      ['i speak', 'speak', 'also', 'english'],
    ),
    _AlignmentRule(
      ["qu'est-ce", 'que', 'vous', 'aimez'],
      ['what', 'do', 'you', 'like'],
    ),
    _AlignmentRule(["j'aime", 'la', 'musique'], ['i like', 'the', 'music']),
    _AlignmentRule(
      ["j'aime", 'aussi', 'le', 'cinéma'],
      ['i', 'also', 'like', 'movies'],
    ),
    _AlignmentRule(['quel', 'temps', 'fait-il'], ['what', 'weather', 'is']),
    _AlignmentRule(
      ['il', 'fait', 'beau', "aujourd'hui"],
      ['the weather is', 'the weather is', 'nice', 'today'],
    ),
    _AlignmentRule(
      ['il', 'fait', 'un', 'peu', 'froid'],
      ['it is', 'it is', 'a little', 'a little', 'cold'],
    ),
    _AlignmentRule(
      ['vous', 'avez', "l'heure"],
      ['do you have', 'have', 'the time'],
    ),
    _AlignmentRule(
      ['il', 'est', 'trois', 'heures'],
      ['it is', 'is', 'three', "o'clock"],
    ),
    _AlignmentRule(
      ['vous', 'ouvrez', 'à', 'quelle', 'heure'],
      ['what time', 'do you open', 'do you open', 'what time', 'what time'],
    ),
    _AlignmentRule(
      ['nous', 'ouvrons', 'à', 'neuf', 'heures'],
      ['we open', 'we open', 'at', 'nine', "o'clock"],
    ),
    _AlignmentRule(
      ['vous', 'fermez', 'à', 'quelle', 'heure'],
      ['what time', 'do you close', 'do you close', 'what time', 'what time'],
    ),
    _AlignmentRule(
      ['bonjour', 'je', 'cherche', 'une', 'pharmacie'],
      ['hello', 'i am looking', 'looking', 'a', 'pharmacy'],
    ),
    _AlignmentRule(
      ["j'ai", 'besoin', 'de', 'médicaments'],
      ['i need', 'need', 'of', 'medicine'],
    ),
    _AlignmentRule(
      ['je', 'voudrais', 'prendre', 'rendez-vous'],
      ['i', 'would like', 'to make', 'an appointment'],
    ),
    _AlignmentRule(
      ['demain', 'matin', "c'est", 'possible'],
      ['tomorrow', 'morning', 'is', 'possible'],
    ),
    _AlignmentRule(['à', 'dix', 'heures'], ['at', 'ten', "o'clock"]),
    _AlignmentRule(
      ['il', 'y', 'a', 'un', 'problème'],
      ['there is', 'there is', 'there is', 'a', 'problem'],
    ),
    _AlignmentRule(
      ["l'eau", 'ne', 'coule', 'pas'],
      ['the water', 'is not', 'running', 'running'],
    ),
    _AlignmentRule(
      ['bonjour', 'je', 'suis', 'votre', 'voisin'],
      ['hello', 'i am', 'am', 'your', 'neighbour'],
    ),
    _AlignmentRule(
      ['vous', 'avez', 'besoin', "d'aide"],
      ['do you need', 'need', 'help'],
    ),
    _AlignmentRule(
      ['excusez-moi', "j'ai", 'une', 'question'],
      ['excuse me', 'i have', 'a', 'question'],
    ),
    _AlignmentRule(
      ['vous', 'pouvez', "m'aider"],
      ['can you', 'can you', 'help me'],
    ),
    _AlignmentRule(["c'est", 'bien', 'ici'], ['is', 'correct', 'here']),
    _AlignmentRule(['oui', "c'est", 'correct'], ['yes', 'that is', 'correct']),
    _AlignmentRule(['je', 'suis', 'désolé'], ['i', 'am', 'sorry']),
    _AlignmentRule(['je', 'suis', 'en', 'retard'], ['i', 'am', 'late', 'late']),
    _AlignmentRule(
      ['merci', 'de', 'comprendre'],
      ['thank you', 'for', 'understanding'],
    ),
    _AlignmentRule(['à', 'demain'], ['see you', 'tomorrow']),
    _AlignmentRule(['bonne', 'soirée'], ['good', 'evening']),
    _AlignmentRule(
      ['je', 'cherche', 'une', 'chemise', 'bleue'],
      ['i am looking', 'looking', 'a', 'shirt', 'blue'],
    ),
    _AlignmentRule(
      ['vous', 'avez', 'ce', 'modèle'],
      ['do you have', 'have', 'this', 'model'],
    ),
    _AlignmentRule(['je', 'peux', "l'essayer"], ['can i', 'try it on']),
    _AlignmentRule(
      ['vous', 'avez', 'une', 'taille', 'plus', 'grande'],
      ['do you have', 'have', 'a', 'size', 'larger', 'larger'],
    ),
    _AlignmentRule(
      ["c'est", 'un', 'peu', 'trop', 'petit'],
      ['it is', 'a little', 'a little', 'too', 'small'],
    ),
    _AlignmentRule(
      ['cette', 'taille', 'me', 'va', 'bien'],
      ['this', 'size', 'fits me', 'fits me', 'well'],
    ),
    _AlignmentRule(['je', 'préfère', 'celui-ci'], ['i', 'prefer', 'this one']),
    _AlignmentRule(
      ['il', 'est', 'moins', 'cher'],
      ['it', 'is', 'less', 'expensive'],
    ),
    _AlignmentRule(
      ['la', 'couleur', 'me', 'plaît', 'davantage'],
      ['the', 'color', 'i like', 'like', 'more'],
    ),
    _AlignmentRule(
      ['je', 'voudrais', 'retourner', 'cet', 'article'],
      ['i', 'would like', 'to return', 'this', 'item'],
    ),
    _AlignmentRule(
      ['il', 'ne', 'fonctionne', 'pas'],
      ['it', 'does not', 'work', 'work'],
    ),
    _AlignmentRule(["j'ai", 'le', 'reçu'], ['i have', 'the', 'receipt']),
    _AlignmentRule(
      ['je', 'vais', 'payer', 'par', 'carte'],
      ['i will', 'pay', 'pay', 'by', 'card'],
    ),
    _AlignmentRule(
      ['vous', 'acceptez', 'les', 'espèces'],
      ['do you accept', 'accept', 'cash', 'cash'],
    ),
    _AlignmentRule(
      ['je', 'peux', 'avoir', 'le', 'reçu'],
      ['can i', 'have', 'the', 'receipt', 'receipt'],
    ),
    _AlignmentRule(
      ['ce', 'matin', "j'ai", 'travaillé'],
      ['this', 'morning', 'i', 'worked'],
    ),
    _AlignmentRule(
      ['à', 'midi', "j'ai", 'déjeuné', 'avec', 'un', 'ami'],
      ['at', 'noon', 'i', 'had lunch', 'with', 'a', 'friend'],
    ),
    _AlignmentRule(
      ['ce', 'soir', 'je', 'vais', 'me', 'reposer'],
      ['this', 'evening', 'i', 'am going to', 'to rest', 'rest'],
    ),
    _AlignmentRule(
      ['tu', 'veux', 'prendre', 'un', 'café'],
      ['do you', 'want', 'to have', 'a', 'coffee'],
    ),
    _AlignmentRule(
      ['on', 'peut', 'se', 'retrouver', 'samedi'],
      ['we can', 'meet', 'meet', 'meet', 'on saturday'],
    ),
    _AlignmentRule(['ça', 'te', 'convient'], ['does', 'that', 'work for you']),
    _AlignmentRule(
      ['je', 'suis', 'libre', 'après', 'trois', 'heures'],
      ['i am', 'am', 'free', 'after', 'three', 'three'],
    ),
    _AlignmentRule(
      ['quatre', 'heures', "c'est", 'parfait'],
      ['four', "o'clock", 'is', 'perfect'],
    ),
    _AlignmentRule(
      ['on', 'se', 'retrouve', 'devant', 'le', 'café'],
      ['we', 'will meet', 'meet', 'in front of', 'the', 'cafe'],
    ),
    _AlignmentRule(
      ['désolé', 'je', 'ne', 'peux', 'pas', 'venir'],
      ['sorry', 'i', 'cannot', 'cannot', 'cannot', 'come'],
    ),
    _AlignmentRule(
      ['est-ce', "qu'on", 'peut', 'reporter'],
      ['can', 'we', 'postpone', 'postpone'],
    ),
    _AlignmentRule(
      ['dimanche', 'me', 'convient', 'mieux'],
      ['sunday', 'works for me', 'works', 'better'],
    ),
    _AlignmentRule(
      ['je', 'préfère', 'ce', 'restaurant'],
      ['i', 'prefer', 'this', 'restaurant'],
    ),
    _AlignmentRule(
      ["l'ambiance", 'est', 'plus', 'calme'],
      ['the atmosphere', 'is', 'calmer', 'calmer'],
    ),
    _AlignmentRule(
      ['et', 'toi', "qu'est-ce", 'que', 'tu', 'préfères'],
      ['and', 'you', 'what', 'do', 'you', 'prefer'],
    ),
  ];
}

class _AlignmentRule {
  const _AlignmentRule(this.source, this.translation);

  final List<String> source;
  final List<String> translation;
}
