import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../models/grammar_course.dart';
import '../../models/grammar_course_session_result.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/tts_play_button.dart';
import '../../widgets/web/web_constrained_view.dart';

/// Complete is a compact grammar workshop, not another sentence-card deck.
/// The five steps deliberately move from explanation to controlled production.
class GrammarCompleteLessonScreen extends ConsumerStatefulWidget {
  const GrammarCompleteLessonScreen({
    super.key,
    required this.session,
    this.warmupSessions = const [],
  });

  final GrammarCourseSession session;
  final List<GrammarCourseSession> warmupSessions;

  @override
  ConsumerState<GrammarCompleteLessonScreen> createState() =>
      _GrammarCompleteLessonScreenState();
}

class _GrammarCompleteLessonScreenState
    extends ConsumerState<GrammarCompleteLessonScreen> {
  final List<String> _builtSentence = [];
  List<String> _wordBank = [];
  List<String> _choices = [];
  int _index = 0;
  String? _selectedChoice;
  bool? _correct;
  int _correctCount = 0;
  int _attemptedCount = 0;

  GrammarCourseStep get _step => widget.session.steps[_index];
  bool get _isLastStep => _index == widget.session.steps.length - 1;

  static const _stageLabels = ['Learn', 'Notice', 'Transform', 'Repair', 'Use'];
  static const _stageTitles = [
    'Learn the pattern',
    'Notice the subject',
    'Transform the sentence',
    'Repair the sentence',
    'Use the pattern',
  ];
  static const _stageSubtitles = [
    'See the small rule before you practise it.',
    'Find the subject before you choose the form.',
    'Keep the meaning and apply the pattern.',
    'Fix one agreement error without changing the idea.',
    'Build one final line about the same situation.',
  ];

  @override
  void initState() {
    super.initState();
    _resetStep();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_prewarmAudio());
    });
  }

  void _resetStep() {
    final seed = '${widget.session.id}:$_index'.hashCode;
    _wordBank = [..._step.tokens]..shuffle(math.Random(seed));
    _choices = _choicesForStep();
    _builtSentence.clear();
    _selectedChoice = null;
    _correct = null;
  }

  Future<void> _prewarmAudio() async {
    final items = <SpeechItem>[];
    for (final session in [widget.session, ...widget.warmupSessions]) {
      for (var index = 0; index < session.steps.length; index++) {
        final step = session.steps[index];
        final prefix = 'grammar-session:${session.id}:step:$index';
        items.add(
          SpeechItem(
            text: step.target,
            language: 'fr-FR',
            contentItemId: '$prefix:target',
          ),
        );
      }
    }
    try {
      await LessonSpeechService.shared.prewarmNarration(items);
    } catch (error) {
      debugPrint('Complete Grammar audio prewarm skipped: $error');
    }
  }

  List<String> _choicesForStep() {
    final provided = _step.choices
        .map((choice) => choice.trim())
        .where((choice) => choice.isNotEmpty)
        .toList(growable: false);
    if (provided.length >= 2) return provided;
    if (_step.tokens.length < 2) return [_step.target];

    final verbIndex = _verbIndex(_step.tokens);
    final verb = _step.tokens[verbIndex];
    final variants = <String>[
      _step.target,
      _replaceFirst(_step.target, verb, _wrongVerb(verb, 1)),
      _replaceFirst(_step.target, verb, _wrongVerb(verb, 2)),
    ];
    final unique = <String>[];
    for (final variant in variants) {
      if (variant.trim().isNotEmpty && !unique.contains(variant)) {
        unique.add(variant);
      }
    }
    return unique;
  }

  int _verbIndex(List<String> tokens) {
    const nonVerbs = {
      'je',
      'tu',
      'il',
      'elle',
      'on',
      'nous',
      'vous',
      'ils',
      'elles',
      'me',
      'm’,',
      'm\'',
      'te',
      'se',
    };
    for (var index = 1; index < tokens.length; index++) {
      final clean = tokens[index].toLowerCase().replaceAll(
        RegExp(r'[,.!?;:]'),
        '',
      );
      if (!nonVerbs.contains(clean)) return index;
    }
    return math.min(1, tokens.length - 1);
  }

  String _wrongVerb(String verb, int variant) {
    final clean = verb.replaceAll(RegExp(r'[,.!?;:]'), '');
    if (clean.endsWith('ent')) {
      final root = clean.substring(0, clean.length - 3);
      return variant == 1 ? '${root}e' : '${root}er';
    }
    if (clean.endsWith('ons')) {
      final root = clean.substring(0, clean.length - 3);
      return variant == 1 ? '${root}ez' : '${root}er';
    }
    if (clean.endsWith('ez')) {
      final root = clean.substring(0, clean.length - 2);
      return variant == 1 ? '${root}e' : '${root}er';
    }
    if (clean.endsWith('e')) {
      return variant == 1 ? '${clean}s' : '${clean}r';
    }
    if (clean.endsWith('s')) {
      return variant == 1 ? clean.substring(0, clean.length - 1) : '${clean}e';
    }
    return variant == 1 ? '${clean}e' : '${clean}er';
  }

  String _replaceFirst(String sentence, String from, String to) {
    final index = sentence.toLowerCase().indexOf(from.toLowerCase());
    if (index < 0) return sentence;
    return '${sentence.substring(0, index)}$to${sentence.substring(index + from.length)}';
  }

  String _normalise(String value) => value
      .toLowerCase()
      .replaceAllMapped(RegExp(r'\s+([,.!?;:])'), (match) => match.group(1)!)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void _advanceConcept() {
    setState(() => _correct = true);
    _nextStep();
  }

  void _check() {
    final answer = _index == _stageLabels.length - 1
        ? _normalise(_builtSentence.join(' '))
        : _normalise(_selectedChoice ?? '');
    final expected = _normalise(_step.target);
    setState(() {
      _attemptedCount++;
      _correct = answer == expected;
      if (_correct == true) _correctCount++;
    });
  }

  void _nextStep() {
    if (_correct != true) return;
    final store = ref.read(learningStoreProvider);
    store.setLessonStatus(
      '${widget.session.progressId}_step_$_index',
      'completed',
      score: 1,
    );
    if (_isLastStep) {
      store.setLessonStatus(widget.session.progressId, 'completed', score: 1);
      if (!mounted) return;
      Navigator.of(context).pop(
        GrammarCourseSessionResult(
          sessionId: widget.session.id,
          correct: _correctCount,
          attempted: _attemptedCount,
          completed: true,
        ),
      );
      return;
    }
    setState(() {
      _index++;
      _resetStep();
    });
  }

  void _retry() {
    setState(() {
      _correct = null;
      _selectedChoice = null;
      _builtSentence.clear();
    });
  }

  void _addWord(String word) {
    if (_correct != null) return;
    final used = _builtSentence.where((item) => item == word).length;
    final available = _wordBank.where((item) => item == word).length;
    if (used >= available) return;
    setState(() => _builtSentence.add(word));
  }

  bool _wordIsAvailable(String word) {
    final used = _builtSentence.where((item) => item == word).length;
    final available = _wordBank.where((item) => item == word).length;
    return used < available;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: DesignTokens.canvas,
    body: SafeArea(
      child: WebConstrainedView(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                children: [
                  _metaRow(),
                  const SizedBox(height: 9),
                  Text(_stageTitles[_index], style: DesignTokens.display(30)),
                  const SizedBox(height: 6),
                  Text(
                    _stageSubtitles[_index],
                    style: DesignTokens.body(
                      15,
                    ).copyWith(color: DesignTokens.muted, height: 1.35),
                  ),
                  const SizedBox(height: 18),
                  _stageContent(),
                  if (_correct != null) ...[
                    const SizedBox(height: 14),
                    _feedback(),
                  ],
                ],
              ),
            ),
            _bottomAction(),
          ],
        ),
      ),
    ),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
    child: Column(
      children: [
        SizedBox(
          height: 54,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Close grammar session',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(CupertinoIcons.xmark),
              ),
              Expanded(
                child: Text(
                  widget.session.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.display(18),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  widget.session.level,
                  textAlign: TextAlign.end,
                  style: DesignTokens.label(12),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              minHeight: 5,
              value:
                  (_index + (_correct == true ? 1 : 0)) /
                  widget.session.steps.length,
              backgroundColor: DesignTokens.hairline,
              valueColor: AlwaysStoppedAnimation(DesignTokens.primary),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _metaRow() => Row(
    children: [
      Expanded(
        child: Text(
          'COMPLETE · ${widget.session.tense.toUpperCase()}',
          style: DesignTokens.label(
            12,
            weight: FontWeight.w800,
          ).copyWith(color: DesignTokens.primary, letterSpacing: 1.1),
        ),
      ),
      Text(
        'STAGE ${_index + 1} OF ${widget.session.steps.length}',
        style: DesignTokens.label(10).copyWith(color: DesignTokens.muted),
      ),
    ],
  );

  Widget _stageContent() => switch (_index) {
    0 => _learnStage(),
    1 => _noticeStage(),
    2 => _choiceStage(title: 'CHOOSE THE MATCHING TRANSFORMATION'),
    3 => _choiceStage(title: 'CHOOSE THE REPAIRED SENTENCE'),
    _ => _produceStage(),
  };

  Widget _surface({required Widget child, bool focus = false}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: DesignTokens.surface,
      borderRadius: BorderRadius.circular(21),
      border: Border.all(
        color: focus
            ? DesignTokens.primary.withValues(alpha: 0.65)
            : DesignTokens.hairline,
      ),
    ),
    child: child,
  );

  Widget _learnStage() => _surface(
    focus: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.session.grammarFocus,
          style: DesignTokens.label(
            11,
            weight: FontWeight.w800,
          ).copyWith(color: DesignTokens.primary),
        ),
        const SizedBox(height: 12),
        Text(_step.target, style: DesignTokens.display(23)),
        const SizedBox(height: 6),
        Text(
          _step.promptEnglish,
          style: DesignTokens.body(14).copyWith(color: DesignTokens.muted),
        ),
        const SizedBox(height: 14),
        Divider(color: DesignTokens.hairline),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline_rounded, color: DesignTokens.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _step.tip,
                style: DesignTokens.body(
                  14,
                  weight: FontWeight.w700,
                ).copyWith(height: 1.35),
              ),
            ),
            TtsPlayButton(
              text: _step.target,
              contentItemId: _audioId('target'),
              size: 40,
              color: DesignTokens.primary,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _noticeStage() {
    final tokens = _step.tokens;
    final subject = tokens.isEmpty ? '' : tokens.first;
    final verbIndex = tokens.length > 1 ? _verbIndex(tokens) : 0;
    final verb = tokens.length > verbIndex ? tokens[verbIndex] : '';
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('READ THE SENTENCE', style: _sectionLabelStyle()),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: subject,
                  style: TextStyle(color: DesignTokens.primary),
                ),
                if (subject.isNotEmpty && verb.isNotEmpty)
                  const TextSpan(text: ' '),
                TextSpan(
                  text: verb,
                  style: TextStyle(
                    color: DesignTokens.ink,
                    decoration: TextDecoration.underline,
                    decorationColor: DesignTokens.primary,
                    decorationThickness: 2,
                  ),
                ),
                if (tokens.length > 1)
                  TextSpan(text: ' ${tokens.skip(verbIndex + 1).join(' ')}'),
              ],
            ),
            style: DesignTokens.display(22),
          ),
          const SizedBox(height: 9),
          Text(
            _step.promptEnglish,
            style: DesignTokens.body(14).copyWith(color: DesignTokens.muted),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _tag('SUBJECT', subject),
              const SizedBox(width: 8),
              _tag('PRESENT FORM', verb),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(String label, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
        color: DesignTokens.primarySoft,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _sectionLabelStyle(size: 9)),
          const SizedBox(height: 4),
          Text(value, style: DesignTokens.body(14, weight: FontWeight.w800)),
        ],
      ),
    ),
  );

  Widget _choiceStage({required String title}) => _surface(
    focus: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: _sectionLabelStyle()),
        const SizedBox(height: 11),
        Text(
          _step.promptEnglish,
          style: DesignTokens.body(14).copyWith(color: DesignTokens.muted),
        ),
        const SizedBox(height: 13),
        for (final choice in _choices) ...[
          _sentenceChoice(choice),
          const SizedBox(height: 8),
        ],
        if (_index == 3) ...[
          const SizedBox(height: 3),
          Text(
            'The sentence keeps the same meaning; only the form is repaired.',
            style: DesignTokens.body(12).copyWith(color: DesignTokens.muted),
          ),
        ],
      ],
    ),
  );

  Widget _sentenceChoice(String choice) {
    final selected = choice == _selectedChoice;
    final answerShown = _correct != null && choice == _step.target;
    final wrongShown = _correct == false && selected;
    final color = answerShown
        ? DesignTokens.success
        : wrongShown
        ? DesignTokens.danger
        : selected
        ? DesignTokens.primary
        : DesignTokens.hairline;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _correct == null
          ? () => setState(() => _selectedChoice = choice)
          : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        decoration: BoxDecoration(
          color: DesignTokens.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                choice,
                style: DesignTokens.body(15, weight: FontWeight.w700),
              ),
            ),
            if (answerShown)
              Icon(Icons.check_circle_rounded, color: DesignTokens.success)
            else if (wrongShown)
              Icon(Icons.cancel_rounded, color: DesignTokens.danger),
          ],
        ),
      ),
    );
  }

  Widget _produceStage() => _surface(
    focus: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('BUILD ONE FINAL LINE', style: _sectionLabelStyle()),
        const SizedBox(height: 10),
        Text(
          _step.promptEnglish,
          style: DesignTokens.body(14).copyWith(color: DesignTokens.muted),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: DesignTokens.primarySoft,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _builtSentence.isEmpty
                      ? 'Tap the words to build the sentence.'
                      : _builtSentence.join(' '),
                  style: DesignTokens.display(19).copyWith(
                    color: _builtSentence.isEmpty
                        ? DesignTokens.muted
                        : DesignTokens.ink,
                  ),
                ),
              ),
              if (_builtSentence.isNotEmpty)
                TtsPlayButton(
                  text: _step.target,
                  contentItemId: _audioId('target'),
                  size: 38,
                  color: DesignTokens.primary,
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text('WORD BANK', style: _sectionLabelStyle()),
        const SizedBox(height: 9),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final word in _wordBank)
              if (_wordIsAvailable(word))
                ActionChip(
                  label: Text(word),
                  onPressed: () => _addWord(word),
                  backgroundColor: DesignTokens.surface,
                  side: BorderSide(color: DesignTokens.hairline),
                  labelStyle: DesignTokens.body(14, weight: FontWeight.w700),
                ),
          ],
        ),
      ],
    ),
  );

  TextStyle _sectionLabelStyle({double size = 10}) => DesignTokens.label(
    size,
    weight: FontWeight.w800,
  ).copyWith(color: DesignTokens.primary, letterSpacing: 1.05);

  Widget _feedback() {
    final correct = _correct == true;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: correct ? DesignTokens.successSoft : DesignTokens.primarySoft,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            correct
                ? Icons.check_circle_outline_rounded
                : Icons.refresh_rounded,
            color: correct ? DesignTokens.success : DesignTokens.primary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              correct
                  ? 'Correct. ${_step.tip}'
                  : 'Try again and keep the same meaning.',
              style: DesignTokens.body(
                13,
                weight: FontWeight.w700,
              ).copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomAction() {
    final label = _correct == true
        ? (_isLastStep ? 'Finish workshop' : 'Next stage')
        : _correct == false
        ? 'Try again'
        : _index < 2
        ? (_index == 0 ? 'I understand' : 'I see the pattern')
        : _index == 2
        ? 'Check transformation'
        : _index == 3
        ? 'Check repair'
        : 'Check sentence';
    final canAct = _correct != null || _index < 2
        ? true
        : _index == widget.session.steps.length - 1
        ? _builtSentence.isNotEmpty
        : _selectedChoice != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      decoration: BoxDecoration(
        color: DesignTokens.canvas,
        border: Border(top: BorderSide(color: DesignTokens.hairline)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: canAct
              ? () {
                  if (_correct == true) {
                    _nextStep();
                  } else if (_correct == false) {
                    _retry();
                  } else if (_index < 2) {
                    _advanceConcept();
                  } else {
                    _check();
                  }
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: DesignTokens.primary,
            foregroundColor: DesignTokens.onPrimary,
            disabledBackgroundColor: DesignTokens.hairline,
            minimumSize: const Size(0, 56),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
            ),
          ),
          child: Text(
            label,
            style: DesignTokens.body(15, weight: FontWeight.w800).copyWith(
              color: canAct ? DesignTokens.onPrimary : DesignTokens.muted,
            ),
          ),
        ),
      ),
    );
  }

  String _audioId(String role) =>
      'grammar-session:${widget.session.id}:step:$_index:$role';
}
