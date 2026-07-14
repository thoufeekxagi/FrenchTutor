import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../models/session.dart';
import '../../models/chat_message.dart';
import '../../providers/database_provider.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageServiceProvider);
    final messages = storage.getSessionMessages(sessionId: session.id);

    final startDate = DateTime.tryParse(session.startedAt);
    final endDate =
        session.endedAt != null ? DateTime.tryParse(session.endedAt!) : null;
    final duration = (startDate != null && endDate != null)
        ? endDate.difference(startDate)
        : null;

    final dateText = startDate != null
        ? _formatDate(startDate)
        : session.startedAt;
    final durationText = duration != null
        ? _formatDuration(duration)
        : null;

    return Scaffold(
      backgroundColor: Passeport.parchment,
      appBar: AppBar(
        backgroundColor: Passeport.parchment,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.topic ?? 'Session',
              style: Passeport.display(18),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (durationText != null)
              Text(
                '$dateText  ·  $durationText',
                style: Passeport.body(12).copyWith(color: Passeport.slateDim),
              )
            else
              Text(
                dateText,
                style: Passeport.body(12).copyWith(color: Passeport.slateDim),
              ),
          ],
        ),
      ),
      body: messages.isEmpty
          ? Center(
              child: Text(
                'No messages in this session',
                style: Passeport.body(14).copyWith(color: Passeport.slate),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                return _buildMessageBubble(messages[index]);
              },
            ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: Passeport.brass.withValues(alpha: 0.15),
              child: Icon(Icons.school, size: 14, color: Passeport.brass),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? Passeport.maroon : Passeport.card,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft:
                      isUser ? const Radius.circular(14) : const Radius.circular(4),
                  bottomRight:
                      isUser ? const Radius.circular(4) : const Radius.circular(14),
                ),
                border: isUser
                    ? null
                    : Border.all(color: Passeport.hairline, width: 1),
              ),
              child: Text(
                message.content,
                style: Passeport.body(14).copyWith(
                  color: isUser ? Passeport.parchment : Passeport.text,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
