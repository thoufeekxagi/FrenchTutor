import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../models/grammar_course.dart';
import '../../models/grammar_course_session_result.dart';
import '../../models/grammar_course_v2.dart';
import '../../providers/database_provider.dart';
import '../../prompts/live_prompts.dart';
import '../../services/inline_call_controller.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/inline_call_bar.dart';
import '../../widgets/tts_play_button.dart';
import '../../widgets/web/web_constrained_view.dart';
import 'grammar_complete_lesson_screen.dart';
import 'grammar_roleplay_lesson_screen.dart';

/// One continuous Grammar session. The current step changes in place so the
/// learner experiences one lesson with a beginning, middle, and finish—not a
/// pile of unrelated sentence cards.
class GrammarV2LessonScreen extends ConsumerStatefulWidget {
  const GrammarV2LessonScreen({
    super.key,
    required this.session,
    this.warmupSessions = const [],
  });

  final GrammarCourseSession session;
  final List<GrammarCourseSession> warmupSessions;

  @override
  ConsumerState<GrammarV2LessonScreen> createState() =>
      _GrammarV2LessonScreenState();
}

class _GrammarV2LessonScreenState extends ConsumerState<GrammarV2LessonScreen>
    with WidgetsBindingObserver {
  final List<String> _builtSentence = [];
  List<String> _wordBank = [];
  List<String> _choiceBank = [];
  int _index = 0;
  String? _selectedChoice;
  bool? _correct;
  bool _showTranslation = true;
  bool _showHint = false;
  InlineCallController? _call;
  int _correctCount = 0;
  int _attemptedCount = 0;

  GrammarCourseStep get _step => widget.session.steps[_index];
  bool get _isCompleteMode => widget.session.mode == GrammarV2Mode.complete;
  bool get _isRoleplayMode => widget.session.mode == GrammarV2Mode.roleplay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.session.mode != GrammarV2Mode.guided) return;
    _resetStep();
    _call = InlineCallController(
      sessionType: LiveSessionType.grammarStage,
      lessonContext: _lessonContext,
      learningStoreForProfile: ref.read(learningStoreProvider),
      onChanged: () {
        if (mounted) setState(() {});
      },
      manualLearnerTurns: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_prewarmSessionAudio());
    });
  }

  void _resetStep() {
    final seed = '${widget.session.id}:$_index'.hashCode;
    _wordBank = [..._step.tokens]..shuffle(math.Random(seed));
    _choiceBank = [..._step.choices]
      ..shuffle(math.Random('$seed:choices'.hashCode));
    _builtSentence.clear();
    _selectedChoice = null;
    _correct = null;
    _showHint = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _call?.handleAppLifecycle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _call?.dispose();
    unawaited(LessonSpeechService.shared.stop());
    super.dispose();
  }

  /// The live tutor receives a replacement snapshot whenever anything visible
  /// changes. Keeping this here (rather than in a separate prompt builder)
  /// means the call and the screen always share the same current step state.
  String _lessonContext() {
    final visibleChoices = _choiceBank.isEmpty
        ? '(none)'
        : _choiceBank.join(' | ');
    final visibleWordBank = _wordBank.where(_wordIsAvailable).isEmpty
        ? '(none)'
        : _wordBank.where(_wordIsAvailable).join(' | ');
    final answerTray = _builtSentence.isEmpty
        ? '(empty)'
        : _builtSentence.join(' ');
    final result = _correct == null
        ? 'not checked'
        : (_correct == true ? 'correct' : 'incorrect');

    return '''
GRAMMAR SESSION: ${widget.session.title}
LEVEL: ${widget.session.level}
TENSE: ${widget.session.tense}
GRAMMAR FOCUS: ${widget.session.grammarFocus}
MODE: ${widget.session.mode.label}

CURRENT SCREEN SNAPSHOT — this replaces every older step snapshot:
STEP: ${_index + 1} of ${widget.session.steps.length}
STEP LABEL: ${_step.label}
VISIBLE ENGLISH INSTRUCTION: ${_step.promptEnglish}
VISIBLE PROMPT: ${_step.prompt}
VISIBLE TARGET SENTENCE: ${_step.target}
VISIBLE OPTIONS (in the option area, in display order): $visibleChoices
VISIBLE WORD BANK (remaining visible words, in display order): $visibleWordBank
CURRENT ANSWER TRAY: $answerTray
CURRENT SELECTION: ${_selectedChoice ?? '(none)'}
CHECK RESULT: $result
TRANSLATION VISIBLE: $_showTranslation
HINT VISIBLE: $_showHint${_showHint ? '\nVISIBLE HINT: ${_step.tip}' : ''}
${_isRoleplayMode ? 'VISIBLE PARTNER FRENCH: ${_step.partnerFrench}\nVISIBLE PARTNER ENGLISH: ${_step.partnerEnglish}\nVISIBLE LEARNER GOAL: ${_step.prompt}' : ''}

PRIVATE ANSWER KEY FOR COACHING: ${_step.answer}

SCOPE RULES:
- Help only with the current screen snapshot above. Ignore all previous and
  future steps; do not preview, mention, or teach them.
- Do not invent a new sentence, new vocabulary, or an unrelated example.
- Keep explanations to this exact sentence and the visible options/word bank.
- If the learner asks about past, present, or future, transform only the
  current target while preserving its meaning and vocabulary, then return to
  this step. Do not introduce a separate sentence.
- The app owns answer checking, progression, and completion. Never advance the
  session or tell the learner to skip ahead.
''';
  }

  void _syncTutorContext() {
    final call = _call;
    if (call == null || !call.isLive) return;
    call.updateLessonContext();
  }

  Future<void> _prewarmSessionAudio() async {
    final sessions = [widget.session, ...widget.warmupSessions];
    final items = <SpeechItem>[];
    for (final session in sessions) {
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
        if (step.partnerFrench != null) {
          items.add(
            SpeechItem(
              text: step.partnerFrench!,
              language: 'fr-FR',
              contentItemId: '$prefix:partner',
            ),
          );
        }
        for (
          var choiceIndex = 0;
          choiceIndex < step.choices.length;
          choiceIndex++
        ) {
          items.add(
            SpeechItem(
              text: step.choices[choiceIndex],
              language: 'fr-FR',
              contentItemId: '$prefix:choice:$choiceIndex',
            ),
          );
        }
      }
    }
    try {
      await LessonSpeechService.shared.prewarmNarration(items);
    } catch (error) {
      debugPrint('Grammar session audio prewarm skipped: $error');
    }
  }

  void _selectChoice(String choice) {
    if (_correct != null) return;
    setState(() => _selectedChoice = choice);
    _syncTutorContext();
  }

  void _addWord(String word) {
    if (_correct != null) return;
    final used = _builtSentence.where((item) => item == word).length;
    final available = _wordBank.where((item) => item == word).length;
    if (used >= available) return;
    setState(() => _builtSentence.add(word));
    _syncTutorContext();
  }

  void _removeWord(int index) {
    if (_correct != null) return;
    setState(() => _builtSentence.removeAt(index));
    _syncTutorContext();
  }

  bool _wordIsAvailable(String word) {
    final used = _builtSentence.where((item) => item == word).length;
    final available = _wordBank.where((item) => item == word).length;
    return used < available;
  }

  void _check() {
    final answer = _isCompleteMode
        ? _normalise(_builtSentence.join(' '))
        : _selectedChoice?.trim().toLowerCase() ?? '';
    final expected = _isCompleteMode
        ? _normalise(_step.target)
        : _step.answer.trim().toLowerCase();
    setState(() {
      _attemptedCount++;
      _correct = answer == expected;
      if (_correct == true) _correctCount++;
    });
    _syncTutorContext();
  }

  String _normalise(String value) => value
      .toLowerCase()
      .replaceAllMapped(RegExp(r'\s+([,.!?;:])'), (match) => match.group(1)!)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void _nextStep() {
    if (_correct != true) return;
    ref
        .read(learningStoreProvider)
        .setLessonStatus(
          '${widget.session.progressId}_step_$_index',
          'completed',
          score: 1,
        );
    if (_index == widget.session.steps.length - 1) {
      final store = ref.read(learningStoreProvider);
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
    _syncTutorContext();
  }

  void _retry() {
    setState(() {
      _correct = null;
      _selectedChoice = null;
      _builtSentence.clear();
    });
    _syncTutorContext();
  }

  void _toggleHint() {
    setState(() => _showHint = !_showHint);
    _syncTutorContext();
  }

  void _toggleTranslation() {
    setState(() => _showTranslation = !_showTranslation);
    _syncTutorContext();
  }

  @override
  Widget build(BuildContext context) {
    if (_isCompleteMode) {
      return GrammarCompleteLessonScreen(
        session: widget.session,
        warmupSessions: widget.warmupSessions,
      );
    }
    if (_isRoleplayMode) {
      return GrammarRoleplayLessonScreen(
        session: widget.session,
        warmupSessions: widget.warmupSessions,
      );
    }
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: WebConstrainedView(
          child: Column(
            children: [
              _header(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
                  children: [
                    _modeLabel(),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _heading,
                            style: DesignTokens.display(30),
                          ),
                        ),
                        if (_call != null)
                          InlineCallActions(
                            controller: _call!,
                            accentColor: DesignTokens.primary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _step.promptEnglish,
                      style: DesignTokens.body(
                        15,
                      ).copyWith(color: DesignTokens.muted, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    _exercise(),
                    const SizedBox(height: 20),
                    _supportRow(),
                    if (_showHint) ...[const SizedBox(height: 12), _hintCard()],
                    if (_correct != null) ...[
                      const SizedBox(height: 16),
                      _feedbackCard(),
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
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
    child: Column(
      children: [
        SizedBox(
          height: 54,
          child: Row(
            children: [
              Semantics(
                button: true,
                label: 'Close grammar session',
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(CupertinoIcons.xmark),
                  color: DesignTokens.ink,
                ),
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
            borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
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

  Widget _modeLabel() => Row(
    children: [
      Expanded(
        child: Text(
          '${widget.session.mode.label.toUpperCase()} · ${widget.session.tense.toUpperCase()}',
          style: DesignTokens.label(
            12,
            weight: FontWeight.w800,
          ).copyWith(color: DesignTokens.primary, letterSpacing: 1.1),
        ),
      ),
      Text(
        'STEP ${_index + 1} OF ${widget.session.steps.length}',
        style: DesignTokens.label(10).copyWith(color: DesignTokens.muted),
      ),
    ],
  );

  String get _heading => switch (widget.session.mode) {
    GrammarV2Mode.guided => 'Choose the right form',
    GrammarV2Mode.complete => 'Build the sentence',
    GrammarV2Mode.roleplay => 'Reply in the scene',
  };

  Widget _exercise() => switch (widget.session.mode) {
    GrammarV2Mode.guided => _guidedExercise(),
    GrammarV2Mode.complete => _completeExercise(),
    GrammarV2Mode.roleplay => _roleplayExercise(),
  };

  Widget _guidedExercise() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _PromptCard(
        prompt: _step.prompt,
        translation: _showTranslation ? _step.promptEnglish : null,
        audioText: _step.target,
        contentItemId: _audioId('target'),
      ),
      const SizedBox(height: 16),
      _sectionLabel('CHOOSE THE FORM'),
      const SizedBox(height: 9),
      for (final choice in _choiceBank) ...[
        _ChoiceTile(
          text: choice,
          selected: choice == _selectedChoice,
          correct: _correct == null ? null : choice == _step.answer,
          onTap: () => _selectChoice(choice),
        ),
        const SizedBox(height: 9),
      ],
    ],
  );

  Widget _completeExercise() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _AnswerTray(
        words: _builtSentence,
        onRemove: _removeWord,
        audioText: _step.target,
        contentItemId: _audioId('target'),
      ),
      const SizedBox(height: 16),
      _sectionLabel('WORD BANK'),
      const SizedBox(height: 9),
      Wrap(
        spacing: 8,
        runSpacing: 9,
        children: [
          for (final word in _wordBank)
            if (_wordIsAvailable(word))
              _WordChip(word: word, onTap: () => _addWord(word)),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        'Tap the words in the right order.',
        style: DesignTokens.body(14).copyWith(color: DesignTokens.muted),
      ),
    ],
  );

  Widget _roleplayExercise() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _PartnerCard(
        french: _step.partnerFrench!,
        english: _step.partnerEnglish!,
        showTranslation: _showTranslation,
        audioText: _step.partnerFrench!,
        contentItemId: _audioId('partner'),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DesignTokens.primarySoft,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: DesignTokens.primary.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.track_changes_rounded, color: DesignTokens.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _step.prompt,
                style: DesignTokens.body(14, weight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      for (final choice in _choiceBank) ...[
        _ChoiceTile(
          text: choice,
          selected: choice == _selectedChoice,
          correct: _correct == null ? null : choice == _step.answer,
          onTap: () => _selectChoice(choice),
        ),
        const SizedBox(height: 9),
      ],
    ],
  );

  Widget _supportRow() => LayoutBuilder(
    builder: (context, constraints) => Row(
      children: [
        Expanded(child: _listenButton()),
        const SizedBox(width: 8),
        Expanded(
          child: _supportButton(
            Icons.lightbulb_outline_rounded,
            'Hint',
            _toggleHint,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _supportButton(
            Icons.translate_rounded,
            'Translate',
            _toggleTranslation,
            selected: _showTranslation,
          ),
        ),
      ],
    ),
  );

  Widget _listenButton() => Container(
    height: 50,
    decoration: BoxDecoration(
      border: Border.all(color: DesignTokens.hairline),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TtsPlayButton(
          text: _isRoleplayMode ? _step.partnerFrench! : _step.target,
          contentItemId: _audioId(_isRoleplayMode ? 'partner' : 'target'),
          size: 42,
          iconSize: 20,
          color: DesignTokens.primary,
        ),
        Text('Listen', style: DesignTokens.body(13, weight: FontWeight.w800)),
      ],
    ),
  );

  Widget _supportButton(
    IconData icon,
    String label,
    VoidCallback onPressed, {
    bool selected = false,
  }) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    style: OutlinedButton.styleFrom(
      foregroundColor: selected ? DesignTokens.primary : DesignTokens.ink,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      minimumSize: const Size(0, 50),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide(
        color: selected ? DesignTokens.primary : DesignTokens.hairline,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: DesignTokens.body(13, weight: FontWeight.w800),
    ),
  );

  Widget _hintCard() => _InfoCard(
    icon: Icons.tips_and_updates_outlined,
    color: DesignTokens.primarySoft,
    text: _step.tip,
  );

  Widget _feedbackCard() {
    final correct = _correct == true;
    return _InfoCard(
      icon: correct
          ? Icons.check_circle_outline_rounded
          : Icons.refresh_rounded,
      color: correct ? DesignTokens.successSoft : DesignTokens.primarySoft,
      text: correct
          ? 'Correct. ${_step.tip}'
          : 'Try again. The target is ${_step.target}',
    );
  }

  Widget _bottomAction() {
    final checked = _correct != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      decoration: BoxDecoration(
        color: DesignTokens.canvas,
        border: Border(top: BorderSide(color: DesignTokens.hairline)),
      ),
      child: Row(
        children: [
          if (checked && _correct == false) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: _retry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: DesignTokens.primary,
                  minimumSize: const Size(0, 56),
                  side: BorderSide(color: DesignTokens.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                child: const Text('Try again'),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: ElevatedButton(
              onPressed: checked
                  ? (_correct == true ? _nextStep : _retry)
                  : _canCheck
                  ? _check
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignTokens.primary,
                foregroundColor: DesignTokens.onPrimary,
                disabledBackgroundColor: DesignTokens.hairline,
                elevation: 0,
                minimumSize: const Size(0, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              child: Text(
                checked
                    ? (_correct == true
                          ? (_isLastStep ? 'Finish session' : 'Next step')
                          : 'Try again')
                    : _checkLabel,
                style: DesignTokens.body(15, weight: FontWeight.w800).copyWith(
                  color: checked || _canCheck
                      ? DesignTokens.onPrimary
                      : DesignTokens.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _isLastStep => _index == widget.session.steps.length - 1;
  bool get _canCheck =>
      _isCompleteMode ? _builtSentence.isNotEmpty : _selectedChoice != null;

  String get _checkLabel => switch (widget.session.mode) {
    GrammarV2Mode.guided => 'Check form',
    GrammarV2Mode.complete => 'Check sentence',
    GrammarV2Mode.roleplay => 'Check reply',
  };

  String _audioId(String role) =>
      'grammar-session:${widget.session.id}:step:$_index:$role';

  Widget _sectionLabel(String value) => Text(
    value,
    style: DesignTokens.label(
      12,
      weight: FontWeight.w800,
    ).copyWith(color: DesignTokens.primary, letterSpacing: 1.15),
  );
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.prompt,
    required this.translation,
    required this.audioText,
    required this.contentItemId,
  });

  final String prompt;
  final String? translation;
  final String audioText;
  final String contentItemId;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 18, 13, 18),
    decoration: BoxDecoration(
      color: DesignTokens.surface,
      borderRadius: BorderRadius.circular(21),
      border: Border.all(color: DesignTokens.hairline),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(prompt, style: DesignTokens.display(24)),
              if (translation != null) ...[
                const SizedBox(height: 8),
                Text(
                  translation!,
                  style: DesignTokens.body(
                    14,
                  ).copyWith(color: DesignTokens.muted, height: 1.35),
                ),
              ],
            ],
          ),
        ),
        TtsPlayButton(
          text: audioText,
          contentItemId: contentItemId,
          size: 42,
          color: DesignTokens.primary,
        ),
      ],
    ),
  );
}

class _PartnerCard extends StatelessWidget {
  const _PartnerCard({
    required this.french,
    required this.english,
    required this.showTranslation,
    required this.audioText,
    required this.contentItemId,
  });

  final String french;
  final String english;
  final bool showTranslation;
  final String audioText;
  final String contentItemId;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
    decoration: BoxDecoration(
      color: DesignTokens.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: DesignTokens.hairline),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TUTOR',
                style: DesignTokens.label(
                  10,
                  weight: FontWeight.w800,
                ).copyWith(color: DesignTokens.primary, letterSpacing: 1.1),
              ),
              const SizedBox(height: 8),
              Text(french, style: DesignTokens.display(21)),
              if (showTranslation) ...[
                const SizedBox(height: 6),
                Text(
                  english,
                  style: DesignTokens.body(
                    14,
                  ).copyWith(color: DesignTokens.muted),
                ),
              ],
            ],
          ),
        ),
        TtsPlayButton(
          text: audioText,
          contentItemId: contentItemId,
          size: 42,
          color: DesignTokens.primary,
        ),
      ],
    ),
  );
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.text,
    required this.selected,
    required this.correct,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final bool? correct;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isAnswer = correct == true && selected;
    final isWrong = correct == false && selected;
    final color = isAnswer
        ? DesignTokens.success
        : isWrong
        ? DesignTokens.danger
        : selected
        ? DesignTokens.primary
        : DesignTokens.hairline;
    return Material(
      color: DesignTokens.surface,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: correct == null ? onTap : null,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: color, width: selected ? 1.6 : 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: DesignTokens.body(16, weight: FontWeight.w700),
                ),
              ),
              if (isAnswer)
                Icon(Icons.check_circle_rounded, color: DesignTokens.success)
              else if (isWrong)
                Icon(Icons.cancel_rounded, color: DesignTokens.danger),
            ],
          ),
        ),
      ),
    );
  }
}

