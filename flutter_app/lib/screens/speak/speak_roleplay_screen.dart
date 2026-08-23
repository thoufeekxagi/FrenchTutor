import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../flow/stage_outcome.dart';
import '../../models/content_models.dart';
import '../../models/speak_curriculum.dart';
import '../../models/speaking_course.dart';
import '../../providers/database_provider.dart';
import '../../services/ai_session_gate.dart';
import '../../services/lesson_speech_service.dart';
import '../pathway/agent_led_listening_screen.dart';

/// Roleplay setup: context first, goal second, phrasebook before recording.
/// The setup owns one entry action and hands the lesson to the preserved
/// actor-coach transcript engine; there is no separate Immersive flow.
class SpeakRoleplayScreen extends ConsumerStatefulWidget {
  const SpeakRoleplayScreen({
    super.key,
    this.topic,
    this.scene,
    this.lesson,
    this.contentKey,
  }) : assert(topic != null || scene != null || lesson != null);

  final String? topic;
  final SpeakRoleplayScene? scene;
  final SpeakingCourseLesson? lesson;
  final String? contentKey;

  @override
  ConsumerState<SpeakRoleplayScreen> createState() =>
      _SpeakRoleplayScreenState();
}

class _SpeakRoleplayScreenState extends ConsumerState<SpeakRoleplayScreen> {
  SpeakRoleplayScene get _resolvedScene =>
      widget.scene ??
      SpeakRoleplayScene(
        id:
            widget.lesson?.id ??
            'roleplay_${widget.topic!.toLowerCase().replaceAll(' ', '_')}',
        level: widget.lesson?.level ?? 'A1',
        title: widget.lesson?.title ?? widget.topic!,
        subtitle:
            widget.lesson?.subtitle ??
            'A focused conversation for a real-life moment.',
        location: 'A place you choose',
        learnerRole: 'yourself',
        tutorRole: 'conversation partner',
        goal: widget.lesson?.goal.isNotEmpty == true
            ? widget.lesson!.goal
            : 'complete the exchange one line at a time',
        openingLine:
            widget.lesson?.lines.first.partnerFrench ??
            'Bonjour, comment puis-je vous aider ?',
        targetPhrases:
            widget.lesson?.lines
                .map((line) => line.french)
                .toList(growable: false) ??
            const ['Pouvez-vous répéter ?', 'Je voudrais…'],
      );

  @override
  void dispose() {
    LessonSpeechService.shared.deactivate();
    super.dispose();
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final currentScene = _resolvedScene;
    if (!await ensureAiSessionQuota(
          context,
          ref.read(pilotAccessServiceProvider),
        ) ||
        !mounted) {
      return;
    }
    await LessonSpeechService.shared.deactivate();
    if (!mounted || !context.mounted) return;
    final passage = _passageFor(currentScene);
    final outcome = await AppRouter.push<StageOutcome<ListeningStageResult>>(
      context,
      (_) => AgentLedListeningScreen(
        passage: passage,
        noteContext: 'Roleplay',
        sessionStage: 'roleplay',
        sessionTopic: currentScene.title,
      ),
      fullscreenDialog: true,
    );
    if (!mounted || !context.mounted) return;
    Navigator.of(context).pop(
      SpeakingResult(
        connected: outcome != null,
        durationSeconds: outcome?.isCompleted == true ? 30 : 0,
        learnerUtteranceCount: outcome?.isCompleted == true
            ? passage.segments.length
            : 0,
        endedReason: outcome?.isCompleted == true
            ? 'roleplay_complete'
            : 'roleplay_cancelled',
      ),
    );
  }

