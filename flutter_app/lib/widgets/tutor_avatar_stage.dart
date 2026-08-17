import 'package:flutter/material.dart';

import '../models/tutor_persona.dart';
import '../services/tutor_lip_sync_controller.dart';

/// The visual state of a tutor during a conversation.
enum TutorAvatarState { idle, listening, thinking, speaking }

/// Stable image-based tutor stage.
///
/// The previous experiment drew a Flutter puppet and drove a mouth from raw
/// audio amplitude. That created visible jitter and did not preserve the
/// identity, lighting, or geometry of the tutor artwork. Until a real
/// audio-to-face renderer is selected, the app intentionally shows one
/// consistent AI portrait instead of pretending that amplitude motion is
/// facial animation.
///
/// [state] and [lipSync] remain in the public API so callers and prototypes do
/// not need a second migration when a production renderer is introduced. They
/// are intentionally ignored by this safe fallback.
class TutorAvatarStage extends StatelessWidget {
  const TutorAvatarStage({
    super.key,
    required this.persona,
    required this.state,
    this.lipSync,
    this.compact = false,
  });

  final TutorPersona persona;
  final TutorAvatarState state;
  final TutorLipSyncController? lipSync;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final width = compact ? 184.0 : 252.0;
    final height = compact ? 236.0 : 324.0;

    return SizedBox(
      width: width,
      height: height,
      child: Semantics(
        image: true,
        label: '${persona.displayName} tutor portrait',
        child: Image.asset(
          persona.portraitAsset,
          key: ValueKey(persona.id),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) =>
              _PortraitFallback(persona: persona),
        ),
      ),
    );
  }
}

class _PortraitFallback extends StatelessWidget {
  const _PortraitFallback({required this.persona});

  final TutorPersona persona;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircleAvatar(
        radius: 52,
        backgroundColor: const Color(0xFFE8EEF9),
        child: Text(
          persona.initial,
          style: const TextStyle(
            color: Color(0xFF2458C6),
            fontSize: 42,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
