import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/tokens.dart';
import '../models/session.dart';

/// One row representing a past practice session — shared by the dashboard's
/// "Recent practice" card and the full "All history" list, so a session
/// looks identical no matter where it's tapped from.
class SessionRow extends StatelessWidget {
  const SessionRow({super.key, required this.session});

  final Session session;

  /// Human label for [Session.stage] — every stage string any practice
  /// screen writes via `SessionRecorder` must have an entry here or it just
  /// shows with no badge (still fine, just less informative).
  static String? stageLabel(String? stage) => switch (stage) {
    'vocab' => 'Vocab',
    'grammar' => 'Grammar',
    'reading_listening' => 'Reading',
    'roleplay' => 'Roleplay',
    'writing' => 'Writing',
    'speaking' => 'Speaking',
    'story' => 'Story',
    _ => null,
  };

  static String formatDate(String iso) {
    try {
      return DateFormat('MMM d, HH:mm').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = stageLabel(session.stage);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: DesignTokens.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.forum_outlined,
              size: 19,
              color: DesignTokens.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.topic ?? 'French practice',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.body(13.5, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDate(session.startedAt),
                  style: DesignTokens.body(
                    11.5,
                  ).copyWith(color: DesignTokens.mutedDim),
                ),
              ],
            ),
          ),
          if (label != null)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: DesignTokens.primarySoft,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                label,
                style: DesignTokens.body(
                  10.5,
                  weight: FontWeight.w600,
                ).copyWith(color: DesignTokens.primary),
              ),
            ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 19,
            color: DesignTokens.muted,
          ),
        ],
      ),
    );
  }
}
