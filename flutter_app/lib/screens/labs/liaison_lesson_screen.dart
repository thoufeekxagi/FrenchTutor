import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/liaison_curriculum_catalog.dart';
import '../../design/tokens.dart';
import '../../models/session.dart';
import '../../models/tutor_persona.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/web/web_constrained_view.dart';
import '../speak/speak_ui.dart';

enum LiaisonStartMode { wordPairs, sentences, readAloud }

class LiaisonLessonScreen extends ConsumerStatefulWidget {
  const LiaisonLessonScreen({
    super.key,
    required this.lesson,
    this.startMode = LiaisonStartMode.wordPairs,
  });

  final LiaisonCurriculumLesson lesson;
  final LiaisonStartMode startMode;

  @override
  ConsumerState<LiaisonLessonScreen> createState() =>
      _LiaisonLessonScreenState();
}

class _LiaisonLessonScreenState extends ConsumerState<LiaisonLessonScreen> {
  late int _step;
  bool _showTranslation = false;
  bool _isPlaying = false;
  bool _isRecording = false;
  bool _isChecking = false;
  bool? _hearChoice;
  bool? _hearCorrect;
  LiaisonAttemptAssessment? _assessment;
  String? _error;
  final Set<int> _passedSteps = {};

  LiaisonCurriculumLesson get lesson => widget.lesson;

  @override
  void initState() {
    super.initState();
    _step = switch (widget.startMode) {
      LiaisonStartMode.wordPairs => 0,
      LiaisonStartMode.sentences => 3,
      LiaisonStartMode.readAloud => 4,
    };
    ref
        .read(learningStoreProvider)
        .setLessonStatus(lesson.progressId, 'in_progress');
  }

  @override
  void dispose() {
    unawaited(LessonSpeechService.shared.deactivate());
    super.dispose();
  }

  String get _title => switch (_step) {
    0 => 'See the link',
    1 => 'Hear the link',
    2 => 'Say the link',
    3 => 'Use it in a sentence',
    4 => 'Read it in context',
    _ => 'Liaison complete',
  };

  String get _targetText => switch (_step) {
    2 => lesson.phrase,
    3 => lesson.sentence,
    4 => lesson.passage,
    _ => lesson.phrase,
  };

  String get _targetEnglish => switch (_step) {
    3 => lesson.sentenceEnglish,
    4 => lesson.passageEnglish,
    _ => lesson.subtitle,
  };

