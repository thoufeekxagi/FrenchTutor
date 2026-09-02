import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/learning_store.dart';
import '../../design/tokens.dart';
import '../../models/writing_course.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../services/inline_call_controller.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/web/web_constrained_view.dart';

class WritingCourseLessonScreen extends StatefulWidget {
  const WritingCourseLessonScreen({super.key, required this.lesson});

  final WritingCourseLesson lesson;

  @override
  State<WritingCourseLessonScreen> createState() =>
      _WritingCourseLessonScreenState();
}

class _WritingCourseLessonScreenState extends State<WritingCourseLessonScreen>
    with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final List<int> _selectedTokenIndexes = [];
  final List<String> _completedReplies = [];
  late List<String> _wordBank;
  late List<int> _wordBankSourceIndexes;
  int _index = 0;
  String? _selectedChoice;
  String? _message;
  bool _correct = false;
  bool _showHint = false;
  bool _showTranslations = true;
  bool _roleplayReview = false;
  bool _isHintLoading = false;
  String? _dynamicHint;
  bool _audioLoading = false;
  String? _activeAudioKey;
  InlineCallController? _call;
  LearningStore? _learningStore;

  WritingCourseStep get _step => widget.lesson.steps[_index];
  bool get _isLast => _index == widget.lesson.steps.length - 1;

  @override
  void initState() {
    super.initState();
    _shuffleWordBank();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_prewarmLessonAudio());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _call?.handleAppLifecycle(state);
  }

  @override
  void dispose() {
    unawaited(LessonSpeechService.shared.stop());
    WidgetsBinding.instance.removeObserver(this);
    _call?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: WebConstrainedView(
          child: Column(
            children: [
              _header(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    DesignTokens.screenMargin,
                    24,
                    DesignTokens.screenMargin,
                    keyboardOpen ? 12 : 24,
                  ),
                  child: AnimatedSwitcher(
                    duration: DesignTokens.durationFast,
                    switchInCurve: DesignTokens.curveStandard,
                    child: KeyedSubtree(
                      key: ValueKey('${widget.lesson.id}-$_index'),
                      child: switch (widget.lesson.mode) {
                        WritingCourseMode.guided => _guidedView(),
                        WritingCourseMode.complete => _completeView(),
                        WritingCourseMode.roleplay => _roleplayView(),
                      },
                    ),
                  ),
                ),
              ),
              _bottomAction(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final progress = (_index + 1) / widget.lesson.steps.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
      child: Column(
        children: [
          SizedBox(
            height: 54,
            child: Row(
              children: [
                Semantics(
                  label: 'Close writing lesson',
                  button: true,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                    color: DesignTokens.ink,
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.lesson.title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: DesignTokens.display(18),
                  ),
                ),
                SizedBox(
                  width: 58,
                  child: Text(
                    '${_index + 1} of ${widget.lesson.steps.length}',
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
                value: progress,
                backgroundColor: DesignTokens.hairline,
                valueColor: AlwaysStoppedAnimation(DesignTokens.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guidedView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _modeLabel('GUIDED'),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(_step.prompt, style: DesignTokens.display(31)),
            ),
            const SizedBox(width: 6),
            _tutorCallActions(),
          ],
        ),
        if (_showTranslations) const SizedBox(height: 10),
        if (_showTranslations)
          Text(
            _step.promptEnglish,
            style: DesignTokens.body(
              16,
            ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
          ),
        const SizedBox(height: 22),
        _guidedAnswerTray(),
        const SizedBox(height: 24),
        _sectionLabel('WORD BANK'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var index = 0; index < _wordBank.length; index++)
              _WordChip(
                label: _wordBank[index],
                meaning: _meaningForToken(index),
                showMeaning: _showTranslations,
                enabled: !_correct && !_selectedTokenIndexes.contains(index),
                onTap: () => _selectToken(index),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Tap the words in the right order.',
          style: DesignTokens.body(13).copyWith(color: DesignTokens.muted),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _secondaryAction(
                icon: Icons.volume_up_outlined,
                label: 'Listen',
                loading:
                    _audioLoading &&
                    _activeAudioKey == _speechKey('guided-model'),
                onTap: () =>
                    _speak(_step.target, speechKey: _speechKey('guided-model')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _secondaryAction(
                icon: Icons.lightbulb_outline_rounded,
                label: 'Hint',
                loading: _isHintLoading,
                onTap: _requestGuidedHint,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _translationToggle(fillWidth: true, compact: true)),
          ],
        ),
        if (_showHint) ...[
          const SizedBox(height: 14),
          _InlineNotice(
            icon: Icons.lightbulb_outline_rounded,
            text:
                _dynamicHint ??
                (_step.tip.isEmpty
                    ? 'Start with ${_step.tokens.first}.'
                    : _step.tip),
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 14),
          _InlineNotice(
            icon: _correct
                ? Icons.check_circle_outline_rounded
                : Icons.refresh_rounded,
            text: _message!,
            success: _correct,
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _guidedAnswerTray() {
    final hasAnswer = _selectedTokenIndexes.isNotEmpty;
    return AnimatedSize(
      duration: DesignTokens.durationFast,
      curve: DesignTokens.curveStandard,
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: hasAnswer
                  ? Wrap(
                      alignment: WrapAlignment.start,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tokenIndex in _selectedTokenIndexes)
                          _AnswerToken(
                            token: _wordBank[tokenIndex],
                            onTap: _correct
                                ? null
                                : () => _removeToken(tokenIndex),
                          ),
                      ],
                    )
                  : const SizedBox(height: 44),
            ),
            const SizedBox(width: 8),
            _audioButton(
              _step.target,
              'Listen to the model sentence',
              speechKey: _speechKey('guided-model'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _completeView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _modeLabel('COMPLETE'),
        const SizedBox(height: 12),
        Text('Choose the best word', style: DesignTokens.display(31)),
        if ((_step.partnerFrench ?? '').isNotEmpty) ...[
          const SizedBox(height: 24),
          _PartnerBubble(
            french: _step.partnerFrench!,
            english: _step.partnerEnglish,
            showTranslation: _showTranslations,
            onListen: () => _speak(_step.partnerFrench!),
          ),
        ],
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _step.prompt,
                textAlign: TextAlign.center,
                style: DesignTokens.body(23, weight: FontWeight.w600),
              ),
              if (_showTranslations && _step.promptEnglish.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '(${_completePromptEnglish()})',
                  textAlign: TextAlign.center,
                  style: DesignTokens.body(
                    14,
                  ).copyWith(color: DesignTokens.inkSoft),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        for (final choice in _step.choices) ...[
          _ChoiceRow(
            label: choice,
            meaning: _choiceMeaning(choice),
            showMeaning: _showTranslations,
            selected: choice == _selectedChoice,
            locked: _correct,
            onTap: () => setState(() {
              _selectedChoice = choice;
              _message = null;
            }),
            onListen: () => _speak(choice),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        _InlineNotice(
          icon: Icons.menu_book_outlined,
          text: _showHint
              ? 'Use the sentence context and grammar to choose.'
              : 'Tap Hint to see a short strategy.',
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.center,
          child: _secondaryAction(
            icon: Icons.lightbulb_outline_rounded,
            label: 'Hint',
            onTap: () => setState(() => _showHint = true),
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 14),
          _InlineNotice(
            icon: _correct
                ? Icons.check_circle_outline_rounded
                : Icons.refresh_rounded,
            text: _message!,
            success: _correct,
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _roleplayView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: _cardDecoration(borderColor: DesignTokens.primary),
          child: Row(
            children: [
              Expanded(
                child: _roleLabel(Icons.person_outline, 'YOU', 'Learner'),
              ),
              Container(width: 1, height: 32, color: DesignTokens.hairline),
              Expanded(
                child: _roleLabel(
                  Icons.support_agent_outlined,
                  'MARIE',
                  'Partner',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        for (var i = 0; i < _completedReplies.length; i++) ...[
          _PartnerBubble(
            french: widget.lesson.steps[i].partnerFrench ?? '',
            english: widget.lesson.steps[i].partnerEnglish,
            showTranslation: _showTranslations,
            onListen: () => _speak(widget.lesson.steps[i].partnerFrench ?? ''),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _LearnerBubble(text: _completedReplies[i]),
          ),
          const SizedBox(height: 18),
        ],
        _PartnerBubble(
          french: _step.partnerFrench ?? '',
          english: _step.partnerEnglish,
          showTranslation: _showTranslations,
          onListen: () => _speak(_step.partnerFrench ?? ''),
        ),
        const SizedBox(height: 28),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: DesignTokens.primarySoft,
            borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
            border: Border.all(
              color: DesignTokens.primary.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.track_changes_rounded, color: DesignTokens.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel('YOUR GOAL'),
                    const SizedBox(height: 5),
                    Text(
                      _step.goal ?? _step.promptEnglish,
                      style: DesignTokens.body(15, weight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _controller,
          enabled: !_correct,
          minLines: 4,
          maxLines: 7,
          textCapitalization: TextCapitalization.sentences,
          style: DesignTokens.body(18),
          decoration: InputDecoration(
            hintText: 'Write a short reply in French…',
            alignLabelWithHint: true,
            contentPadding: const EdgeInsets.all(18),
          ),
          onChanged: (_) => setState(() => _message = null),
        ),
        if (!_correct && _step.suggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final suggestion in _step.suggestions)
                _WordChip(
                  label: suggestion,
                  meaning: _suggestionMeaning(suggestion),
                  showMeaning: _showTranslations,
                  enabled: true,
                  onTap: () => _insertSuggestion(suggestion),
                ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _secondaryAction(
                icon: Icons.lightbulb_outline_rounded,
                label: 'Hint',
                onTap: () => setState(() => _showHint = true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _secondaryAction(
                icon: Icons.menu_book_outlined,
                label: 'Grammar',
                onTap: () => setState(() => _showHint = true),
              ),
            ),
          ],
        ),
        if (_showHint) ...[
          const SizedBox(height: 14),
          _InlineNotice(
            icon: Icons.lightbulb_outline_rounded,
            text: _roleplayHint,
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 14),
          _InlineNotice(
            icon: _correct
                ? Icons.check_circle_outline_rounded
                : Icons.refresh_rounded,
            text: _message!,
            success: _correct,
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _bottomAction() {
    final label = _correct
        ? (_isLast
              ? 'Finish lesson'
              : _roleplayReview
              ? 'Next anyway'
              : 'Next')
        : switch (widget.lesson.mode) {
            WritingCourseMode.guided => 'Check sentence',
            WritingCourseMode.complete => 'Check answer',
            WritingCourseMode.roleplay => 'Send reply',
          };
    final enabled =
        _correct ||
        switch (widget.lesson.mode) {
          WritingCourseMode.guided => _selectedTokenIndexes.isNotEmpty,
          WritingCourseMode.complete => _selectedChoice != null,
          WritingCourseMode.roleplay => _controller.text.trim().isNotEmpty,
        };
    final primaryAction = PrimaryActionButton(
      label: label,
      onPressed: enabled ? (_correct ? _advance : _check) : null,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: DesignTokens.canvas,
        border: Border(top: BorderSide(color: DesignTokens.hairline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.lesson.mode != WritingCourseMode.guided) ...[
            _translationToggle(),
            const SizedBox(height: 8),
          ],
          if (_roleplayReview)
            Row(
              children: [
                Expanded(
                  child: _secondaryAction(
                    icon: Icons.edit_outlined,
                    label: 'Redo reply',
                    onTap: _redoRoleplay,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: primaryAction),
              ],
            )
          else
            primaryAction,
        ],
      ),
    );
  }

  Widget _translationToggle({bool fillWidth = false, bool compact = false}) =>
      Semantics(
        button: true,
        toggled: _showTranslations,
        label: _showTranslations ? 'Translations on' : 'Translations off',
        child: SizedBox(
          width: fillWidth ? double.infinity : null,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () =>
                setState(() => _showTranslations = !_showTranslations),
            icon: Icon(
              _showTranslations
                  ? Icons.translate_rounded
                  : Icons.translate_outlined,
              size: compact ? 17 : 18,
            ),
            label: Text(
              compact
                  ? 'Translate'
                  : (_showTranslations ? 'English on' : 'English off'),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 42),
              backgroundColor: _showTranslations
                  ? DesignTokens.primarySoft
                  : Colors.transparent,
              foregroundColor: _showTranslations
                  ? DesignTokens.primary
                  : DesignTokens.muted,
              side: BorderSide(
                color: _showTranslations
                    ? DesignTokens.primary
                    : DesignTokens.hairline,
              ),
              padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
              ),
              textStyle: DesignTokens.body(12, weight: FontWeight.w700),
            ),
          ),
        ),
      );

  Widget _tutorCallActions() {
    final call = _call;
    final isConnecting = call?.connecting == true;
    final isActive = call?.active == true;
    final phoneColor = isActive ? DesignTokens.success : DesignTokens.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: isActive ? 'End tutor call' : 'Talk with tutor',
          child: IconButton(
            onPressed: isConnecting ? null : _toggleCall,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: isConnecting
                ? const SizedBox.square(
                    dimension: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.phone_in_talk_rounded, size: 22),
            color: phoneColor,
            tooltip: isActive ? 'End tutor call' : 'Talk with tutor',
          ),
        ),
        if (isActive)
          Semantics(
            button: true,
            toggled: call!.muted,
            label: call.muted ? 'Unmute tutor call' : 'Mute tutor call',
            child: IconButton(
              onPressed: call.toggleMute,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(
                call.muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                size: 21,
              ),
              color: call.muted ? DesignTokens.primary : DesignTokens.muted,
              tooltip: call.muted ? 'Unmute tutor call' : 'Mute tutor call',
            ),
          ),
      ],
    );
  }

  String _speechKey(String role) => _speechKeyForStep(_index, role);

  String _speechKeyForStep(int index, String role) =>
      'writing:${widget.lesson.id}:$index:$role';

  Future<void> _prewarmLessonAudio() async {
    final items = <SpeechItem>[];
    for (var index = 0; index < widget.lesson.steps.length; index++) {
      final step = widget.lesson.steps[index];
      if (step.target.trim().isNotEmpty) {
        items.add(
          SpeechItem(
            text: step.target,
            language: 'fr-FR',
            contentItemId: _speechKeyForStep(index, 'guided-model'),
          ),
        );
      }
      if ((step.partnerFrench ?? '').trim().isNotEmpty) {
        items.add(
          SpeechItem(
            text: step.partnerFrench!,
            language: 'fr-FR',
            contentItemId: _speechKeyForStep(index, 'partner'),
          ),
        );
      }
    }
    if (items.isEmpty) return;
    try {
      await LessonSpeechService.shared.prewarmNarration(items);
    } catch (error) {
      // Prewarming is best effort. A cache miss still follows the same
      // retrying playback path when the learner taps Listen.
      debugPrint('Writing lesson audio prewarm skipped: $error');
    }
  }

  Future<void> _requestGuidedHint() async {
    if (_isHintLoading) return;
    final stepAtRequest = _step;
    final draft = _selectedTokenIndexes
        .map((index) => _wordBank[index])
        .join(' ');
    setState(() {
      _showHint = true;
      _isHintLoading = true;
      _dynamicHint = null;
    });
    try {
      final hint = await LessonAgentService.shared
          .getWritingHint(
            prompt:
                'CEFR ${widget.lesson.level}: ${stepAtRequest.promptEnglish}',
            targetWords: stepAtRequest.tokens,
            draft: draft,
            tier: 2,
          )
          .timeout(const Duration(seconds: 6));
      if (!mounted || stepAtRequest != _step) return;
      final message = hint.message.trim();
      setState(() {
        _dynamicHint = message.isEmpty ? _fallbackGuidedHint : message;
        _isHintLoading = false;
      });
    } catch (error) {
      debugPrint('Writing guided hint fallback: $error');
      if (!mounted || stepAtRequest != _step) return;
      setState(() {
        _dynamicHint = _fallbackGuidedHint;
        _isHintLoading = false;
      });
    }
  }

  String get _fallbackGuidedHint =>
      _step.tip.isEmpty ? 'Start with ${_step.tokens.first}.' : _step.tip;

  String get _liveContext =>
      '''
WRITING GUIDED LESSON
Lesson: ${widget.lesson.title}
Level: ${widget.lesson.level}
Mode: ${widget.lesson.mode.name}
Prompt: ${_step.prompt}
English meaning: ${_step.promptEnglish}
Target sentence: ${_step.target}
Selected words: ${_selectedTokenIndexes.isEmpty ? '(none)' : _selectedTokenIndexes.map((index) => _wordBank[index]).join(' ')}
Word bank: ${_wordBank.join(', ')}
The learner is building the target sentence from shuffled word chips. Explain
one word, ordering choice, or grammar point at a time. Never take over the
exercise or reveal the full answer unless the learner explicitly asks.
''';

  Future<void> _toggleCall() async {
    var call = _call;
    if (call == null) {
      try {
        final container = ProviderScope.containerOf(context, listen: false);
        _learningStore = container.read(learningStoreProvider);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tutor help is unavailable here.')),
          );
        }
        return;
      }
      call = InlineCallController(
        sessionType: LiveSessionType.writingGuide,
        lessonContext: () => _liveContext,
        learningStoreForProfile: _learningStore!,
        openingPrompt:
            'The learner is building a French sentence. Offer one short, '
            'specific explanation of the current word order, then wait.',
        onChanged: () {
          if (mounted) setState(() {});
        },
      );
      _call = call;
    }
    await call.toggle(context);
    if (mounted) setState(() {});
  }

  void _check() {
    switch (widget.lesson.mode) {
      case WritingCourseMode.guided:
        final actual = _normalise(
          _selectedTokenIndexes.map((index) => _wordBank[index]).join(' '),
        );
        final expected = _normalise(_step.target);
        setState(() {
          _correct = actual == expected;
          _message = _correct
              ? 'That sentence is in the right order.'
              : 'Not quite. Move the words and try again.';
        });
      case WritingCourseMode.complete:
        setState(() {
          _correct = _selectedChoice == _step.target;
          _message = _correct
              ? '${_step.target} completes the meaning.'
              : 'That word does not fit this context. Try another one.';
        });
      case WritingCourseMode.roleplay:
        _checkRoleplay();
    }
  }

  void _checkRoleplay() {
    final answer = _controller.text.trim();
    final communicates = _communicatesGoal(answer);
    if (!communicates) {
      setState(() {
        _message = 'Add the key information needed to complete the goal.';
      });
      return;
    }
    final close = _similarEnough(answer, _step.target, threshold: 0.72);
    setState(() {
      _correct = true;
      _roleplayReview = !close;
      _message = close
          ? 'Your reply completes the goal.'
          : 'Good message. A clearer version is: ${_step.target}';
    });
  }

  void _redoRoleplay() {
    setState(() {
      _correct = false;
      _roleplayReview = false;
      _message = null;
      _showHint = false;
      _controller.clear();
    });
  }

  bool _communicatesGoal(String answer) {
    final normalised = _normalise(answer);
    final signals = <String>{
      ..._step.suggestions,
      ..._step.target
          .split(RegExp(r'\s+'))
          .where((word) => _normalise(word).length >= 4),
    };
    return signals.any((signal) => normalised.contains(_normalise(signal)));
  }

  bool _similarEnough(
    String answer,
    String target, {
    required double threshold,
  }) {
    final answerWords = _normalise(
      answer,
    ).split(' ').where((w) => w.isNotEmpty).toSet();
    final targetWords = _normalise(
      target,
    ).split(' ').where((w) => w.isNotEmpty).toSet();
    if (targetWords.isEmpty) return answerWords.isNotEmpty;
    final matched = targetWords.where(answerWords.contains).length;
    return matched / targetWords.length >= threshold;
  }

  String _normalise(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r"[.,!?;:’']"), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String get _roleplayHint {
    final starter = _step.starter?.trim();
    if (starter == null || starter.isEmpty) return _step.tip;
    return '${_step.tip} Start with “$starter”.';
  }

  void _advance() {
    unawaited(LessonSpeechService.shared.stop());
    if (widget.lesson.mode == WritingCourseMode.roleplay) {
      _completedReplies.add(
        _controller.text.trim().isEmpty
            ? _step.target
            : _controller.text.trim(),
      );
    }
    if (_isLast) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _index++;
      _selectedTokenIndexes.clear();
      _selectedChoice = null;
      _controller.clear();
      _message = null;
      _correct = false;
      _showHint = false;
      _dynamicHint = null;
      _isHintLoading = false;
      _audioLoading = false;
      _activeAudioKey = null;
      _roleplayReview = false;
    });
    _shuffleWordBank();
    // Keep a live tutor call attached to the lesson as the learner moves
    // between cards. This is deliberately silent; the tutor uses the new
    // context only on the next learner request.
    _call?.updateLessonContext();
  }

  void _selectToken(int index) {
    if (_selectedTokenIndexes.contains(index)) return;
    setState(() {
      _selectedTokenIndexes.add(index);
      _message = null;
    });
  }

  void _removeToken(int index) {
    setState(() {
      _selectedTokenIndexes.remove(index);
      _message = null;
    });
  }

  void _shuffleWordBank() {
    _wordBankSourceIndexes = List.generate(
      _step.tokens.length,
      (index) => index,
    );
    if (_wordBankSourceIndexes.length > 1) {
      _wordBankSourceIndexes.shuffle(math.Random(_shuffleSeed));
    }
    _wordBank = [
      for (final sourceIndex in _wordBankSourceIndexes)
        _step.tokens[sourceIndex],
    ];
  }

  int get _shuffleSeed {
    var hash = 17;
    for (final codeUnit in widget.lesson.id.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash + _index;
  }

  String _meaningForToken(int shuffledIndex) {
    if (shuffledIndex < 0 || shuffledIndex >= _wordBankSourceIndexes.length) {
      return '';
    }
    final sourceIndex = _wordBankSourceIndexes[shuffledIndex];
    if (sourceIndex < 0 || sourceIndex >= _step.tokenMeanings.length) {
      return '';
    }
    return _step.tokenMeanings[sourceIndex];
  }

  String _choiceMeaning(String choice) {
    final index = _step.choices.indexOf(choice);
    if (index < 0 || index >= _step.choiceMeanings.length) return '';
    return _step.choiceMeanings[index];
  }

  String _completePromptEnglish() {
    var translation = _step.promptEnglish.trim();
    final answerMeaning = _choiceMeaning(_step.target).trim();
    if (answerMeaning.isEmpty) return translation;
    final answerPattern = RegExp(
      RegExp.escape(answerMeaning),
      caseSensitive: false,
    );
    return translation.replaceFirst(answerPattern, '___');
  }

  String _suggestionMeaning(String suggestion) {
    final index = _step.suggestions.indexOf(suggestion);
    if (index < 0 || index >= _step.suggestionMeanings.length) return '';
    return _step.suggestionMeanings[index];
  }

  void _insertSuggestion(String suggestion) {
    final existing = _controller.text.trimRight();
    final next = existing.isEmpty ? suggestion : '$existing $suggestion';
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() => _message = null);
  }

  Future<void> _speak(String text, {String? speechKey}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final key = speechKey ?? _speechKey('line-$trimmed');
    if (_audioLoading && _activeAudioKey == key) return;
    if (mounted) {
      setState(() {
        _audioLoading = true;
        _activeAudioKey = key;
      });
    }
    try {
      await LessonSpeechService.shared.speak(
        items: [
          SpeechItem(text: trimmed, language: 'fr-FR', contentItemId: key),
        ],
        onPlaybackReady: () {
          if (!mounted || _activeAudioKey != key) return;
          setState(() => _audioLoading = false);
        },
        onFinished: () {
          if (!mounted || _activeAudioKey != key) return;
          setState(() {
            _audioLoading = false;
            _activeAudioKey = null;
          });
        },
        onError: (_) {
          if (!mounted || _activeAudioKey != key) return;
          setState(() {
            _audioLoading = false;
            _activeAudioKey = null;
          });
        },
      );
    } catch (error) {
      debugPrint('Writing lesson audio playback failed: $error');
      if (mounted && _activeAudioKey == key) {
        setState(() {
          _audioLoading = false;
          _activeAudioKey = null;
        });
      }
    }
  }

  Widget _audioButton(String text, String semanticsLabel, {String? speechKey}) {
    final key = speechKey ?? _speechKey('line-$text');
    final loading = _audioLoading && _activeAudioKey == key;
    return Semantics(
      label: semanticsLabel,
      button: true,
      child: IconButton(
        onPressed: loading ? null : () => _speak(text, speechKey: key),
        tooltip: semanticsLabel,
        icon: _audioIcon(loading),
        color: DesignTokens.primary,
      ),
    );
  }

  Widget _audioIcon(bool loading) {
    if (!loading) return const Icon(Icons.volume_up_outlined);
    return SizedBox.square(
      dimension: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          Icon(Icons.volume_up_outlined, size: 13, color: DesignTokens.primary),
        ],
      ),
    );
  }

  Widget _modeLabel(String label) => Text(
    label,
    style: DesignTokens.label(
      12,
    ).copyWith(color: DesignTokens.primary, letterSpacing: 1.3),
  );

  Widget _sectionLabel(String label) => Text(
    label,
    style: DesignTokens.label(
      11,
    ).copyWith(color: DesignTokens.primary, letterSpacing: 1.2),
  );

  BoxDecoration _cardDecoration({Color? borderColor}) => BoxDecoration(
    color: DesignTokens.surface,
    borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
    border: Border.all(color: borderColor ?? DesignTokens.hairline),
    boxShadow: DesignTokens.surfaceShadow,
  );

  Widget _secondaryAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool loading = false,
  }) => SizedBox(
    height: 48,
    child: OutlinedButton.icon(
      onPressed: loading ? null : onTap,
      icon: loading
          ? SizedBox.square(
              dimension: 19,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const CircularProgressIndicator(strokeWidth: 2),
                  Icon(icon, size: 10),
                ],
              ),
            )
          : Icon(icon, size: 19),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: DesignTokens.ink,
        side: BorderSide(color: DesignTokens.hairline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
        ),
      ),
    ),
  );

  Widget _roleLabel(IconData icon, String role, String detail) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, color: DesignTokens.primary, size: 20),
      const SizedBox(width: 7),
      Flexible(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: role,
                style: DesignTokens.label(
                  11,
                ).copyWith(color: DesignTokens.primary),
              ),
              TextSpan(
                text: ' · $detail',
                style: DesignTokens.body(
                  11,
                ).copyWith(color: DesignTokens.muted),
              ),
            ],
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

class ExpandedOrWrap extends StatelessWidget {
  const ExpandedOrWrap({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    alignment: WrapAlignment.start,
    children: children,
  );
}

class _AnswerToken extends StatelessWidget {
  const _AnswerToken({required this.token, required this.onTap});

  final String token;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: DesignTokens.primarySoft,
    borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          token,
          style: DesignTokens.body(15, weight: FontWeight.w600),
        ),
      ),
    ),
  );
}

class _WordChip extends StatelessWidget {
  const _WordChip({
    required this.label,
    this.meaning = '',
    this.showMeaning = false,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String meaning;
  final bool showMeaning;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: enabled,
    label: showMeaning && meaning.isNotEmpty ? '$label ($meaning)' : label,
    child: Material(
      color: DesignTokens.surface,
      borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
            border: Border.all(color: DesignTokens.hairline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: DesignTokens.body(14, weight: FontWeight.w600).copyWith(
                  color: enabled ? DesignTokens.ink : DesignTokens.muted,
                ),
              ),
              if (showMeaning && meaning.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  '($meaning)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.body(11).copyWith(
                    color: enabled ? DesignTokens.inkSoft : DesignTokens.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    this.meaning = '',
    this.showMeaning = false,
    required this.selected,
    required this.locked,
    required this.onTap,
    required this.onListen,
  });

  final String label;
  final String meaning;
  final bool showMeaning;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? DesignTokens.primarySoft : DesignTokens.surface,
    borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
    child: InkWell(
      onTap: locked ? null : onTap,
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
          border: Border.all(
            color: selected ? DesignTokens.primary : DesignTokens.hairline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? DesignTokens.primary : DesignTokens.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: DesignTokens.body(17, weight: FontWeight.w600),
                  ),
                  if (showMeaning && meaning.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '($meaning)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.body(
                        12,
                      ).copyWith(color: DesignTokens.inkSoft),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Listen to $label',
              onPressed: onListen,
              icon: const Icon(Icons.volume_up_outlined),
              color: selected ? DesignTokens.primary : DesignTokens.muted,
            ),
          ],
        ),
      ),
    ),
  );
}

