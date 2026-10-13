import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../models/tutor_persona.dart';
import '../ui/v3_ui.dart';
import 'v3_marie_session.dart';

/// The call button at the top of a lesson. One tap starts the call, the same
/// tap ends it. It is a phone, not a microphone.
class V3MarieCallButton extends StatelessWidget {
  const V3MarieCallButton({
    super.key,
    required this.session,
    required this.onTap,
  });

  final V3MarieSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final name = ActiveTutor.current.displayName;
        final phase = session.phase;
        final live = phase == V3MariePhase.live;
        final connecting = phase == V3MariePhase.connecting;
        final color = live ? DesignTokens.danger : DesignTokens.primary;
        return V3Pressable(
          key: const ValueKey('lesson.askMarie'),
          label: live
              ? 'End call with $name'
              : connecting
              ? 'Connecting to $name'
              : 'Talk to $name',
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: live ? DesignTokens.dangerSoft : DesignTokens.primarySoft,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (connecting)
                  const SizedBox.square(
                    dimension: 18,
                    child: CupertinoActivityIndicator(),
                  )
                else
                  Icon(
                    live
                        ? CupertinoIcons.phone_down_fill
                        : CupertinoIcons.phone_fill,
                    size: 18,
                    color: color,
                  ),
                const SizedBox(width: 7),
                Text(
                  live
                      ? 'End'
                      : connecting
                      ? 'Calling'
                      : name,
                  textScaler: const TextScaler.linear(1),
                  style: V3Type.strong(14, color),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The in-lesson Marie panel: status, Mute, End, and a pill with what she is
/// saying. Shown only while a call is connecting, live, or has failed.
///
/// The pill shows at most three lines so it never covers the lesson. Tap it
/// to read the whole conversation (her words and how she heard you).
class V3MarieDock extends StatelessWidget {
  const V3MarieDock({super.key, required this.session});

  final V3MarieSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (session.phase == V3MariePhase.idle) {
          return const SizedBox(width: double.infinity);
        }
        // Large text must never push the lesson off a small screen.
        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.35,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Container(
              key: const ValueKey('marie.dock'),
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              decoration: BoxDecoration(
                color: DesignTokens.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: DesignTokens.hairline),
                boxShadow: DesignTokens.surfaceShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(child: _status()),
                      if (session.phase == V3MariePhase.live) ...[
                        _round(
                          key: const ValueKey('marie.mute'),
                          label: session.muted
                              ? 'Unmute microphone'
                              : 'Mute microphone',
                          icon: session.muted
                              ? CupertinoIcons.mic_slash_fill
                              : CupertinoIcons.mic_fill,
                          fill: session.muted
                              ? DesignTokens.ink
                              : DesignTokens.canvas,
                          foreground: session.muted
                              ? DesignTokens.canvas
                              : DesignTokens.ink,
                          onTap: session.toggleMute,
                        ),
                        const SizedBox(width: 10),
                      ],
                      _round(
                        key: const ValueKey('marie.end'),
                        label: 'End call',
                        icon: CupertinoIcons.phone_down_fill,
                        fill: DesignTokens.danger,
                        foreground: Colors.white,
                        onTap: session.end,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _pill(context),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _status() {
    final name = ActiveTutor.current.displayName;
    final phase = session.phase;
    final (String text, Color color) = switch (phase) {
      V3MariePhase.connecting => ('Connecting to $name…', DesignTokens.primary),
      V3MariePhase.error => ('Could not connect', DesignTokens.danger),
      _ =>
        session.muted
            ? ('Muted. $name cannot hear you', DesignTokens.inkSoft)
            : session.marieSpeaking
            ? ('$name is speaking', DesignTokens.primary)
            : ('Listening', DesignTokens.success),
    };
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: V3Type.strong(14, DesignTokens.ink),
          ),
        ),
      ],
    );
  }

  Widget _round({
    required Key key,
    required String label,
    required IconData icon,
    required Color fill,
    required Color foreground,
    required VoidCallback onTap,
  }) {
    return V3Pressable(
      key: key,
      label: label,
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: DesignTokens.hairline),
        ),
        child: Icon(icon, size: 21, color: foreground),
      ),
    );
  }

  Widget _pill(BuildContext context) {
    final name = ActiveTutor.current.displayName;
    if (session.phase == V3MariePhase.error) {
      return Row(
        children: [
          Expanded(
            child: Text(
              session.error ?? 'Check your connection and try again.',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: V3Type.body(14.5, DesignTokens.ink),
            ),
          ),
          V3Pressable(
            key: const ValueKey('marie.retry'),
            label: 'Try again',
            onTap: () => session.toggle(context),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                'Try again',
                style: V3Type.strong(14.5, DesignTokens.primary),
              ),
            ),
          ),
        ],
      );
    }
    final caption = session.caption;
    final hint = session.phase == V3MariePhase.connecting
        ? 'One moment…'
        : session.muted
        ? 'Tap the microphone to unmute and talk to $name.'
        : '$name is listening. Just talk.';
    final empty = caption.isEmpty;
    return V3Pressable(
      key: const ValueKey('marie.pill'),
      label: empty ? 'Conversation with $name' : '$name said: $caption',
      onTap: () => showV3MarieTranscript(context, session),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: DesignTokens.primarySoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                empty ? hint : caption,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: empty
                    ? V3Type.body(14.5)
                    : V3Type.body(
                        15.5,
                        DesignTokens.ink,
                      ).copyWith(height: 1.35),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              CupertinoIcons.chevron_up,
              size: 16,
              color: DesignTokens.inkSoft,
            ),
          ],
        ),
      ),
    );
  }
}

/// The whole conversation so far: what Marie said, and how she heard you.
Future<void> showV3MarieTranscript(
  BuildContext context,
  V3MarieSession session,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => V3Width(
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final name = ActiveTutor.current.displayName;
          final lines = session.history;
          final shown = lines.isEmpty && session.caption.isNotEmpty
              ? [V3MarieLine(fromMarie: true, text: session.caption)]
              : lines;
          return Container(
            key: const ValueKey('marie.sheet'),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            padding: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            decoration: BoxDecoration(
              color: DesignTokens.canvas,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: DesignTokens.hairline,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Conversation', style: V3Type.title(26)),
                const SizedBox(height: 4),
                Text(
                  'What $name said, and how she heard you.',
                  style: V3Type.body(14),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: shown.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'Nothing yet. Say something and it appears here.',
                            style: V3Type.body(15),
                          ),
                        )
                      : ListView(
                          // Newest at the bottom, and the sheet opens on it.
                          reverse: true,
                          shrinkWrap: true,
                          children: [
                            for (final l in shown.reversed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l.fromMarie
                                          ? name.toUpperCase()
                                          : 'YOU (AS HEARD)',
                                      style: V3Type.eyebrow(
                                        l.fromMarie
                                            ? DesignTokens.primary
                                            : DesignTokens.inkSoft,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    SelectableText(
                                      l.text,
                                      style: V3Type.reading(
                                        18,
                                      ).copyWith(fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
                V3TextAction(
                  label: 'Close',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