class _WordChip extends StatelessWidget {
  const _WordChip({required this.word, required this.onTap});

  final String word;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
    onPressed: onTap,
    label: Text(word),
    backgroundColor: DesignTokens.surface,
    side: BorderSide(color: DesignTokens.hairline),
    labelStyle: DesignTokens.body(14, weight: FontWeight.w700),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
  );
}

class _AnswerTray extends StatelessWidget {
  const _AnswerTray({
    required this.words,
    required this.onRemove,
    required this.audioText,
    required this.contentItemId,
  });

  final List<String> words;
  final ValueChanged<int> onRemove;
  final String audioText;
  final String contentItemId;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 128),
    padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
    decoration: BoxDecoration(
      color: DesignTokens.surface,
      borderRadius: BorderRadius.circular(21),
      border: Border.all(color: DesignTokens.primary.withValues(alpha: 0.5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                words.isEmpty
                    ? 'Tap words to build the sentence'
                    : words.join(' '),
                style: DesignTokens.display(20),
              ),
            ),
            if (words.isNotEmpty)
              TtsPlayButton(
                text: audioText,
                contentItemId: contentItemId,
                size: 40,
                color: DesignTokens.primary,
              ),
          ],
        ),
        if (words.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var index = 0; index < words.length; index++)
                InputChip(
                  label: Text(words[index]),
                  onDeleted: () => onRemove(index),
                ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: DesignTokens.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: DesignTokens.body(
              14,
              weight: FontWeight.w700,
            ).copyWith(height: 1.35),
          ),
        ),
      ],
    ),
  );
}