class _PartnerBubble extends StatelessWidget {
  const _PartnerBubble({
    required this.french,
    required this.onListen,
    this.english,
    this.showTranslation = false,
  });

  final String french;
  final VoidCallback onListen;
  final String? english;
  final bool showTranslation;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'MARIE',
        style: DesignTokens.label(
          11,
        ).copyWith(color: DesignTokens.primary, letterSpacing: 1.2),
      ),
      const SizedBox(height: 7),
      Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
        decoration: BoxDecoration(
          color: DesignTokens.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(5),
          ),
          border: Border.all(color: DesignTokens.hairline),
          boxShadow: DesignTokens.surfaceShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(french, style: DesignTokens.body(16)),
                  if (showTranslation && (english ?? '').isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      '($english)',
                      style: DesignTokens.body(
                        12,
                      ).copyWith(color: DesignTokens.inkSoft),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Listen to Marie',
              onPressed: onListen,
              icon: const Icon(Icons.volume_up_outlined),
              color: DesignTokens.primary,
            ),
          ],
        ),
      ),
    ],
  );
}

class _LearnerBubble extends StatelessWidget {
  const _LearnerBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 300),
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    decoration: BoxDecoration(
      color: DesignTokens.primarySoft,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(18),
        topRight: Radius.circular(18),
        bottomLeft: Radius.circular(18),
        bottomRight: Radius.circular(5),
      ),
      border: Border.all(color: DesignTokens.primary.withValues(alpha: 0.35)),
    ),
    child: Text(text, style: DesignTokens.body(15)),
  );
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.icon,
    required this.text,
    this.success = false,
  });

  final IconData icon;
  final String text;
  final bool success;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: success ? DesignTokens.successSoft : DesignTokens.primarySoft,
      borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 19,
          color: success ? DesignTokens.success : DesignTokens.primary,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: DesignTokens.body(13, weight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