  Future<void> _play(String text) async {
    if (_isPlaying || _isRecording || _isChecking) return;
    setState(() {
      _isPlaying = true;
      _error = null;
    });
    try {
      await LessonSpeechService.shared.speak(
        items: [
          SpeechItem(
            text: text,
            language: 'fr-FR',
            contentItemId: '${lesson.progressId}:$_step',
            voiceName: ActiveTutor.current.voiceName,
          ),
        ],
        rate: 0.36,
        onFinished: () {
          if (mounted) setState(() => _isPlaying = false);
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _isPlaying = false;
            _error = 'Audio failed: $error';
          });
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _error = 'Audio failed: $error';
      });
    }
  }

  Future<void> _toggleRecording() async {
    if (_isChecking || _isPlaying) return;
    if (_isRecording) {
      await LessonSpeechService.shared.stopListening();
      return;
    }
    setState(() {
      _isRecording = true;
      _assessment = null;
      _error = null;
    });
    await LessonSpeechService.shared.startListening(
      locale: 'fr-FR',
      onPartial: (_) {},
      onFinal: (_) {},
      onFinalWithAudio: (transcript, bytes) {
        if (!mounted) return;
        if (bytes.isEmpty) {
          setState(() {
            _isRecording = false;
            _isChecking = false;
            _error =
                'No audio was captured. Check microphone permission and try again.';
          });
          return;
        }
        setState(() {
          _isRecording = false;
          _isChecking = true;
        });
        unawaited(_checkAttempt(bytes));
      },
    );
    if (mounted && !LessonSpeechService.shared.isListening && _isRecording) {
      setState(() {
        _isRecording = false;
        _error = 'Microphone permission is required for this step.';
      });
    }
  }

  Future<void> _checkAttempt(List<int> bytes) async {
    try {
      final result = await ref
          .read(lessonAgentServiceProvider)
          .evaluateLiaisonAttempt(
            pcmBytes: bytes,
            referenceText: _targetText,
            firstWord: lesson.firstWord,
            secondWord: lesson.secondWord,
            linkSound: lesson.linkSound,
            shouldLink: lesson.expectsLink,
          );
      final passed =
          result.audioClear &&
          result.wordsMatch &&
          result.liaisonMatch &&
          result.confidence >= 0.6;
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _assessment = result;
        if (passed) _passedSteps.add(_step);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _error = 'Pronunciation check failed: $error';
      });
    }
  }

  bool get _canContinue => switch (_step) {
    0 => true,
    1 => _hearCorrect == true,
    2 || 3 || 4 => _passedSteps.contains(_step),
    _ => true,
  };

  void _next() {
    if (!_canContinue) return;
    if (_step >= 5) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _step++;
      _showTranslation = false;
      _hearChoice = null;
      _hearCorrect = null;
      _assessment = null;
      _error = null;
    });
    if (_step == 5) _finish();
  }

  void _finish() {
    final expectedChecks = switch (widget.startMode) {
      LiaisonStartMode.wordPairs => 4,
      LiaisonStartMode.sentences => 2,
      LiaisonStartMode.readAloud => 1,
    };
    final firstExpectedStep = switch (widget.startMode) {
      LiaisonStartMode.wordPairs => 1,
      LiaisonStartMode.sentences => 3,
      LiaisonStartMode.readAloud => 4,
    };
    final passedChecks = _passedSteps
        .where((step) => step >= firstExpectedStep && step <= 4)
        .length;
    final score = passedChecks / expectedChecks;
    ref
        .read(learningStoreProvider)
        .setLessonStatus(
          lesson.progressId,
          'completed',
          score: score.clamp(0, 1),
        );
    final now = DateTime.now().toUtc();
    ref
        .read(storageServiceProvider)
        .saveSession(
          Session(
            id: 'liaison_${now.microsecondsSinceEpoch}',
            startedAt: now.toIso8601String(),
            endedAt: now.toIso8601String(),
            topic: lesson.title,
            contentKey: lesson.progressId,
            stage: 'liaison',
            summary:
                'Completed ${lesson.title} (${lesson.level}) liaison practice.',
          ),
        );
  }

  void _answerHear(bool links) {
    final expected = lesson.ruleType == LiaisonRuleType.optional
        ? links
        : links == lesson.expectsLink;
    setState(() {
      _hearChoice = links;
      _hearCorrect = expected;
      if (expected) _passedSteps.add(1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = ((_step + 1) / 6).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: SpeakColors.background,
      body: SafeArea(
        child: WebConstrainedView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 20, 10),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(CupertinoIcons.xmark),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 5,
                          backgroundColor: SpeakColors.line,
                          valueColor: AlwaysStoppedAnimation(
                            SpeakColors.accent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_step + 1} of 6',
                      style: DesignTokens.label(
                        11,
                      ).copyWith(color: SpeakColors.inkSoft),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  children: [
                    Text(
                      lesson.level,
                      style: DesignTokens.label(
                        12,
                      ).copyWith(color: SpeakColors.accent),
                    ),
                    const SizedBox(height: 8),
                    Text(_title, style: DesignTokens.display(30)),
                    const SizedBox(height: 8),
                    Text(
                      lesson.title,
                      style: DesignTokens.body(
                        14,
                      ).copyWith(color: SpeakColors.inkSoft),
                    ),
                    const SizedBox(height: 24),
                    if (_step == 0) _buildExplanation(),
                    if (_step == 1) _buildHear(),
                    if (_step >= 2 && _step <= 4) _buildSpeaking(),
                    if (_step == 5) _buildReview(),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _MessageCard(
                        text: _error!,
                        color: DesignTokens.danger,
                        icon: CupertinoIcons.exclamationmark_triangle,
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                child: SpeakPrimaryButton(
                  label: _step == 5 ? 'Finish lesson' : 'Continue',
                  icon: CupertinoIcons.arrow_right,
                  onTap: _canContinue ? _next : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExplanation() {
    return SpeakCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(lesson.firstWord, style: DesignTokens.display(25)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  lesson.expectsLink ? '‿${lesson.linkSound}‿' : ' · ',
                  style: DesignTokens.display(
                    23,
                  ).copyWith(color: SpeakColors.accent),
                ),
              ),
              Flexible(
                child: Text(
                  lesson.secondWord,
                  style: DesignTokens.display(25),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            lesson.soundHint,
            textAlign: TextAlign.center,
            style: DesignTokens.body(15, weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            lesson.explanation,
            textAlign: TextAlign.center,
            style: DesignTokens.body(
              13,
            ).copyWith(color: SpeakColors.inkSoft, height: 1.45),
          ),
          const SizedBox(height: 18),
          _AudioButton(onTap: () => _play(lesson.phrase), playing: _isPlaying),
        ],
      ),
    );
  }

  Widget _buildHear() {
    final optional = lesson.ruleType == LiaisonRuleType.optional;
    return Column(
      children: [
        SpeakCard(
          child: Column(
            children: [
              Text(
                'Listen first. What happens between the words?',
                textAlign: TextAlign.center,
                style: DesignTokens.body(16, weight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              _AudioButton(
                onTap: () => _play(lesson.sentence),
                playing: _isPlaying,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ChoiceButton(
          label: optional ? 'I hear a link (optional)' : 'The words link',
          selected: _hearChoice == true,
          onTap: () => _answerHear(true),
        ),
        const SizedBox(height: 10),
        _ChoiceButton(
          label: optional ? 'They may stay separate' : 'They stay separate',
          selected: _hearChoice == false,
          onTap: () => _answerHear(false),
        ),
        if (_hearCorrect == false) ...[
          const SizedBox(height: 12),
          _MessageCard(
            text: lesson.soundHint,
            color: DesignTokens.danger,
            icon: CupertinoIcons.refresh,
          ),
        ],
      ],
    );
  }

  Widget _buildSpeaking() {
    final assessment = _assessment;
    final passed = _passedSteps.contains(_step);
    return Column(
      children: [
        SpeakCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _targetText,
                      style: DesignTokens.display(_step == 2 ? 27 : 21),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _play(_targetText),
                    icon: Icon(
                      _isPlaying
                          ? CupertinoIcons.pause_fill
                          : CupertinoIcons.speaker_2_fill,
                      color: SpeakColors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _showTranslation = !_showTranslation),
                  icon: const Icon(CupertinoIcons.textformat_alt, size: 17),
                  label: Text(
                    _showTranslation ? 'Hide meaning' : 'Show meaning',
                  ),
                ),
              ),
              if (_showTranslation)
                Text(
                  _targetEnglish,
                  style: DesignTokens.body(
                    14,
                  ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          _isChecking
              ? 'Checking the sound…'
              : _isRecording
              ? 'Listening… tap to stop'
              : passed
              ? 'Sound confirmed'
              : 'Tap, then say the line',
          style: DesignTokens.body(13, weight: FontWeight.w600).copyWith(
            color: passed ? DesignTokens.success : SpeakColors.inkSoft,
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: (_isChecking || passed) ? null : _toggleRecording,
          child: AnimatedContainer(
            duration: DesignTokens.durationFast,
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: passed ? DesignTokens.success : SpeakColors.accent,
              boxShadow: [
                BoxShadow(
                  color: (passed ? DesignTokens.success : SpeakColors.accent)
                      .withValues(alpha: 0.22),
                  blurRadius: _isRecording ? 28 : 14,
                  spreadRadius: _isRecording ? 8 : 2,
                ),
              ],
            ),
            child: Icon(
              passed
                  ? CupertinoIcons.check_mark
                  : _isRecording
                  ? CupertinoIcons.stop_fill
                  : CupertinoIcons.mic_fill,
              color: passed ? Colors.white : SpeakColors.onAccent,
              size: 36,
            ),
          ),
        ),
        if (assessment != null) ...[
          const SizedBox(height: 18),
          _MessageCard(
            text: assessment.feedback,
            color: passed ? DesignTokens.success : DesignTokens.danger,
            icon: passed
                ? CupertinoIcons.check_mark_circled_solid
                : CupertinoIcons.arrow_counterclockwise,
            detail: assessment.transcript.isEmpty
                ? null
                : 'Heard: ${assessment.transcript}',
          ),
        ],
      ],
    );
  }

  Widget _buildReview() {
    return SpeakCard(
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DesignTokens.successSoft,
            ),
            child: Icon(
              CupertinoIcons.check_mark,
              color: DesignTokens.success,
              size: 34,
            ),
          ),
          const SizedBox(height: 16),
          Text('You connected it.', style: DesignTokens.display(24)),
          const SizedBox(height: 8),
          Text(
            lesson.linkedDisplay,
            style: DesignTokens.body(
              17,
              weight: FontWeight.w700,
            ).copyWith(color: SpeakColors.accent),
          ),
          const SizedBox(height: 8),
          Text(
            lesson.explanation,
            textAlign: TextAlign.center,
            style: DesignTokens.body(
              13,
            ).copyWith(color: SpeakColors.inkSoft, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _AudioButton extends StatelessWidget {
  const _AudioButton({required this.onTap, required this.playing});

  final VoidCallback onTap;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: SpeakColors.accent,
        foregroundColor: SpeakColors.onAccent,
        minimumSize: const Size(58, 58),
      ),
      icon: Icon(
        playing ? CupertinoIcons.pause_fill : CupertinoIcons.speaker_2_fill,
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        decoration: BoxDecoration(
          color: SpeakColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? DesignTokens.success : SpeakColors.line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: DesignTokens.body(14, weight: FontWeight.w600),
              ),
            ),
            if (selected)
              Icon(CupertinoIcons.check_mark, color: DesignTokens.success),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.text,
    required this.color,
    required this.icon,
    this.detail,
  });

  final String text;
  final String? detail;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: DesignTokens.body(13, weight: FontWeight.w600),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    detail!,
                    style: DesignTokens.body(
                      12,
                    ).copyWith(color: SpeakColors.inkSoft),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
