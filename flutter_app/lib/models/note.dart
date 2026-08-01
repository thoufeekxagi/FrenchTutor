class Note {
  Note({
    required this.id,
    this.uuid,
    this.tag,
    required this.text,
    this.source = 'user',
    this.sessionId,
    required this.createdAt,
    required this.updatedAt,
    this.timesShown = 0,
  });

  final int id;

  /// Sync identity (client-generated UUID) — null on a legacy pre-migration
  /// row that hasn't been re-saved yet, in which case it isn't pushed to
  /// Supabase until the next save assigns one.
  String? uuid;
  String? tag;
  String text;

  /// 'user' (typed in the floating notetaker) or 'ai' (auto-generated recap
  /// of a live session's new vocabulary) — both show in the same list.
  String source;

  /// The live session this note was auto-generated from, when [source] is
  /// 'ai'; null for user notes.
  String? sessionId;
  final String createdAt;
  String updatedAt;
  int timesShown;
}
