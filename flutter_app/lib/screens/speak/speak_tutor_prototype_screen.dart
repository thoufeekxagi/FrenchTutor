import 'package:flutter/material.dart';

import '../../config/api_keys.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/chat_message.dart';
import '../../models/tutor_persona.dart';
import '../../services/ai_session_gate.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/tutor_voice_preview.dart';
import '../../providers/database_provider.dart';
import '../../widgets/speaking_transcript_strip.dart';
import '../../widgets/tutor_avatar_stage.dart';
import '../session/session_screen.dart';
import 'speak_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A deliberately isolated speaking-stage preview.
///
/// It keeps the stable tutor portrait and transcript behaviour available for
/// QA while the production audio-to-face renderer is still being evaluated.
class SpeakTutorPrototypeScreen extends ConsumerStatefulWidget {
  const SpeakTutorPrototypeScreen({super.key});

  @override
  ConsumerState<SpeakTutorPrototypeScreen> createState() =>
      _SpeakTutorPrototypeScreenState();
}

class _SpeakTutorPrototypeScreenState
    extends ConsumerState<SpeakTutorPrototypeScreen> {
  final _transcriptController = ScrollController();
  final _lineController = TextEditingController();
  final _previewer = TutorVoicePreviewer();
  final _messages = <ChatMessage>[
    ChatMessage(
      role: 'tutor',
      content: 'Bonjour ! On peut pratiquer une vraie conversation.',
    ),
    ChatMessage(
      role: 'user',
      content: 'Je voudrais commander un café, s’il vous plaît.',
    ),
  ];

  @override
  void dispose() {
    _transcriptController.dispose();
    _lineController.dispose();
    _previewer.dispose();
    super.dispose();
  }

  Future<void> _listenToTutor(TutorPersona persona) async {
    if (_previewer.playingId == persona.id) {
      await _previewer.stop();
    } else {
      await _previewer.play(persona);
    }
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
  }

  void _addLine() {
    final text = _lineController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(ChatMessage(role: 'user', content: text));
      _lineController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_transcriptController.hasClients) return;
      _transcriptController.animateTo(
        _transcriptController.position.maxScrollExtent,
        duration: DesignTokens.durationFast,
        curve: DesignTokens.curveStandard,
      );
    });
  }

  Future<void> _startLiveConversation() async {
    if (!await ensureAiSessionQuota(
          context,
          ref.read(pilotAccessServiceProvider),
        ) ||
        !mounted) {
      return;
    }
    await _previewer.stop();
    LessonSpeechService.shared.deactivate();
    if (!mounted) return;
    await AppRouter.push(
      context,
      (_) => const SessionScreen(
        apiKey: ApiKeys.geminiKey,
        stage: 'free_talk',
        sessionTopic: 'A calm French conversation',
        lessonContext:
            'Have a natural French conversation. Keep the tutor warm and concise. '
            'When helpful, make the learner repeat one useful phrase and then let '
            'them continue speaking.',
      ),
      fullscreenDialog: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _previewer,
      builder: (context, _) {
        return ValueListenableBuilder<TutorPersona>(
          valueListenable: ActiveTutor.notifier,
          builder: (context, persona, _) {
            final state = _previewer.playingId == persona.id
                ? TutorAvatarState.speaking
                : TutorAvatarState.listening;
            final compact = MediaQuery.sizeOf(context).height < 760;
            return SpeakScaffold(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'Tutor stage',
                                style: DesignTokens.body(
                                  13,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Portrait preview · ${persona.displayName}',
                                style: DesignTokens.body(
                                  11,
                                ).copyWith(color: SpeakColors.inkSoft),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  SpeakingTranscriptStrip(
                    messages: _messages,
                    controller: _transcriptController,
                    tutorName: persona.displayName,
                    height: compact ? 126 : 142,
                  ),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TutorAvatarStage(
                            persona: persona,
                            state: state,
                            compact: compact,
                          ),
                          Text(
                            persona.displayName,
                            style: DesignTokens.display(22),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Warm, clear, and encouraging',
                            style: DesignTokens.body(
                              12.5,
                            ).copyWith(color: SpeakColors.inkSoft),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _listenToTutor(persona),
                            icon: Icon(
                              _previewer.playingId == persona.id
                                  ? Icons.stop_rounded
                                  : Icons.volume_up_rounded,
                            ),
                            label: Text(
                              _previewer.playingId == persona.id
                                  ? 'Stop sample'
                                  : 'Hear ${persona.displayName}',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _startLiveConversation,
                            icon: const Icon(Icons.mic_none_rounded),
                            label: const Text('Start live'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: TextField(
                      controller: _lineController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _addLine(),
                      decoration: InputDecoration(
                        hintText: 'Add your line to the transcript',
                        suffixIcon: IconButton(
                          tooltip: 'Add line',
                          onPressed: _addLine,
                          icon: const Icon(Icons.arrow_upward_rounded),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: SpeakColors.line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: SpeakColors.line),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
