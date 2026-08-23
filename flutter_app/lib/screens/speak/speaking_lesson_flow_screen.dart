import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../flow/stage_outcome.dart';
import '../../models/tutor_persona.dart';
import '../../services/lesson_speech_service.dart';

/// One fixed phrase in the controlled Speak-style lesson.
///
/// The French line is the source of truth. The learner is never asked to
/// guess what to say from a vague prompt: hear it, see its meaning, say it,
/// receive an inline check, and then move to the next phrase.
class SpeakingPhraseStep {
  const SpeakingPhraseStep({
    required this.french,
    required this.english,
    this.partnerFrench,
    this.partnerEnglish,
    this.tip = '',
    this.openResponse = false,
  });

  final String french;
  final String english;
  final String? partnerFrench;
  final String? partnerEnglish;
  final String tip;
  final bool openResponse;
}

enum _SpeakingStepState { ready, recording, checking, success, retry }

/// Shared controlled speaking flow used by the course lesson and quick drill.
///
/// This is intentionally a single route. The reference changes state inside
/// the same lesson surface instead of pushing a separate random result page.
class SpeakingLessonFlowScreen extends StatefulWidget {
  const SpeakingLessonFlowScreen({
    super.key,
    required this.title,
    required this.level,
    required this.steps,
    this.topic,
    this.contentKey,
    this.tutor = TutorPersona.defaultPersona,
  });

  final String title;
  final String level;
  final List<SpeakingPhraseStep> steps;
  final String? topic;
  final String? contentKey;
  final TutorPersona tutor;

  @override
  State<SpeakingLessonFlowScreen> createState() =>
      _SpeakingLessonFlowScreenState();
}

class _SpeakingLessonFlowScreenState extends State<SpeakingLessonFlowScreen> {
  final Stopwatch _sessionClock = Stopwatch();
  int _index = 0;
  int _successful = 0;
  bool _playing = false;
  bool _showMeaning = true;
  String _heard = '';
  String? _error;
  _SpeakingStepState _state = _SpeakingStepState.ready;

  SpeakingPhraseStep get _step => widget.steps[_index];

