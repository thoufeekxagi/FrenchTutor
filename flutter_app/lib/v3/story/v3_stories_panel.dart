import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../design/app_router.dart';
import '../../design/appearance_colors.dart';
import '../../design/tokens.dart';
import '../ui/v3_ui.dart';
import 'v3_story.dart';
import 'v3_story_reader.dart';
import 'v3_story_store.dart';

/// Stories list, shown in the Practice area of the Learn tab. Screen contract:
///
/// User arrived to: practise French through a short story.
/// They must understand: reading and listening stories are separate modes,
/// grouped by level, and listening transcripts stay hidden until requested.
/// Primary action: start the featured story in the selected mode.
/// Success state: the story opens in its reader or listen-first player.
/// Must not contain: photos, a second font, or levels with fake content. A
/// level with no stories is shown as coming soon and cannot be tapped.
class V3StoriesPanel extends StatefulWidget {
  const V3StoriesPanel({super.key, this.initialListening = false});

  /// Open on the Listen stories mode when a caller needs that starting state.
  final bool initialListening;

  @override
  State<V3StoriesPanel> createState() => _V3StoriesPanelState();
}

class _V3StoriesPanelState extends State<V3StoriesPanel> {
  static const _levels = ['A1', 'A2', 'B1', 'B2'];

  List<V3Story> _stories = const [];
  List<V3Story> _listeningStories = const [];
  Set<String> _done = const {};
  Map<String, int> _pos = const {};
  var _level = 'A1';
  late var _listening = widget.initialListening;
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final catalogs = await Future.wait([
      V3Stories.load(),
      V3Stories.loadListening(),
    ]);
    final stories = catalogs[0];
    final listeningStories = catalogs[1];
    final done = await V3StoryProgress.done();
    final pos = await V3StoryProgress.positions();
    if (!mounted) return;
    setState(() {
      _stories = stories;
      _listeningStories = listeningStories;
      _done = done;
      _pos = pos;
      _loaded = true;
    });
  }

  Future<void> _open(V3Story story) async {
    await AppRouter.push<bool>(
      context,
      (_) => V3StoryReader(
        story: story,
        startAt: _pos[story.id] ?? 0,
        listenFirst: _listening,
      ),
    );
    if (mounted) unawaited(_load());
  }

  V3Story? _featured(List<V3Story> atLevel) {
    for (final s in atLevel) {
      if (!_done.contains(s.id) && (_pos[s.id] ?? 0) > 0) return s;
    }
    for (final s in atLevel) {
      if (!_done.contains(s.id)) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(height: 200);
    final catalog = _listening ? _listeningStories : _stories;
    final atLevel = [
      for (final s in catalog)
        if (s.level == _level) s,
    ];
    final featured = _featured(atLevel);
    final rest = [
      for (final s in atLevel)
        if (s != featured) s,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _modePicker(),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final l in _levels) ...[_chip(l), const SizedBox(width: 8)],
          ],
        ),
        const SizedBox(height: 18),
        if (atLevel.isEmpty)
          Text('Stories for $_level are coming soon.', style: V3Type.body(15)),
        if (featured != null) ...[
          _featuredCard(featured),
          const SizedBox(height: 22),
        ],
        if (rest.isNotEmpty) ...[
          Text(
            featured == null ? 'Stories' : 'More stories',
            style: V3Type.eyebrow(DesignTokens.inkSoft),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < rest.length; i++) ...[
            _storyCard(rest[i], i),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }

  Widget _modePicker() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Row(
        children: [
          _modeButton('read', 'Read stories', listening: false),
          const SizedBox(width: 4),
          _modeButton('listen', 'Listen stories', listening: true),
        ],
      ),
    );
  }

  Widget _modeButton(String id, String label, {required bool listening}) {
    final selected = _listening == listening;
    return Expanded(
      child: V3Pressable(
        key: ValueKey('stories.mode.$id'),
        label: label,
        onTap: () => setState(() => _listening = listening),
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? DesignTokens.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: V3Type.strong(
              14,
              selected ? DesignTokens.onPrimary : DesignTokens.inkSoft,
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String level) {
    final has = (_listening ? _listeningStories : _stories).any(
      (s) => s.level == level,
    );
    final on = _level == level;
    return V3Pressable(
      key: ValueKey('stories.level.$level'),
      label: has ? level : '$level, coming soon',
      onTap: has ? () => setState(() => _level = level) : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 56),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: on ? DesignTokens.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: on ? DesignTokens.primary : DesignTokens.hairline,
          ),
        ),
        child: Text(
          level,
          style: V3Type.strong(
            15,
            on
                ? DesignTokens.onPrimary
                : (has ? DesignTokens.ink : DesignTokens.muted),
          ),
        ),
      ),
    );
  }

  Widget _featuredCard(V3Story s) {
    final at = _pos[s.id] ?? 0;
    final started = at > 0;
    const onBlue = Colors.white;
    final dim = onBlue.withValues(alpha: 0.82);
    return V3Pressable(
      key: const ValueKey('stories.featured'),
      label: '${started ? 'Resume' : 'Start'} ${s.title}',
      onTap: () => _open(s),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppearanceColors.blueLight,
              Color.lerp(AppearanceColors.blueLight, Colors.black, 0.3)!,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_listening ? (started ? 'CONTINUE LISTENING' : 'LISTEN FIRST') : (started ? 'CONTINUE' : 'START HERE')}  ·  ${s.minutes} MIN',
              style: V3Type.eyebrow(dim),
            ),
            const SizedBox(height: 12),
            Text(s.title, style: V3Type.title(30, color: onBlue)),
            if (started) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (at + 1) / s.sentences.length,
                  minHeight: 5,
                  backgroundColor: onBlue.withValues(alpha: 0.28),
                  color: onBlue,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: onBlue,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _listening
                        ? (started ? 'Resume listening' : 'Start listening')
                        : (started ? 'Resume reading' : 'Start reading'),
                    style: V3Type.strong(16, AppearanceColors.blueLight),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    CupertinoIcons.arrow_right,
                    size: 18,
                    color: AppearanceColors.blueLight,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _storyCard(V3Story s, int index) {
    final done = _done.contains(s.id);
    final tints = [
      DesignTokens.primarySoft,
      DesignTokens.masterySoft,
      DesignTokens.successSoft,
    ];
    return V3Pressable(
      key: ValueKey('stories.card.${s.id}'),
      label:
          '${s.title}, ${s.titleEn}, ${s.minutes} minutes${done ? (_listening ? ', listened' : ', read') : ''}',
      onTap: () => _open(s),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DesignTokens.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: DesignTokens.hairline),
          boxShadow: DesignTokens.surfaceShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 78,
              alignment: Alignment.bottomLeft,
              padding: const EdgeInsets.fromLTRB(10, 0, 0, 8),
              decoration: BoxDecoration(
                color: tints[index % tints.length],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                s.title.characters.first,
                style: V3Type.title(34, color: DesignTokens.ink),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title, style: V3Type.strong(18)),
                  const SizedBox(height: 5),
                  Text(
                    '${s.level}  ·  ${s.minutes} min',
                    style: V3Type.body(12.5),
                  ),
                ],
              ),
            ),
            if (done)
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: DesignTokens.successSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  CupertinoIcons.checkmark_alt,
                  size: 15,
                  color: DesignTokens.success,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
