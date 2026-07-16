import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../design/tokens.dart';
import '../../models/note.dart';
import '../../providers/database_provider.dart';
import '../../widgets/adaptive/adaptive.dart';

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

  static const _knownTags = [
    'Vocabulary',
    'Grammar',
    'Listening',
    'Writing',
    'Speaking',
    'General',
  ];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final storage = ref.read(storageServiceProvider);
    setState(() => _loading = true);
    Future(() => storage.getAllNotes()).then((loaded) {
      if (mounted) {
        setState(() {
          _notes = loaded;
          _loading = false;
        });
      }
    });
  }

  void _delete(Note note) {
    ref.read(storageServiceProvider).deleteNote(note.id);
    setState(() => _notes.removeWhere((item) => item.id == note.id));
  }

  List<String> get _availableTags {
    final present = _notes.map((note) => note.tag ?? 'General').toSet();
    // Keep a stable, familiar order; only show tags that actually have notes.
    return _knownTags.where(present.contains).toList();
  }

  List<Note> get _filteredNotes {
    if (_filter == 'All') return _notes;
    return _notes.where((note) => (note.tag ?? 'General') == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tags = _availableTags;

    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        backgroundColor: DesignTokens.canvas,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Notes', style: DesignTokens.display(20)),
      ),
      body: SafeArea(
        top: false,
        child: PSContentColumn(
          child: _loading
              ? const Center(child: PSProgressIndicator())
              : _notes.isEmpty
              ? _emptyState()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        DesignTokens.screenMargin,
                        DesignTokens.space4,
                        DesignTokens.screenMargin,
                        DesignTokens.space3,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Review what mattered',
                            style: DesignTokens.display(27),
                          ),
                          const SizedBox(height: DesignTokens.space2),
                          Text(
                            '${_filteredNotes.length} note${_filteredNotes.length == 1 ? '' : 's'} ready to revisit.',
                            style: DesignTokens.body(
                              14,
                            ).copyWith(color: DesignTokens.slateDim),
                          ),
                        ],
                      ),
                    ),
                    if (tags.isNotEmpty) _filterBar(tags),
                    Expanded(
                      child: RefreshIndicator(
                        color: DesignTokens.primary,
                        onRefresh: () async => _reload(),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            DesignTokens.screenMargin,
                            DesignTokens.space4,
                            DesignTokens.screenMargin,
                            32,
                          ),
                          itemCount: _filteredNotes.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 32,
                            color: DesignTokens.parchmentDim,
                          ),
                          itemBuilder: (context, index) {
                            final note = _filteredNotes[index];
                            return _NoteRow(
                              note: note,
                              onDelete: () => _delete(note),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _filterBar(List<String> tags) {
    final chips = ['All', ...tags];
    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.screenMargin,
          vertical: DesignTokens.space2,
        ),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: DesignTokens.space2),
        itemBuilder: (context, index) {
          final label = chips[index];
          final selected = _filter == label;
          return Semantics(
            button: true,
            selected: selected,
            child: InkWell(
              borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
              onTap: () => setState(() => _filter = label),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: DesignTokens.minTapTarget,
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.space4,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? DesignTokens.ink
                      : DesignTokens.parchmentDim,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
                ),
                child: Text(
                  label,
                  style: DesignTokens.body(13, weight: FontWeight.w600)
                      .copyWith(
                        color: selected
                            ? DesignTokens.surface
                            : DesignTokens.inkSoft,
                      ),
                ),
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
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: DesignTokens.infoSoft,
                borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
              ),
              child: const Icon(
                CupertinoIcons.square_pencil,
                size: 28,
                color: DesignTokens.info,
              ),
            ),
            const SizedBox(height: DesignTokens.space5),
            Text(
              'Your notes will collect here',
              style: DesignTokens.display(21),
            ),
            const SizedBox(height: DesignTokens.space2),
            Text(
              'Use the notetaker during a lesson or call. Anything you save will be ready to review here.',
              style: DesignTokens.body(
                14,
              ).copyWith(color: DesignTokens.slateDim, height: 1.45),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note, required this.onDelete});

  final Note note;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.space5),
        decoration: BoxDecoration(
          color: DesignTokens.primary,
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        ),
        child: const Icon(CupertinoIcons.trash, color: DesignTokens.surface),
      ),
      onDismissed: (_) => onDelete(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.space1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _tagColor(note.tag),
                borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
              ),
              child: Icon(
                _tagIcon(note.tag),
                size: 20,
                color: DesignTokens.inkSoft,
              ),
            ),
            const SizedBox(width: DesignTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          note.tag ?? 'General',
                          style: DesignTokens.body(
                            13,
                            weight: FontWeight.w600,
                          ).copyWith(color: DesignTokens.slateDim),
                        ),
                      ),
                      const SizedBox(width: DesignTokens.space3),
                      Text(
                        _formatDate(note.updatedAt),
                        style: DesignTokens.body(
                          12,
                        ).copyWith(color: DesignTokens.slateDim),
                      ),
                    ],
                  ),
                  const SizedBox(height: DesignTokens.space2),
                  Text(
                    note.text,
                    style: DesignTokens.body(15).copyWith(height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _tagColor(String? tag) {
    switch (tag) {
      case 'Listening':
      case 'Speaking':
        return DesignTokens.successSoft;
      case 'Vocabulary':
      case 'Grammar':
        return DesignTokens.infoSoft;
      case 'Writing':
        return DesignTokens.primarySoft;
      default:
        return DesignTokens.parchmentDim;
    }
  }

  IconData _tagIcon(String? tag) {
    switch (tag) {
      case 'Vocabulary':
        return CupertinoIcons.square_stack_3d_up;
      case 'Grammar':
        return CupertinoIcons.book;
      case 'Listening':
        return CupertinoIcons.headphones;
      case 'Writing':
        return CupertinoIcons.pencil;
      case 'Speaking':
        return CupertinoIcons.mic;
      default:
        return CupertinoIcons.doc_text;
    }
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
