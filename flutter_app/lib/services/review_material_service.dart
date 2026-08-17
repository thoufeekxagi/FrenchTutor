import '../data/database/storage_service.dart';

/// One real piece of learner material that can be used to build a review.
/// Review never invents placeholder phrases: it is sourced from the learner's
/// most recent recorded transcript turns.
class ReviewPhrase {
  const ReviewPhrase({
    required this.text,
    required this.source,
    required this.role,
  });

  final String text;
  final String source;
  final String role;
}

abstract final class ReviewMaterialService {
  /// Returns the newest substantial transcript turns across the learner's
  /// recent sessions, newest first. The cap keeps a review focused while
  /// still allowing it to draw from more than one practice session.
  static List<ReviewPhrase> recent(StorageService storage, {int limit = 10}) {
    final phrases = <ReviewPhrase>[];
    for (final session in storage.getAllSessions()) {
      final messages = storage.getSessionMessages(sessionId: session.id);
      for (final message in messages.reversed) {
        final text = message.content.trim();
        if (!_isReviewable(text)) continue;
        phrases.add(
          ReviewPhrase(
            text: text,
            source: session.topic?.trim().isNotEmpty == true
                ? session.topic!.trim()
                : 'Recent practice',
            role: message.role,
          ),
        );
        if (phrases.length == limit) return phrases;
      }
    }
    return phrases;
  }

  static bool _isReviewable(String text) {
    if (text.isEmpty) return false;
    if (text.length < 2) return false;
    final normalized = text.toLowerCase();
    const navigation = {
      'next',
      'again',
      'back',
      'yes',
      'yeah',
      'ok',
      'okay',
      'oui',
      "d'accord",
    };
    if (navigation.contains(normalized)) return false;
    return text.split(RegExp(r'\s+')).length >= 2;
  }
}
