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
import '../../widgets/grammar_live_audio_button.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/inline_call_bar.dart';
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
  bool _showTranslations = false;
  bool _roleplayReview = false;
  bool _isHintLoading = false;
  String? _dynamicHint;
  InlineCallController? _call;
  LearningStore? _learningStore;

  WritingCourseStep get _step => widget.lesson.steps[_index];
  bool get _isLast => _index == widget.lesson.steps.length - 1;
  bool get _isBeginner {
    final level = widget.lesson.level.trim().toUpperCase();
    return level == 'A1' || level == 'A2';
  }

  @override
  void initState() {
    super.initState();
    _shuffleWordBank();
    WidgetsBinding.instance.addObserver(this);
    // The writing lesson owns one Live socket, using the same screen-aware
    // opening and step hand-off as Grammar. Marie explains the current card,
    // then stays quiet until the learner asks for help or checks an answer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Course Writing uses one compact Live connection for its two supported
      // formats. Roleplay is not a Course format and therefore never opens a
      // tutor socket here.
      if (widget.lesson.mode == WritingCourseMode.roleplay) return;
      try {
        final call = _ensureCall();
        unawaited(call.start(context, sendOpeningPrompt: true));
      } catch (error) {
        // Widget tests and a few embedded surfaces do not provide the database
        // container. The card remains usable; a real course route gets the
        // provider-backed Live connection above.
        debugPrint('Writing Live tutor unavailable: $error');
      }
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
                    widget.lesson.displayTitle,
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
        _liveConnectionCard(),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Arrange the French words',
                style: DesignTokens.display(27),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _guidedAnswerTray(),
        if (_correct) ...[const SizedBox(height: 14), _correctSentenceCard()],
        const SizedBox(height: 22),
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
        if (_showTranslations) ...[
          const SizedBox(height: 14),
          _translationPanel(),
        ],
        const SizedBox(height: 14),
        Text(
          'Tap each word in the right order.',
          style: DesignTokens.body(13).copyWith(color: DesignTokens.muted),
        ),
        const SizedBox(height: 24),
        _guidedControls(),
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
          ],
        ),
      ),
    );
  }

  Widget _liveConnectionCard() {
    final call = _call;
    if (call == null) return const SizedBox.shrink();
    return InlineTutorConnectionCard(controller: call, onTap: _toggleCall);
  }

  Widget _guidedControls() {
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
      ),
      side: const BorderSide(color: Colors.transparent),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _iconAction(
          icon: Icons.lightbulb_outline_rounded,
          label: _isHintLoading ? 'Loading hint' : 'Hint',
          active: _showHint,
          onTap: _requestGuidedHint,
          style: buttonStyle,
        ),
        const SizedBox(width: 10),
        _iconAction(
          icon: _showTranslations
              ? Icons.translate_rounded
              : Icons.translate_outlined,
          label: _showTranslations ? 'Hide translations' : 'Show translations',
          active: _showTranslations,
          onTap: _toggleTranslations,
          style: buttonStyle,
        ),
        const SizedBox(width: 10),
        _iconAction(
          icon: Icons.volume_up_rounded,
          label: 'Hear the correct French sentence',
          active: false,
          onTap: _repeatVisibleSentence,
          style: buttonStyle,
        ),
      ],
    );
  }

  Widget _completeControls() {
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
      ),
      side: const BorderSide(color: Colors.transparent),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _iconAction(
          icon: Icons.lightbulb_outline_rounded,
          label: 'Hint',
          active: _showHint,
          onTap: () {
            setState(() => _showHint = true);
            _syncTutorContext();
          },
          style: buttonStyle,
        ),
        const SizedBox(width: 10),
        _iconAction(
          icon: _showTranslations
              ? Icons.translate_rounded
              : Icons.translate_outlined,
          label: _showTranslations ? 'Hide translations' : 'Show translations',
          active: _showTranslations,
          onTap: _toggleTranslations,
          style: buttonStyle,
        ),
        const SizedBox(width: 10),
        _iconAction(
          icon: Icons.volume_up_rounded,
          label: 'Hear the current French sentence',
          active: false,
          onTap: _repeatVisibleSentence,
          style: buttonStyle,
        ),
      ],
    );
  }

  Widget _iconAction({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    required ButtonStyle style,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox.square(
        dimension: 48,
        child: OutlinedButton(
          onPressed: _isHintLoading && label == 'Loading hint' ? null : onTap,
          style: style.copyWith(
            backgroundColor: WidgetStatePropertyAll(
              active ? DesignTokens.primarySoft : DesignTokens.surface,
            ),
            foregroundColor: WidgetStatePropertyAll(
              active ? DesignTokens.primary : DesignTokens.muted,
            ),
            side: WidgetStatePropertyAll(
              BorderSide(
                color: active ? DesignTokens.primary : DesignTokens.hairline,
              ),
            ),
          ),
          child: _isHintLoading && label == 'Loading hint'
              ? const SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, size: 20),
        ),
      ),
    );
  }

  Widget _translationPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: DesignTokens.canvasDim,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('TRANSLATIONS'),
          const SizedBox(height: 8),
          for (var index = 0; index < _wordBank.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _wordBank[index],
                      style: DesignTokens.body(14, weight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _meaningForToken(index),
                      style: DesignTokens.body(
                        14,
                      ).copyWith(color: DesignTokens.inkSoft),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _correctSentenceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      decoration: BoxDecoration(
        color: DesignTokens.successSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DesignTokens.success.withValues(alpha: 0.65)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: DesignTokens.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _step.target,
              style: DesignTokens.body(18, weight: FontWeight.w700),
            ),
          ),
          GrammarLiveAudioButton(
            controller: _call,
            text: _step.target,
            size: 42,
          ),
        ],
      ),
    );
  }

  Widget _completeView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _liveConnectionCard(),
        const SizedBox(height: 18),
        _modeLabel('COMPLETE'),
        const SizedBox(height: 12),
        Text('Choose the best word', style: DesignTokens.display(31)),
        if ((_step.partnerFrench ?? '').isNotEmpty) ...[
          const SizedBox(height: 24),
          _PartnerBubble(
            french: _step.partnerFrench!,
            english: _step.partnerEnglish,
            englishFirst: _isBeginner,
            showTranslation: _showTranslations,
            onListen: () => _repeatSentenceWithLive(_step.partnerFrench!),
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
            onTap: () => _selectChoice(choice),
            onListen: () => _repeatWordWithLive(choice),
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
        _completeControls(),
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
            englishFirst: _isBeginner,
            showTranslation: _showTranslations,
            onListen: () => _repeatSentenceWithLive(
              widget.lesson.steps[i].partnerFrench ?? '',
            ),
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
          englishFirst: _isBeginner,
          showTranslation: _showTranslations,
          onListen: () => _repeatSentenceWithLive(_step.partnerFrench ?? ''),
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
                onTap: () {
                  setState(() => _showHint = true);
                  _syncTutorContext();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _secondaryAction(
                icon: Icons.menu_book_outlined,
                label: 'Grammar',
                onTap: () {
                  setState(() => _showHint = true);
                  _syncTutorContext();
                },
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
          if (widget.lesson.mode == WritingCourseMode.roleplay) ...[
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
            onPressed: _toggleTranslations,
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

  Future<void> _requestGuidedHint() async {
    if (_isHintLoading) return;
    final stepAtRequest = _step;
    // An arrange card has an authored, validated answer already. Show that
    // exact order immediately instead of asking the text model for a vague
    // strategy ("arrange the words") that does not help a learner who is
    // explicitly asking for the answer. The generated lesson's target and
    // token meanings are the source of truth, so this cannot hallucinate a
    // different sentence or introduce a second network request.
    if (widget.lesson.mode == WritingCourseMode.guided) {
      setState(() {
        _showHint = true;
        _isHintLoading = false;
        _dynamicHint = _guidedAnswerHint(stepAtRequest);
      });
      _syncTutorContext();
      return;
    }
    final draft = _selectedTokenIndexes
        .map((index) => _wordBank[index])
        .join(' ');
    setState(() {
      _showHint = true;
      _isHintLoading = true;
      _dynamicHint = null;
    });
    _syncTutorContext();
    // Beginner hints stay local and English-only. This keeps A1/A2 guidance
    // immediate and prevents an occasional French model hint from leaking
    // into the beginner exercise.
    if (_isBeginner) {
      if (!mounted || stepAtRequest != _step) return;
      setState(() {
        _dynamicHint = _fallbackGuidedHint;
        _isHintLoading = false;
      });
      _syncTutorContext();
      return;
    }
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
      _syncTutorContext();
    } catch (error) {
      debugPrint('Writing guided hint fallback: $error');
      if (!mounted || stepAtRequest != _step) return;
      setState(() {
        _dynamicHint = _fallbackGuidedHint;
        _isHintLoading = false;
      });
      _syncTutorContext();
    }
  }

  String get _fallbackGuidedHint => _isBeginner
      ? _guidedAnswerHint(_step)
      : (_step.tip.isEmpty ? 'Start with ${_step.tokens.first}.' : _step.tip);

  String _guidedAnswerHint(WritingCourseStep step) {
    final answerLines = <String>[];
    for (var index = 0; index < step.tokens.length; index++) {
      final token = step.tokens[index].trim();
      if (token.isEmpty) continue;
      final meaning = index < step.tokenMeanings.length
          ? step.tokenMeanings[index].trim()
          : '';
      answerLines.add(meaning.isEmpty ? token : '$token — $meaning');
    }
    final answer = step.target.trim().isEmpty
        ? step.tokens.join(' ').trim()
        : step.target.trim();
    if (answerLines.isEmpty) return 'Answer: $answer';
    return 'Answer order:\n${answerLines.join('\n')}\n\nComplete sentence: $answer';
  }

  /// The Live tutor receives the same replacement snapshot contract as
  /// Grammar. Only data currently visible in the writing card is authoritative;
  /// the target stays masked until the app reports a correct answer or the
  /// learner explicitly opens the answer hint.
  String get _liveContext {
    final visibleBank = _wordBank.isEmpty ? '(none)' : _wordBank.join(' | ');
    final visibleBankMeanings = !_showTranslations
        ? '(hidden because Translate is off)'
        : _wordBank.isEmpty
        ? '(none)'
        : [
            for (var index = 0; index < _wordBank.length; index++)
              '${_wordBank[index]} = ${_meaningForToken(index)}',
          ].join(' | ');
    final selected = _selectedTokenIndexes.isEmpty
        ? '(empty)'
        : _selectedTokenIndexes.map((index) => _wordBank[index]).join(' ');
    final choices = _step.choices.isEmpty
        ? '(none)'
        : _step.choices.join(' | ');
    final choiceMeanings = _step.choiceMeanings.isEmpty
        ? '(none)'
        : _step.choiceMeanings.join(' | ');
    final result = _message == null
        ? 'not checked'
        : (_correct ? 'correct' : 'incorrect');
    final answerVisible =
        _correct ||
        (widget.lesson.mode == WritingCourseMode.guided && _showHint);
    final targetForCoach = answerVisible
        ? _step.target
        : '(hidden until the learner answers correctly; never infer or say it)';
    final visibleMeaning =
        _showTranslations && widget.lesson.mode == WritingCourseMode.complete
        ? _answerSafeEnglishMeaning()
        : '(not shown on this writing card)';
    final visibleHint = _showHint
        ? (_dynamicHint ??
              (widget.lesson.mode == WritingCourseMode.roleplay
                  ? _roleplayHint
                  : _fallbackGuidedHint))
        : null;
    final privateAnswerKey = widget.lesson.mode == WritingCourseMode.guided
        ? '\nPRIVATE ANSWER KEY (do not volunteer; use only when the learner '
              'explicitly asks for the answer): ${_guidedAnswerHint(_step)}'
        : '';
    final roleplayDetails = widget.lesson.mode == WritingCourseMode.roleplay
        ? '''
VISIBLE PARTNER FRENCH: ${_step.partnerFrench ?? '(none)'}
VISIBLE PARTNER ENGLISH: ${_showTranslations ? (_step.partnerEnglish ?? '(none)') : '(hidden because Translate is off)'}
VISIBLE LEARNER GOAL: ${_step.goal ?? _step.promptEnglish}
CURRENT DRAFT: ${_controller.text.trim().isEmpty ? '(empty)' : _controller.text.trim()}
'''
        : '';

    return '''
WRITING SESSION: ${widget.lesson.displayTitle}
LEVEL: ${widget.lesson.level}
MODE: ${widget.lesson.mode.name}

CURRENT SCREEN SNAPSHOT — this replaces every older step completely.
STEP: ${_index + 1} of ${widget.lesson.steps.length}
VISIBLE TASK: ${widget.lesson.mode == WritingCourseMode.guided
        ? 'Arrange the visible French words in the correct order.'
        : widget.lesson.mode == WritingCourseMode.complete
        ? 'Choose the visible French form that completes the blank.'
        : 'Write a short French reply for the visible goal.'}
VISIBLE FRENCH PROMPT: ${widget.lesson.mode == WritingCourseMode.roleplay ? (_step.partnerFrench ?? '(none)') : _step.prompt}
VISIBLE ENGLISH MEANING: $visibleMeaning
VISIBLE WORD BANK: $visibleBank
VISIBLE WORD BANK MEANINGS (display order): $visibleBankMeanings
VISIBLE OPTIONS: $choices
VISIBLE OPTION MEANINGS: $choiceMeanings
CURRENT ANSWER / SELECTION: ${widget.lesson.mode == WritingCourseMode.guided ? selected : (_selectedChoice ?? '(none)')}
VISIBLE COMPLETED TARGET: $targetForCoach
CHECK RESULT: $result
TRANSLATION VISIBLE: $_showTranslations
HINT VISIBLE: $_showHint${visibleHint == null ? '' : '\nVISIBLE HINT: $visibleHint'}
$privateAnswerKey
$roleplayDetails
SCOPE RULES:
- Explain and guide only this current screen snapshot. Ignore every previous
  and future step; never preview or mention one.
- Do not invent a sentence, answer, option, or example that is not visible.
- Before CHECK RESULT is correct, never say, spell, translate, or assemble the
  missing French target unless the app has explicitly revealed it in VISIBLE
  HINT or the learner directly asks for the answer. When VISIBLE HINT contains
  the answer, or the learner asks for it, repeat only the exact private answer
  key and its displayed meanings. The visible word bank/options are choices,
  not an answer to volunteer.
- The app owns selection, checking, retry, and next. Never advance the lesson
  or tell the learner to skip ahead.
- Keep help brief: one short explanation of the task, then ask the learner to
  choose or arrange. After a wrong answer, give only a clue; do not reveal it.
''';
  }

  String _openingPrompt() =>
      '''
APP OPENING — describe the writing card that is actually on screen.
CURRENT TASK: ${widget.lesson.mode == WritingCourseMode.guided
          ? 'Arrange the visible French words in the correct order.'
          : widget.lesson.mode == WritingCourseMode.complete
          ? 'Choose the French form that completes the visible blank.'
          : 'Write a short French reply for the visible goal.'}
VISIBLE FRENCH PROMPT: ${widget.lesson.mode == WritingCourseMode.roleplay ? (_step.partnerFrench ?? '(none)') : _step.prompt}
VISIBLE ENGLISH MEANING: ${_showTranslations ? _answerSafeEnglishMeaning() : '(hidden because Translate is off)'}
VISIBLE WORD BANK: ${_wordBank.isEmpty ? '(none)' : _wordBank.join(', ')}
VISIBLE WORD BANK MEANINGS: ${_showTranslations ? _visibleWordBankMeaningsForPrompt : '(hidden because Translate is off)'}
VISIBLE OPTIONS: ${_step.choices.isEmpty ? '(none)' : _step.choices.join(', ')}
Say at most two short English sentences. Explain this exact task and the
visible blank/options or word bank, then ask the learner to choose or arrange.
Never fill the blank, assemble the answer, identify the correct option, or
repeat the hidden target. Then wait.
''';

  String _stepChangePrompt() =>
      '''
APP SCREEN CHANGED — explain only the new writing card.
STEP: ${_index + 1} of ${widget.lesson.steps.length}
TASK: ${widget.lesson.mode == WritingCourseMode.guided
          ? 'Arrange the visible French words.'
          : widget.lesson.mode == WritingCourseMode.complete
          ? 'Choose the French form that completes the blank.'
          : 'Write a short French reply for the goal.'}
VISIBLE FRENCH PROMPT: ${widget.lesson.mode == WritingCourseMode.roleplay ? (_step.partnerFrench ?? '(none)') : _step.prompt}
VISIBLE ENGLISH MEANING: ${_showTranslations ? _answerSafeEnglishMeaning() : '(hidden because Translate is off)'}
VISIBLE WORD BANK: ${_wordBank.isEmpty ? '(none)' : _wordBank.join(', ')}
VISIBLE WORD BANK MEANINGS: ${_showTranslations ? _visibleWordBankMeaningsForPrompt : '(hidden because Translate is off)'}
VISIBLE OPTIONS: ${_step.choices.isEmpty ? '(none)' : _step.choices.join(', ')}
Use at most two short English sentences: explain this exact task, mention the
visible choices without identifying the answer, and ask the learner to act.
Preserve the blank and wait. Do not mention the previous step.
''';

  String _answerSafeEnglishMeaning() {
    var meaning = _step.promptEnglish.trim();
    if (meaning.isEmpty) return '(no English meaning supplied)';
    final hidden = <String>{_step.target, ..._step.choices};
    for (final candidate in hidden) {
      final value = candidate.trim();
      if (value.length < 3) continue;
      meaning = meaning.replaceAll(
        RegExp(
          r'(?<![A-Za-zÀ-ÿ])' + RegExp.escape(value) + r'(?![A-Za-zÀ-ÿ])',
          caseSensitive: false,
        ),
        '[missing French form]',
      );
    }
    return meaning;
  }

  String get _visibleWordBankMeaningsForPrompt => [
    for (var index = 0; index < _wordBank.length; index++)
      '${_wordBank[index]} = ${_meaningForToken(index)}',
  ].join(', ');

  void _syncTutorContext() {
    final call = _call;
    if (call == null || !call.isLive) return;
    call.updateLessonContext();
  }

  InlineCallController _ensureCall() {
    final existing = _call;
    if (existing != null) return existing;
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      _learningStore = container.read(learningStoreProvider);
    } catch (_) {
      throw StateError('Tutor help is unavailable here.');
    }
    final created = InlineCallController(
      sessionType: LiveSessionType.writingGuide,
      lessonContext: () => _liveContext,
      learningStoreForProfile: _learningStore!,
      compactGuidedContext: true,
      openingPrompt: _openingPrompt(),
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    _call = created;
    return created;
  }

  Future<void> _toggleCall() async {
    try {
      final call = _ensureCall();
      await call.toggle(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    }
    if (mounted) setState(() {});
  }

  void _toggleTranslations() {
    setState(() => _showTranslations = !_showTranslations);
    _syncTutorContext();
  }

  Future<void> _repeatCurrentSentence() async {
    await _repeatWithLive(
      _step.target,
      'Say the current French target sentence exactly once',
    );
  }

  Future<void> _repeatVisibleSentence() async {
    if (widget.lesson.mode == WritingCourseMode.complete) {
      final sentence = _step.prompt.replaceFirst('___', _step.target).trim();
      await _repeatSentenceWithLive(sentence);
      return;
    }
    await _repeatCurrentSentence();
  }

  Future<void> _repeatSentenceWithLive(String sentence) async {
    await _repeatWithLive(
      sentence,
      'Say this current French sentence exactly once',
    );
  }

  Future<void> _repeatWordWithLive(String word) async {
    await _repeatWithLive(word, 'Say only this exact French word once');
  }

  Future<void> _repeatWithLive(String text, String instruction) async {
    try {
      final call = _ensureCall();
      if (!call.active) {
        await call.start(context, sendOpeningPrompt: false);
      }
      if (!call.active) return;
      call.promptTutor(
        'APP COMMAND: $instruction: $text. Do not explain it, translate it, '
        'or add anything. Then stop and wait.',
      );
    } catch (error) {
      debugPrint('Writing Live sentence repeat failed: $error');
    }
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
        _syncTutorContext();
        _promptCheckFeedback();
      case WritingCourseMode.complete:
        setState(() {
          _correct = _selectedChoice == _step.target;
          _message = _correct
              ? '${_step.target} completes the meaning.'
              : 'That word does not fit this context. Try another one.';
        });
        _syncTutorContext();
        _promptCheckFeedback();
      case WritingCourseMode.roleplay:
        _checkRoleplay();
    }
  }

  void _promptCheckFeedback() {
    final call = _call;
    if (call == null || !call.isLive) return;
    if (_correct) {
      final sentence = _completedFrenchSentence();
      call.promptTutor('''
APP FEEDBACK — the app already checked the learner's visible answer.
Say only this short English line: "Correct. The complete French sentence is:
$sentence" Then wait. Do not add a reason, lecture, question, or translation.
''');
      return;
    }
    final clue = widget.lesson.mode == WritingCourseMode.guided
        ? 'Check the word order and the sentence meaning, then arrange the words again.'
        : 'Check the subject and the tense against the visible sentence meaning, then choose again.';
    call.promptTutor('''
APP FEEDBACK — the app marked the visible answer incorrect.
Say only this short English clue: "$clue" Then wait. Never reveal, spell,
translate, or assemble the missing French form.
''');
  }

  String _completedFrenchSentence() {
    final prompt = _step.prompt.trim();
    if (prompt.contains('___')) {
      return prompt.replaceFirst('___', _step.target).trim();
    }
    if (widget.lesson.mode == WritingCourseMode.guided) return _step.target;
    return prompt.isEmpty ? _step.target : prompt;
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
    _syncTutorContext();
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
    _call?.suppressCurrentReply();
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
      _roleplayReview = false;
    });
    _shuffleWordBank();
    // Replace the old snapshot before speaking so a queued reply can never
    // describe the previous card.
    _syncTutorContext();
    _call?.promptTutor(_stepChangePrompt());
  }

  void _selectToken(int index) {
    if (_selectedTokenIndexes.contains(index)) return;
    setState(() {
      _selectedTokenIndexes.add(index);
      _message = null;
    });
    _syncTutorContext();
  }

  void _removeToken(int index) {
    setState(() {
      _selectedTokenIndexes.remove(index);
      _message = null;
    });
    _syncTutorContext();
  }

  void _selectChoice(String choice) {
    if (_correct) return;
    setState(() {
      _selectedChoice = choice;
      _message = null;
    });
    _syncTutorContext();
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
    _syncTutorContext();
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(
            token,
            softWrap: true,
            style: DesignTokens.body(15, weight: FontWeight.w600),
          ),
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
          constraints: BoxConstraints(
            minHeight: 48,
            maxWidth: MediaQuery.sizeOf(context).width * 0.46,
          ),
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
                softWrap: true,
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
    this.englishFirst = false,
    this.showTranslation = false,
  });

  final String french;
  final VoidCallback onListen;
  final String? english;
  final bool englishFirst;
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
                  if (englishFirst &&
                      showTranslation &&
                      (english ?? '').isNotEmpty)
                    Text(english!, style: DesignTokens.body(16))
                  else
                    Text(french, style: DesignTokens.body(16)),
                  if (showTranslation && (english ?? '').isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      englishFirst ? '($french)' : '($english)',
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
