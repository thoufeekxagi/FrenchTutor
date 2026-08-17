import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_keys.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/speak_curriculum.dart';
import '../../providers/database_provider.dart';
import '../../services/ai_session_gate.dart';
import '../../services/lesson_speech_service.dart';
import '../session/session_screen.dart';
import 'speak_ui.dart';

class SpeakRoleplayScreen extends ConsumerWidget {
  const SpeakRoleplayScreen({
    super.key,
    this.topic,
    this.scene,
    this.contentKey,
  }) : assert(topic != null || scene != null);

  final String? topic;
  final SpeakRoleplayScene? scene;
  final String? contentKey;

  SpeakRoleplayScene get _resolvedScene =>
      scene ??
      SpeakRoleplayScene(
        id: 'free_talk_${topic!.toLowerCase().replaceAll(' ', '_')}',
        level: 'A1',
        title: topic!,
        subtitle: 'A focused conversation for a real-life moment.',
        location: 'A place you choose',
        learnerRole: 'yourself',
        tutorRole: 'conversation partner',
        goal: 'keep the conversation moving naturally',
        openingLine: 'Bonjour, comment puis-je vous aider ?',
        targetPhrases: const ['Pouvez-vous répéter ?', 'Je voudrais…'],
      );

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final currentScene = _resolvedScene;
    if (!await ensureAiSessionQuota(
          context,
          ref.read(pilotAccessServiceProvider),
        ) ||
        !context.mounted) {
      return;
    }
    LessonSpeechService.shared.deactivate();
    await AppRouter.push(
      context,
      (_) => SessionScreen(
        apiKey: ApiKeys.geminiKey,
        stage: 'speaking',
        sessionTopic: currentScene.title,
        contentKey: contentKey ?? currentScene.id,
        lessonContext: currentScene.lessonContext,
        kickoffMessage: currentScene.kickoffMessage,
      ),
      fullscreenDialog: true,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentScene = _resolvedScene;
    return SpeakScaffold(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: SpeakColors.inkSoft,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.favorite_border_rounded,
                  color: SpeakColors.inkSoft,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              children: [
                _sceneHero(currentScene),
                const SizedBox(height: 24),
                Text(currentScene.title, style: DesignTokens.display(25)),
                const SizedBox(height: 5),
                Text(
                  currentScene.subtitle,
                  style: DesignTokens.body(
                    14,
                  ).copyWith(color: SpeakColors.inkSoft),
                ),
                const SizedBox(height: 20),
                Text('In this roleplay', style: DesignTokens.display(21)),
                const SizedBox(height: 12),
                SpeakCard(
                  child: Column(
                    children: [
                      _detail(
                        Icons.person_outline_rounded,
                        'Your role',
                        currentScene.learnerRole,
                      ),
                      const Divider(height: 22, color: SpeakColors.line),
                      _detail(
                        Icons.record_voice_over_rounded,
                        'Tutor role',
                        currentScene.tutorRole,
                      ),
                      const Divider(height: 22, color: SpeakColors.line),
                      _detail(
                        Icons.auto_awesome_rounded,
                        'Your goal',
                        currentScene.goal,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('Try saying', style: DesignTokens.display(21)),
                const SizedBox(height: 10),
                SpeakCard(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.format_quote_rounded,
                        color: SpeakColors.blue,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          currentScene.openingLine,
                          style: DesignTokens.body(15, weight: FontWeight.w600),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: 'Play opening line',
                        child: IconButton(
                          tooltip: 'Play opening line',
                          onPressed: () => _speakFrench(
                            currentScene.openingLine,
                            contentItemId: currentScene.id,
                          ),
                          icon: const Icon(Icons.volume_up_outlined),
                          color: SpeakColors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
                if (currentScene.targetPhrases.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('Useful phrases', style: DesignTokens.display(21)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final phrase in currentScene.targetPhrases)
                        ActionChip(
                          label: Text(phrase),
                          avatar: const Icon(
                            Icons.volume_up_outlined,
                            size: 16,
                          ),
                          onPressed: () => _speakFrench(
                            phrase,
                            contentItemId: currentScene.id,
                          ),
                          backgroundColor: SpeakColors.blueSoft,
                          side: BorderSide.none,
                          labelStyle: DesignTokens.body(
                            12,
                            weight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SpeakPrimaryButton(
              label: 'Start roleplay',
              icon: Icons.arrow_forward_rounded,
              onTap: () => _start(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sceneHero(SpeakRoleplayScene currentScene) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 190,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (currentScene.imageUrl != null)
              Image.network(
                currentScene.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    DesignTokens.primary.withValues(alpha: 0.94),
                    DesignTokens.primaryDeep.withValues(alpha: 0.88),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            Positioned(
              right: 18,
              top: 18,
              child: Icon(
                _sceneIcon(currentScene),
                color: Colors.white.withValues(alpha: 0.18),
                size: 90,
              ),
            ),
            Positioned(
              left: 18,
              bottom: 18,
              child: Text(
                currentScene.location.toUpperCase(),
                style: DesignTokens.label(
                  10,
                ).copyWith(color: Colors.white70, letterSpacing: 1.2),
              ),
            ),
            Positioned(
              left: 18,
              bottom: 42,
              child: Text(
                'ROLEPLAY',
                style: DesignTokens.label(
                  10,
                ).copyWith(color: Colors.white70, letterSpacing: 1.2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _sceneIcon(SpeakRoleplayScene scene) {
    final text = '${scene.title} ${scene.location}'.toLowerCase();
    if (text.contains('café') || text.contains('coffee')) {
      return Icons.local_cafe_rounded;
    }
    if (text.contains('gare') || text.contains('train')) {
      return Icons.train_rounded;
    }
    if (text.contains('restaurant') || text.contains('crêperie')) {
      return Icons.restaurant_rounded;
    }
    if (text.contains('marché') || text.contains('market')) {
      return Icons.storefront_rounded;
    }
    if (text.contains('hôtel') || text.contains('hotel')) {
      return Icons.hotel_rounded;
    }
    if (text.contains('aéroport') || text.contains('airport')) {
      return Icons.flight_takeoff_rounded;
    }
    return Icons.forum_rounded;
  }

  void _speakFrench(String text, {required String contentItemId}) {
    LessonSpeechService.shared.speak(
      items: [
        SpeechItem(text: text, language: 'fr-FR', contentItemId: contentItemId),
      ],
    );
  }

  Widget _detail(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Icon(icon, color: SpeakColors.blue, size: 21),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: DesignTokens.body(13, weight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: DesignTokens.body(
                  12,
                ).copyWith(color: SpeakColors.inkSoft),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
