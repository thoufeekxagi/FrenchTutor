import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../design/tokens.dart';
import '../../models/chat_message.dart';
import '../../models/session.dart';
import '../../providers/database_provider.dart';
import '../../widgets/adaptive/adaptive.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageServiceProvider);
    final messages = storage.getSessionMessages(sessionId: session.id);

    final startDate = DateTime.tryParse(session.startedAt);
    final endDate = session.endedAt != null
        ? DateTime.tryParse(session.endedAt!)
        : null;
    final duration = (startDate != null && endDate != null)
        ? endDate.difference(startDate)
        : null;
    final dateText = startDate != null
        ? _formatDate(startDate)
        : session.startedAt;
    final durationText = duration != null ? _formatDuration(duration) : null;

    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        backgroundColor: DesignTokens.canvas,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 60,
        leading: Center(
          child: Semantics(
            button: true,
            label: 'Back',
            child: IconButton(
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              icon: const Icon(CupertinoIcons.chevron_left, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: PSContentColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.screenMargin,
                  DesignTokens.space2,
                  DesignTokens.screenMargin,
                  DesignTokens.space5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.topic ?? 'Session',
                      style: DesignTokens.display(28),
                    ),
                    const SizedBox(height: DesignTokens.space2),
                    Text(
                      durationText == null
                          ? dateText
                          : '$dateText · $durationText',
                      style: DesignTokens.body(
                        14,
                      ).copyWith(color: DesignTokens.slateDim),
                    ),
                    const SizedBox(height: DesignTokens.space4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.space3,
                        vertical: DesignTokens.space2,
                      ),
                      decoration: BoxDecoration(
                        color: DesignTokens.infoSoft,
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusPill,
                        ),
                      ),
                      child: Text(
                        '${messages.length} message${messages.length == 1 ? '' : 's'} saved',
                        style: DesignTokens.body(
                          12,
                          weight: FontWeight.w600,
                        ).copyWith(color: DesignTokens.info),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: messages.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          DesignTokens.screenMargin,
                          DesignTokens.space2,
                          DesignTokens.screenMargin,
                          32,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          return _buildMessage(messages[index]);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: DesignTokens.infoSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.text_bubble,
                color: DesignTokens.info,
                size: 25,
              ),
            ),
            const SizedBox(height: DesignTokens.space4),
            Text('No transcript saved', style: DesignTokens.display(19)),
            const SizedBox(height: DesignTokens.space2),
            Text(
              'This session does not contain any saved messages.',
              textAlign: TextAlign.center,
              style: DesignTokens.body(
                14,
              ).copyWith(color: DesignTokens.slateDim, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(ChatMessage message) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.space5),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: DesignTokens.successSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.waveform,
                size: 18,
                color: DesignTokens.success,
              ),
            ),
            const SizedBox(width: DesignTokens.space3),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  isUser ? 'You' : 'Marie',
                  style: DesignTokens.body(
                    12,
                    weight: FontWeight.w600,
                  ).copyWith(color: DesignTokens.slateDim),
                ),
                const SizedBox(height: DesignTokens.space1),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.space4,
                    vertical: DesignTokens.space3,
                  ),
                  decoration: BoxDecoration(
                    color: isUser ? DesignTokens.primary : DesignTokens.surface,
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radiusCard,
                    ),
                    boxShadow: isUser ? null : DesignTokens.cardShadow,
                  ),
                  child: Text(
                    message.content,
                    style: DesignTokens.body(15).copyWith(
                      color: isUser ? DesignTokens.surface : DesignTokens.text,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 48),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatDuration(Duration duration) {
    final totalMinutes = duration.inMinutes;
    if (totalMinutes < 1) return '<1 min';
    if (totalMinutes < 60) return '$totalMinutes min';
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }
}
