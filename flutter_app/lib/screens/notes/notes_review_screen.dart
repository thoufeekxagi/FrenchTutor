import '../../widgets/adaptive/adaptive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../widgets/passeport_card.dart';
import '../../providers/database_provider.dart';
import '../../models/note.dart';

/// Lets a student browse and study everything they jotted down with the floating
/// notetaker across every lesson/session — grouped by which stage it came from
/// (Vocabulary, Grammar, Listening, Writing, Speaking, or General), newest first.
/// Read-only aside from deleting a note; there's nothing to "do" with a note here,
/// only to reread it while reviewing.
class NotesReviewScreen extends ConsumerStatefulWidget {
  const NotesReviewScreen({super.key});

  @override
  ConsumerState<NotesReviewScreen> createState() => _NotesReviewScreenState();
}

class _NotesReviewScreenState extends ConsumerState<NotesReviewScreen> {
  List<Note> _notes = [];
  bool _loading = true;
  String _filter = 'All';

  static const _knownTags = ['Vocabulary', 'Grammar', 'Listening', 'Writing', 'Speaking', 'General'];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final storage = ref.read(storageServiceProvider);
    setState(() => _loading = true);
    Future(() => storage.getAllNotes()).then((loaded) {
      if (mounted) setState(() { _notes = loaded; _loading = false; });
    });
  }

  void _delete(Note note) {
    ref.read(storageServiceProvider).deleteNote(note.id);
    setState(() => _notes.removeWhere((n) => n.id == note.id));
  }

  List<String> get _availableTags {
    final present = _notes.map((n) => n.tag ?? 'General').toSet();
    // Keep a stable, familiar order; only show tags that actually have notes.
    return _knownTags.where(present.contains).toList();
  }

  List<Note> get _filteredNotes {
    if (_filter == 'All') return _notes;
    return _notes.where((n) => (n.tag ?? 'General') == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tags = _availableTags;

    return Scaffold(
      backgroundColor: Passeport.parchmentDim,
      appBar: AppBar(
        title: Text('Review Notes', style: Passeport.display(20)),
        backgroundColor: Passeport.parchmentDim,
        foregroundColor: Passeport.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _loading
          ? const Center(child: PSProgressIndicator())
          : _notes.isEmpty
              ? _emptyState()
              : Column(
                  children: [
                    if (tags.isNotEmpty) _filterBar(tags),
                    Expanded(
                      child: RefreshIndicator(
                        color: Passeport.maroon,
                        onRefresh: () async => _reload(),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                          itemCount: _filteredNotes.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _NoteCard(note: _filteredNotes[i], onDelete: () => _delete(_filteredNotes[i])),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _filterBar(List<String> tags) {
    final chips = ['All', ...tags];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final label = chips[i];
          final selected = _filter == label;
          return GestureDetector(
            onTap: () => setState(() => _filter = label),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? Passeport.maroon : Passeport.card,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: selected ? Passeport.maroon : Passeport.hairline),
              ),
              child: Text(
                label,
                style: Passeport.mono(11.5, weight: FontWeight.w500)
                    .copyWith(color: selected ? Passeport.parchment : Passeport.slateDim),
              ),
            ),
          );
        },
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
            Icon(Icons.edit_note, size: 40, color: Passeport.slate),
            const SizedBox(height: 12),
            Text(
              'No notes yet',
              style: Passeport.display(17, weight: FontWeight.w500).copyWith(color: Passeport.text),
            ),
            const SizedBox(height: 6),
            Text(
              "Tap the notetaker bubble during any lesson or call to jot down what you're hearing or reading — it'll show up here to review later.",
              style: Passeport.body(13).copyWith(color: Passeport.slateDim),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.onDelete});

  final Note note;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(color: Passeport.maroon, borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: PasseportCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Passeport.maroon.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    (note.tag ?? 'General').toUpperCase(),
                    style: Passeport.mono(9.5, weight: FontWeight.w500).copyWith(color: Passeport.maroon),
                  ),
                ),
                const Spacer(),
                Text(_formatDate(note.updatedAt), style: Passeport.mono(10.5).copyWith(color: Passeport.slateDim)),
              ],
            ),
            const SizedBox(height: 8),
            Text(note.text, style: Passeport.body(13.5).copyWith(color: Passeport.text)),
          ],
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final date = DateTime.parse(iso);
      return DateFormat('MMM d, HH:mm').format(date);
    } catch (_) {
      return iso;
    }
  }
}
