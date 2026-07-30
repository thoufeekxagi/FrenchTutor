import 'package:sqlite3/common.dart';

/// Fast-forwards the harness's in-memory `LearningStore` between simulated
/// days.
///
/// `SRSService`/`LearningStore` have no clock-injection seam — every
/// scheduling write stamps real `DateTime.now()` directly (see
/// lib/services/srs_service.dart, lib/data/database/learning_store.dart).
/// Rather than touch production source for a test-only harness, this
/// corrects the anchor dates AFTER each simulated day's real writes
/// complete: real interval/ease math still runs untouched inside
/// `SRSService.grade()`, only the resulting `due_at`/`introduced_on`/
/// `reviewed_at` get moved from "real today" to the simulated day.
///
/// Known limitation: assumes the whole run happens within a single real
/// calendar day (introduced_on detection keys off the real day-string
/// captured at startup). A run spanning real local midnight could misfire
/// that one column for whichever cards are introduced right at the
/// boundary — cosmetic only, doesn't affect due-date scheduling.
class ClockShift {
  ClockShift(this._db) : _realToday = _dayString(DateTime.now());

  final CommonDatabase _db;
  final String _realToday;

  int _vocabCardsBoundaryMs = 0;
  int _vocabReviewsMaxId = 0;
  int _sessionDiaryMaxId = 0;

  /// Call once right before running a simulated day's real work.
  void beginDay() {
    _vocabCardsBoundaryMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    _vocabReviewsMaxId = _maxId('vocab_reviews');
    _sessionDiaryMaxId = _maxId('session_diary');
  }

  int _maxId(String table) {
    final rows = _db.select('SELECT COALESCE(MAX(id), 0) AS m FROM $table');
    return rows.first['m'] as int;
  }

  /// Call once right after a simulated day's real work completes, passing
  /// the date this day represents in the simulation.
  void endDay(DateTime simDate) {
    final simDay = _dayString(simDate);
    final boundaryIso = DateTime.fromMillisecondsSinceEpoch(
      _vocabCardsBoundaryMs,
      isUtc: true,
    ).toIso8601String();
    final boundaryNow = DateTime.fromMillisecondsSinceEpoch(
      _vocabCardsBoundaryMs,
      isUtc: true,
    );

    final touched = _db.select(
      'SELECT id, due_at, last_reviewed_at, introduced_on FROM vocab_cards WHERE updated_at >= ?',
      [boundaryIso],
    );
    for (final row in touched) {
      final id = row['id'] as String;
      final dueAt = _shift(row['due_at'] as String?, boundaryNow, simDate);
      final lastReviewed = _shift(
        row['last_reviewed_at'] as String?,
        boundaryNow,
        simDate,
      );
      // introduced_on only ever needs correcting the FIRST time a card is
      // introduced (its raw value is store.dayString(real-now), constant
      // for the whole run) — on later simulated days upsertSRS's own
      // COALESCE already preserves whatever we corrected it to previously,
      // so only rows still holding the untouched real-today value get
      // rewritten here.
      final introducedOn = row['introduced_on'] as String?;
      final newIntroducedOn = introducedOn == _realToday ? simDay : introducedOn;
      _db.execute(
        'UPDATE vocab_cards SET due_at = ?, last_reviewed_at = ?, introduced_on = ? WHERE id = ?',
        [dueAt, lastReviewed, newIntroducedOn, id],
      );
    }

    _db.execute(
      'UPDATE vocab_reviews SET reviewed_at = ? WHERE id > ?',
      [simDate.toUtc().toIso8601String(), _vocabReviewsMaxId],
    );
    _db.execute(
      'UPDATE session_diary SET date = ? WHERE id > ?',
      [simDay, _sessionDiaryMaxId],
    );
  }

  String? _shift(String? iso, DateTime boundaryNow, DateTime simDate) {
    if (iso == null) return null;
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final delta = parsed.difference(boundaryNow);
    return simDate.toUtc().add(delta).toIso8601String();
  }

  static String _dayString(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