  @override
  void initState() {
    super.initState();
    _sessionClock.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playCurrentPrompt();
    });
  }

  @override
  void dispose() {
    unawaited(LessonSpeechService.shared.deactivate());
    _sessionClock.stop();
    super.dispose();
  }

  Future<void> _playPhrase() async {
    if (_playing || !mounted) return;
    setState(() {
      _playing = true;
      _error = null;
    });
    await LessonSpeechService.shared.speak(
      items: [
        SpeechItem(
          text: _step.french,
          language: 'fr-FR',
          contentItemId: widget.contentKey,
          voiceName: widget.tutor.voiceName,
        ),
      ],
      rate: 0.34,
      onPlaybackReady: () {
        if (mounted) setState(() => _playing = false);
      },
      onFinished: () {
        if (mounted) setState(() => _playing = false);
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _playing = false;
            _error = 'Audio could not be played: $error';
          });
        }
      },
    );
    if (mounted && _playing) setState(() => _playing = false);
  }

  Future<void> _startRecording() async {
    if (_state == _SpeakingStepState.checking ||
        _state == _SpeakingStepState.recording) {
      return;
    }
    if (_state == _SpeakingStepState.success) return;
    setState(() {
      _state = _SpeakingStepState.recording;
      _heard = '';
      _error = null;
    });
    await LessonSpeechService.shared.startListening(
      locale: 'fr-FR',
      onPartial: (_) {},
      onFinal: _finishRecording,
    );
  }

  Future<void> _finishRecording(String transcript) async {
    if (!mounted) return;
    setState(() {
      _state = _SpeakingStepState.checking;
      _heard = transcript.trim();
    });
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    final match = _step.openResponse
        ? _fold(_heard).split(' ').where((word) => word.isNotEmpty).length >= 2
        : _matchesTarget(_heard, _step.french);
    setState(() {
      _state = match ? _SpeakingStepState.success : _SpeakingStepState.retry;
      if (_heard.isEmpty) {
        _error =
            'No French speech was transcribed. Please try this line again.';
      }
      if (match) _successful++;
    });
  }

  Future<void> _stopRecording() async {
    if (_state != _SpeakingStepState.recording) return;
    await LessonSpeechService.shared.stopListening();
  }

  void _next() {
    if (_state != _SpeakingStepState.success) return;
    if (_index + 1 >= widget.steps.length) {
      _finishLesson();
      return;
    }
    setState(() {
      _index++;
      _state = _SpeakingStepState.ready;
      _heard = '';
      _error = null;
    });
    unawaited(_playCurrentPrompt());
  }

  Future<void> _playCurrentPrompt() =>
      _step.partnerFrench == null ? _playPhrase() : _playPartnerLine();

  void _finishLesson() {
    _sessionClock.stop();
    final seconds = _sessionClock.elapsed.inSeconds;
    Navigator.of(context).pop(
      SpeakingResult(
        connected: true,
        durationSeconds: seconds,
        learnerUtteranceCount: _successful,
        endedReason: 'guided_complete',
      ),
    );
  }

  bool _matchesTarget(String heard, String target) {
    final left = _fold(heard);
    final right = _fold(target);
    if (left.isEmpty || right.isEmpty) return false;
    if (left == right || left.contains(right) || right.contains(left)) {
      return true;
    }
    final heardWords = left.split(' ').where((word) => word.isNotEmpty).toSet();
    final targetWords = right
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toSet();
    if (targetWords.isEmpty) return false;
    final overlap = heardWords.intersection(targetWords).length;
    return overlap / targetWords.length >= 0.72;
  }

  String _fold(String value) {
    const accents = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'ç': 'c',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ÿ': 'y',
    };
    var folded = value.toLowerCase().trim();
    accents.forEach((from, to) => folded = folded.replaceAll(from, to));
    return folded
        .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  _progressBar(),
                  const SizedBox(height: 24),
                  _lessonHeading(),
                  const SizedBox(height: 18),
                  _phraseCard(),
                  const SizedBox(height: 16),
                  _coachCard(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _messageCard(_error!, DesignTokens.danger),
                  ],
                ],
              ),
            ),
            _bottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close lesson',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(
              Icons.close_rounded,
              color: DesignTokens.nightText,
            ),
          ),
          Expanded(
            child: Text(
              widget.level.toUpperCase(),
              textAlign: TextAlign.center,
              style: _label(11).copyWith(letterSpacing: 1.4),
            ),
          ),
          IconButton(
            tooltip: 'Save lesson',
            onPressed: () {},
            icon: const Icon(
              Icons.bookmark_border_rounded,
              color: DesignTokens.nightText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressBar() {
    final progress =
        (_index + (_state == _SpeakingStepState.success ? 1 : 0)) /
        widget.steps.length;
    return Column(
      children: [
        Row(
          children: [
            Text('${_index + 1} of ${widget.steps.length}', style: _label(12)),
            const Spacer(),
            Text(
              '${(_successful / widget.steps.length * 100).round()}%',
              style: _label(12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: DesignTokens.nightHairline,
            valueColor: const AlwaysStoppedAnimation(DesignTokens.nightAccent),
          ),
        ),
      ],
    );
  }

  Widget _lessonHeading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _step.partnerFrench == null ? 'GUIDED SPEAKING' : 'ROLEPLAY',
          style: _label(11).copyWith(letterSpacing: 1.5),
        ),
        const SizedBox(height: 6),
        Text(widget.title, style: _display(28)),
        const SizedBox(height: 5),
        Text(
          widget.topic ?? 'Hear it, repeat it, use it.',
          style: _body(14).copyWith(color: DesignTokens.nightMuted),
        ),
      ],
    );
  }

  Widget _phraseCard() {
    final success = _state == _SpeakingStepState.success;
    final retry = _state == _SpeakingStepState.retry;
    final border = success
        ? DesignTokens.success
        : retry
        ? DesignTokens.danger
        : DesignTokens.nightHairline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_step.partnerFrench != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 310),
              padding: const EdgeInsets.fromLTRB(15, 13, 10, 13),
              decoration: BoxDecoration(
                color: DesignTokens.nightSurfaceRaised,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(color: DesignTokens.nightHairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MARIE',
                          style: _label(
                            10,
                          ).copyWith(color: DesignTokens.nightAccent),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _step.partnerFrench!,
                          style: _body(16, weight: FontWeight.w700),
                        ),
                        if (_showMeaning &&
                            (_step.partnerEnglish?.isNotEmpty ?? false)) ...[
                          const SizedBox(height: 4),
                          Text(
                            _step.partnerEnglish!,
                            style: _body(
                              12,
                            ).copyWith(color: DesignTokens.nightMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Play Marie’s line',
                    onPressed: _playing ? null : _playPartnerLine,
                    icon: const Icon(
                      Icons.volume_up_outlined,
                      color: DesignTokens.nightText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            color: success
                ? DesignTokens.success.withValues(alpha: 0.14)
                : DesignTokens.nightSurface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: border,
              width: success || retry ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    success
                        ? Icons.check_circle_rounded
                        : Icons.format_quote_rounded,
                    color: success
                        ? DesignTokens.success
                        : DesignTokens.nightAccent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    success
                        ? 'Nice work'
                        : retry
                        ? 'Try it again'
                        : 'Speak now',
                    style: _body(13, weight: FontWeight.w800).copyWith(
                      color: success
                          ? DesignTokens.success
                          : retry
                          ? DesignTokens.danger
                          : DesignTokens.nightAccent,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Play phrase',
                    onPressed: _playing ? null : _playPhrase,
                    icon: Icon(
                      _playing
                          ? Icons.graphic_eq_rounded
                          : Icons.volume_up_outlined,
                      color: DesignTokens.nightText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(_step.french, style: _display(30).copyWith(height: 1.15)),
              if (_showMeaning) ...[
                const SizedBox(height: 12),
                Text(
                  _step.english,
                  style: _body(
                    16,
                  ).copyWith(color: DesignTokens.nightMuted, height: 1.3),
                ),
              ],
              if (_step.tip.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _step.tip,
                  style: _body(12).copyWith(color: DesignTokens.nightMuted),
                ),
              ],
              if (_heard.trim().isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(success ? 'MATCHED' : 'I HEARD', style: _label(10)),
                const SizedBox(height: 4),
                Text(
                  _heard,
                  style: _body(14, weight: FontWeight.w700).copyWith(
                    color: success
                        ? DesignTokens.success
                        : DesignTokens.nightText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _playPartnerLine() async {
    final line = _step.partnerFrench;
    if (line == null || line.trim().isEmpty || _playing || !mounted) return;
    setState(() {
      _playing = true;
      _error = null;
    });
    await LessonSpeechService.shared.speak(
      items: [
        SpeechItem(
          text: line,
          language: 'fr-FR',
          contentItemId:
              '${widget.contentKey ?? widget.title}_${_index}_partner',
          voiceName: widget.tutor.voiceName,
        ),
      ],
      rate: 0.34,
      onPlaybackReady: () {
        if (mounted) setState(() => _playing = false);
      },
      onFinished: () {
        if (mounted) setState(() => _playing = false);
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _playing = false;
            _error = 'Marie’s line could not be played: $error';
          });
        }
      },
    );
    if (mounted && _playing) setState(() => _playing = false);
  }

  Widget _coachCard() {
    final text = switch (_state) {
      _SpeakingStepState.ready =>
        'Listen once, then hold the microphone and say the phrase.',
      _SpeakingStepState.recording =>
        'Listening… release when you finish the phrase.',
      _SpeakingStepState.checking => 'Checking your words…',
      _SpeakingStepState.success =>
        'Your phrase matched. Keep going while it is fresh.',
      _SpeakingStepState.retry =>
        'The phrase was not close enough yet. Replay it and try again.',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: DesignTokens.nightSurfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.tips_and_updates_outlined,
            color: DesignTokens.nightAccent,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: _body(13).copyWith(color: DesignTokens.nightMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomControls() {
    final recording = _state == _SpeakingStepState.recording;
    final checking = _state == _SpeakingStepState.checking;
    final success = _state == _SpeakingStepState.success;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: DesignTokens.nightCanvas,
        border: Border(top: BorderSide(color: DesignTokens.nightHairline)),
      ),
      child: Row(
        children: [
          _smallControl(
            icon: _showMeaning
                ? Icons.translate_rounded
                : Icons.translate_outlined,
            label: _showMeaning ? 'Meaning on' : 'Meaning off',
            onTap: () => setState(() => _showMeaning = !_showMeaning),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: checking
                  ? null
                  : success
                  ? _next
                  : (recording ? _stopRecording : _startRecording),
              onLongPressStart: checking || success
                  ? null
                  : (_) => _startRecording(),
              onLongPressEnd: checking || success
                  ? null
                  : (_) => _stopRecording(),
              child: Container(
                height: 58,
                decoration: BoxDecoration(
                  color: success
                      ? DesignTokens.success
                      : recording
                      ? DesignTokens.danger
                      : DesignTokens.nightAccent,
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      success
                          ? Icons.check_rounded
                          : recording
                          ? Icons.stop_rounded
                          : Icons.mic_none_rounded,
                      color: Colors.black,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      success
                          ? 'Next phrase'
                          : recording
                          ? 'Release to check'
                          : 'Hold to speak',
                      style: _body(
                        14,
                        weight: FontWeight.w800,
                      ).copyWith(color: Colors.black),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _smallControl(
            icon: Icons.volume_up_outlined,
            label: 'Replay target',
            onTap: _playing ? null : _playPhrase,
          ),
        ],
      ),
    );
  }

  Widget _smallControl({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Icon(
          icon,
          color: onTap == null
              ? DesignTokens.nightHairline
              : DesignTokens.nightText,
        ),
      ),
    );
  }

  Widget _messageCard(String message, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(message, style: _body(12).copyWith(color: color)),
    );
  }

  TextStyle _display(double size) =>
      DesignTokens.display(size).copyWith(color: DesignTokens.nightText);

  TextStyle _body(double size, {FontWeight weight = FontWeight.w400}) =>
      DesignTokens.body(
        size,
        weight: weight,
      ).copyWith(color: DesignTokens.nightText);

  TextStyle _label(double size) => _body(
    size,
    weight: FontWeight.w800,
  ).copyWith(color: DesignTokens.nightMuted, letterSpacing: 0.4);
}

/// Converts a course target list into the five-step Speak-like drill. The
/// course currently stores target phrases as French only, so familiar phrases
/// receive an inline meaning and unknown targets stay honest rather than
/// inventing a translation in the client.
const _speakingMeanings = {
  'bonjour': 'Hello.',
  'je m’appelle…': 'My name is…',
  'je m\'appelle…': 'My name is…',
  'enchanté, je suis…': 'Nice to meet you, I am…',
  'où est… ?': 'Where is…?',
  'je voudrais…, s’il vous plaît.': 'I would like…, please.',
  'combien ça coûte ?': 'How much does it cost?',
  'il y a…': 'There is / there are…',
  'tu veux venir… ?': 'Do you want to come…?',
  'pouvez-vous répéter ?': 'Can you repeat, please?',
};

List<SpeakingPhraseStep> speakingStepsForTargets(
  Iterable<String> targets, {
  String level = 'A1',
}) {
  final cleaned = targets
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .take(5)
      .toList(growable: false);
  if (cleaned.isEmpty) {
    throw StateError('This speaking lesson has no target phrases.');
  }
  return _buildSpeakingSteps(
    cleaned,
    meanings: _speakingMeanings,
    level: level,
  );
}

/// Provides the authored first-course scripts for adaptive rows. Adaptive
/// rows intentionally store a compact competency rather than a rich lesson
/// payload, so the speaking surface must use an explicit script registry, not
/// invent a phrase or silently switch to another mode.
List<SpeakingPhraseStep> speakingStepsForLesson({
  required Iterable<String> targets,
  required String title,
  required String competency,
  required String level,
}) {
  final cleaned = targets
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .take(5)
      .toList(growable: false);
  if (cleaned.isNotEmpty) {
    return speakingStepsForTargets(cleaned, level: level);
  }
  final label = '$title $competency'.toLowerCase();
  final phrases = label.contains('introduce')
      ? const [
          'Bonjour, je m’appelle Alex.',
          'Je viens de Toronto.',
          'Enchanté de vous rencontrer.',
          'Et vous, vous habitez où ?',
        ]
      : label.contains('appointment')
      ? const [
          'Bonjour, je voudrais prendre rendez-vous.',
          'Je suis disponible mardi matin.',
          'Est-ce que dix heures vous convient ?',
          'Merci, à mardi.',
        ]
      : label.contains('clarification')
      ? const [
          'Pardon, pouvez-vous répéter ?',
          'Pouvez-vous parler plus lentement ?',
          'Je n’ai pas compris la dernière phrase.',
          'Merci, maintenant je comprends.',
        ]
      : label.contains('routine')
      ? const [
          'Je me lève à sept heures.',
          'Je travaille le matin.',
          'Le soir, je prépare le dîner.',
          'Le week-end, je me repose.',
        ]
      : label.contains('choice')
      ? const [
          'Je préfère cette option.',
          'C’est plus simple pour moi.',
          'Je choisis le billet aller-retour.',
          'Merci pour votre conseil.',
        ]
      : label.contains('plan')
      ? const [
          'Demain, je vais travailler.',
          'Je voudrais visiter le musée.',
          'Si j’ai le temps, je prendrai un café.',
          'On peut se retrouver à midi.',
        ]
      : label.contains('problem')
      ? const [
          'J’ai un petit problème.',
          'La porte ne ferme pas.',
          'Pouvez-vous m’aider, s’il vous plaît ?',
          'Merci beaucoup pour votre aide.',
        ]
      : label.contains('opinion')
      ? const [
          'À mon avis, c’est une bonne idée.',
          'Je préfère cette solution.',
          'Parce qu’elle est simple et pratique.',
          'Et vous, qu’en pensez-vous ?',
        ]
      : label.contains('direction')
      ? const [
          'Excusez-moi, où est la gare ?',
          'Allez tout droit, puis tournez à gauche.',
          'C’est loin d’ici ?',
          'Merci, je vais trouver.',
        ]
      : label.contains('preference')
      ? const [
          'J’aime le thé, mais je préfère le café.',
          'Je préfère une table près de la fenêtre.',
          'Qu’est-ce que vous aimez ?',
          'Nous avons les mêmes goûts.',
        ]
      : label.contains('request')
      ? const [
          'Pourriez-vous m’aider, s’il vous plaît ?',
          'J’aurais besoin d’une information.',
          'Est-ce que vous pouvez vérifier ?',
          'Merci pour votre temps.',
        ]
      : label.contains('past')
      ? const [
          'Hier, je suis allé au marché.',
          'J’ai acheté des légumes frais.',
          'Ensuite, je suis rentré chez moi.',
          'C’était une matinée agréable.',
        ]
      : label.contains('natural')
      ? const [
          'Les amis arrivent à huit heures.',
          'Nous allons écouter la liaison.',
          'Je parle lentement et clairement.',
          'Je recommence avec un rythme naturel.',
        ]
      : label.contains('connect')
      ? const [
          'Je voudrais sortir, mais il pleut.',
          'Je reste à la maison parce que je suis fatigué.',
          'Donc, je vais lire un livre.',
          'Après cela, je préparerai le dîner.',
        ]
      : null;
  if (phrases == null) {
    throw StateError('No speaking script is configured for "$title".');
  }
  return _buildSpeakingSteps(
    phrases,
    meanings: _speakingMeanings,
    level: level,
  );
}

List<SpeakingPhraseStep> _buildSpeakingSteps(
  Iterable<String> source, {
  required Map<String, String> meanings,
  required String level,
}) {
  return [
    for (final phrase in source)
      SpeakingPhraseStep(
        french: phrase,
        english:
            meanings[phrase.toLowerCase()] ??
            'Listen to the tutor, then use this phrase in the lesson.',
        tip: level.toUpperCase() == 'A1'
            ? 'Keep the rhythm clear and unhurried.'
            : '',
      ),
  ];
}
