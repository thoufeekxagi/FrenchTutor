class Note {
  Note({
    required this.id,
    this.tag,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.timesShown = 0,
  });

  final int id;
  String? tag;
  String text;
  final String createdAt;
  String updatedAt;
  int timesShown;
}
