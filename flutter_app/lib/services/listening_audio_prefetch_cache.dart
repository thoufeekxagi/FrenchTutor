import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'elevenlabs_audio_service.dart';
import 'sync_service.dart';
import '../models/content_models.dart';

/// Keeps a small memory deck plus a persistent local copy of Listening clips.
///
/// The story row and audio path remain durable in Supabase/SQLite. This cache
/// removes repeated private-storage downloads both within and across launches.
class ListeningAudioPrefetchCache {
  ListeningAudioPrefetchCache._();

  static final shared = ListeningAudioPrefetchCache._();

  // The library warm-up covers the learner's saved window (up to 15 lessons).
  // Keep that bounded window available so warming older lessons does not
  // immediately evict the newer ones before the learner can open them.
  static const _capacity = 15;
  final Map<String, Future<ElevenLabsAudioClip?>> _entries = {};
  final List<String> _recency = [];
  Directory? _directoryLazy;

  Future<ElevenLabsAudioClip?>? peek(String storyId) => _entries[storyId];

  Future<ElevenLabsAudioClip?> prefetch({
    required GeneratedStory story,
    required SyncService sync,
  }) {
    final path = story.audioPath?.trim() ?? '';
    if (path.isEmpty) return Future<ElevenLabsAudioClip?>.value(null);

    final existing = _entries[story.id];
    if (existing != null) {
      _touch(story.id);
      return existing;
    }

    final future = _download(story: story, path: path, sync: sync);
    _entries[story.id] = future;
    _touch(story.id);
    _trim();
    unawaited(
      future.then<void>(
        (clip) {
          if (clip == null && identical(_entries[story.id], future)) {
            _entries.remove(story.id);
            _recency.remove(story.id);
          }
        },
        onError: (_, _) {
          _entries.remove(story.id);
          _recency.remove(story.id);
        },
      ),
    );
    return future;
  }

  Future<void> remember({
    required GeneratedStory story,
    required ElevenLabsAudioClip clip,
  }) async {
    final path = story.audioPath?.trim() ?? '';
    if (path.isEmpty || clip.bytes.isEmpty) return;
    final ready = Future<ElevenLabsAudioClip?>.value(clip);
    _entries[story.id] = ready;
    _touch(story.id);
    _trim();
    await _writeLocal(path, clip.bytes);
  }

  Future<ElevenLabsAudioClip?> _download({
    required GeneratedStory story,
    required String path,
    required SyncService sync,
  }) async {
    try {
      final local = await _readLocal(path);
      if (local != null && local.isNotEmpty) {
        final localClip = _clip(story: story, path: path, bytes: local);
        if (localClip != null) return localClip;
        await _removeLocal(path);
      }
      final bytes = await sync
          .downloadListeningAudio(path)
          .timeout(const Duration(seconds: 15));
      if (bytes == null || bytes.isEmpty) return null;
      final clip = _clip(story: story, path: path, bytes: bytes);
      if (clip == null) return null;
      await _writeLocal(path, bytes);
      return clip;
    } catch (_) {
      return null;
    }
  }

  ElevenLabsAudioClip? _clip({
    required GeneratedStory story,
    required String path,
    required Uint8List bytes,
  }) {
    final mode = story.audioMode?.trim().isNotEmpty == true
        ? story.audioMode!.trim()
        : 'narration';
    final isWav =
        path.toLowerCase().endsWith('.wav') || mode == 'gemini_live_spoken';
    if (isWav && !_isValidWav(bytes)) return null;
    return ElevenLabsAudioClip(
      mode: mode,
      bytes: bytes,
      container: isWav ? 'wav' : 'mp3',
    );
  }

  Future<Directory> get _directory async {
    if (_directoryLazy != null) return _directoryLazy!;
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/listening_audio_cache');
    if (!await directory.exists()) await directory.create(recursive: true);
    return _directoryLazy = directory;
  }

  String _fileName(String path) => '${sha256.convert(utf8.encode(path))}.audio';

  Future<Uint8List?> _readLocal(String path) async {
    try {
      final file = File('${(await _directory).path}/${_fileName(path)}');
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeLocal(String path, List<int> bytes) async {
    try {
      final file = File('${(await _directory).path}/${_fileName(path)}');
      await file.writeAsBytes(bytes, flush: false);
    } catch (_) {
      // The downloaded in-memory clip is still usable for this session.
    }
  }

  Future<void> _removeLocal(String path) async {
    try {
      final file = File('${(await _directory).path}/${_fileName(path)}');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  bool _isValidWav(List<int> bytes) {
    if (bytes.length < 44) return false;
    String marker(int offset) =>
        String.fromCharCodes(bytes.sublist(offset, offset + 4));
    return marker(0) == 'RIFF' && marker(8) == 'WAVE';
  }

  void _touch(String storyId) {
    _recency.remove(storyId);
    _recency.add(storyId);
  }

  void _trim() {
    while (_recency.length > _capacity) {
      final oldest = _recency.removeAt(0);
      _entries.remove(oldest);
    }
  }
}