  ReadingPassage _passageFor(SpeakRoleplayScene scene) {
    final authored = widget.lesson?.lines;
    final segments = authored != null && authored.isNotEmpty
        ? [
            for (final line in authored)
              ReadingSegment(
                fr: line.french,
                en: line.english,
                characterFr: line.partnerFrench,
                characterEn: line.partnerEnglish,
                grammarNote: '',
                pronunciationTip: line.tip,
              ),
          ]
        : [
            for (var index = 0; index < scene.targetPhrases.length; index++)
              ReadingSegment(
                fr: scene.targetPhrases[index],
                en: '',
                characterFr: index == 0 ? scene.openingLine : null,
                grammarNote: '',
                pronunciationTip: '',
              ),
          ];
    if (segments.isEmpty) {
      throw StateError('This roleplay has no learner lines to practise.');
    }
    return ReadingPassage(
      id: widget.contentKey ?? scene.id,
      title: scene.title,
      titleEn: scene.title,
      segments: segments,
      fullText: segments.map((segment) => segment.fr).join(' '),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scene = _resolvedScene;
    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: DesignTokens.nightText,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Save roleplay',
                    onPressed: () {},
                    icon: const Icon(
                      Icons.favorite_border_rounded,
                      color: DesignTokens.nightText,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                children: [
                  _sceneHero(scene),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Text('ROLEPLAY', style: _label('')),
                      const Spacer(),
                      Text(scene.level, style: _label('')),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(scene.title, style: _display(29)),
                  const SizedBox(height: 5),
                  Text(
                    scene.subtitle,
                    style: _body(14).copyWith(color: DesignTokens.nightMuted),
                  ),
                  const SizedBox(height: 22),
                  Text('YOUR GOAL', style: _label('')),
                  const SizedBox(height: 9),
                  _panel(
                    icon: Icons.flag_outlined,
                    title: scene.goal,
                    subtitle:
                        'The tutor keeps the scene moving at ${scene.level} level.',
                  ),
                  const SizedBox(height: 20),
                  Text('IN THIS ROLEPLAY', style: _label('')),
                  const SizedBox(height: 9),
                  _panel(
                    icon: Icons.person_outline_rounded,
                    title: 'You',
                    subtitle: scene.learnerRole,
                  ),
                  const SizedBox(height: 8),
                  _panel(
                    icon: Icons.record_voice_over_outlined,
                    title: 'Tutor',
                    subtitle: scene.tutorRole,
                  ),
                  const SizedBox(height: 20),
                  Text('PHRASEBOOK', style: _label('')),
                  const SizedBox(height: 9),
                  _phrasebook(scene),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: GestureDetector(
                onTap: () => _start(context, ref),
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: DesignTokens.nightAccent,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Text(
                    'Start roleplay  →',
                    style: _body(
                      15,
                      weight: FontWeight.w800,
                    ).copyWith(color: Colors.black),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sceneHero(SpeakRoleplayScene scene) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7D5423), Color(0xFF282015)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 20,
            top: 16,
            child: Icon(_sceneIcon(scene), color: Colors.white24, size: 92),
          ),
          Positioned(
            left: 18,
            bottom: 18,
            child: Text(
              scene.location.toUpperCase(),
              style: _body(
                11,
                weight: FontWeight.w800,
              ).copyWith(color: Colors.white70, letterSpacing: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: Row(
        children: [
          Icon(icon, color: DesignTokens.nightAccent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _body(14, weight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: _body(12).copyWith(color: DesignTokens.nightMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _phrasebook(SpeakRoleplayScene scene) {
    final phrases = [
      scene.openingLine,
      ...scene.targetPhrases,
    ].where((phrase) => phrase.trim().isNotEmpty).take(4);
    return Container(
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: Column(
        children: [
          for (final phrase in phrases)
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.format_quote_rounded,
                color: DesignTokens.nightAccent,
              ),
              title: Text(phrase, style: _body(13, weight: FontWeight.w700)),
              trailing: IconButton(
                tooltip: 'Play phrase',
                onPressed: () => LessonSpeechService.shared.speak(
                  items: [
                    SpeechItem(
                      text: phrase,
                      language: 'fr-FR',
                      contentItemId: scene.id,
                    ),
                  ],
                  rate: 0.34,
                ),
                icon: const Icon(
                  Icons.volume_up_outlined,
                  color: DesignTokens.nightText,
                  size: 19,
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _sceneIcon(SpeakRoleplayScene scene) {
    final text = '${scene.title} ${scene.location}'.toLowerCase();
    if (text.contains('café') || text.contains('coffee')) {
      return Icons.local_cafe_rounded;
    }
    if (text.contains('train') || text.contains('gare')) {
      return Icons.train_rounded;
    }
    if (text.contains('shop') || text.contains('store')) {
      return Icons.storefront_rounded;
    }
    if (text.contains('restaurant')) return Icons.restaurant_rounded;
    if (text.contains('airport')) return Icons.flight_takeoff_rounded;
    return Icons.forum_rounded;
  }

  TextStyle _display(double size) =>
      DesignTokens.display(size).copyWith(color: DesignTokens.nightText);

  TextStyle _body(double size, {FontWeight weight = FontWeight.w400}) =>
      DesignTokens.body(
        size,
        weight: weight,
      ).copyWith(color: DesignTokens.nightText);

  TextStyle _label(String label) => _body(
    11,
    weight: FontWeight.w800,
  ).copyWith(color: DesignTokens.nightAccent, letterSpacing: 1.4);
}
