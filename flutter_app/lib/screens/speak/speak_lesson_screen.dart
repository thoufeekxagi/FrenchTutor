import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_keys.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../providers/database_provider.dart';
import '../../services/ai_session_gate.dart';
import '../../services/lesson_speech_service.dart';
import '../session/session_screen.dart';
import 'speak_ui.dart';

class SpeakLessonScreen extends ConsumerStatefulWidget {
  const SpeakLessonScreen({
    super.key,
    required this.topic,
    this.lessonContext,
    this.contentKey,
    this.primarySkill,
    this.focusPhrase = 'Bonjour !',
  });

  final String topic;
  final String? lessonContext;
  final String? contentKey;
  final String? primarySkill;
  final String focusPhrase;

  @override
  ConsumerState<SpeakLessonScreen> createState() => _SpeakLessonScreenState();
}

class _SpeakLessonScreenState extends ConsumerState<SpeakLessonScreen> {
  Future<void> _start(BuildContext context) async {
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
        sessionTopic: widget.topic,
        contentKey: widget.contentKey,
        stage: widget.primarySkill ?? 'speaking',
        lessonContext:
            widget.lessonContext ??
            'Run a contextual French lesson about "${widget.topic}". Start with a useful phrase, ask the learner to use it, then give concise feedback before moving on.',
        kickoffMessage: _kickoffMessage,
      ),
      fullscreenDialog: true,
    );
    // This preflight is only the doorway into the course activity. Once the
    // live tutor is done, return to the course session instead of leaving the
    // learner on a second "Start speaking" screen with no new action.
    if (context.mounted) Navigator.of(context).pop(true);
  }

  String get _kickoffMessage =>
      '(App instruction, not the student: this is a guided speaking practice '
      'inside the course lesson "${widget.topic}". Briefly explain in English '
      'what the learner is practising, then say "${widget.focusPhrase}" in '
      'French and ask them to repeat or respond with one very short French '
      'attempt. Stay at the learner\'s level and keep the turn focused on '
      'this lesson context; do not greet with a generic free-talk question.)';

  @override
  Widget build(BuildContext context) {
    return SpeakScaffold(
      child: Column(
        children: [
          SpeakHeader(
            title: 'Speaking practice',
            subtitle: widget.topic,
            leading: GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: Icon(Icons.close_rounded, color: SpeakColors.inkSoft),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 34, 20, 24),
              children: [
                Text(widget.topic, style: DesignTokens.display(30)),
                const SizedBox(height: 24),
                SpeakCard(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: SpeakColors.accentSoft,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              Icons.record_voice_over_rounded,
                              color: SpeakColors.accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Your speaking target',
                              style: DesignTokens.body(
                                15,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.bookmark_border_rounded,
                            color: SpeakColors.inkSoft,
                            size: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Center(
                        child: Text(
                          'Bonjour !',
                          style: DesignTokens.display(
                            30,
                          ).copyWith(color: SpeakColors.accent),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: Text(
                          'Hello!',
                          style: DesignTokens.body(
                            15,
                          ).copyWith(color: SpeakColors.inkSoft),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Marie will explain the task in English, model the French, '
                        'then wait for your answer in the live conversation.',
                        textAlign: TextAlign.center,
                        style: DesignTokens.body(
                          13,
                        ).copyWith(color: SpeakColors.inkSoft, height: 1.35),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text('You will practise', style: DesignTokens.display(20)),
                const SizedBox(height: 10),
                _bullet(
                  Icons.chat_bubble_outline_rounded,
                  'Useful phrases for real conversations',
                ),
                _bullet(Icons.hearing_rounded, 'Listening and pronunciation'),
                _bullet(
                  Icons.auto_awesome_rounded,
                  'Quick feedback from your tutor',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SpeakPrimaryButton(
              label: 'Start speaking',
              icon: Icons.arrow_forward_rounded,
              onTap: () => _start(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: SpeakColors.accent),
          const SizedBox(width: 10),
          Text(
            text,
            style: DesignTokens.body(13).copyWith(color: SpeakColors.inkSoft),
          ),
        ],
      ),
    );
  }
}
