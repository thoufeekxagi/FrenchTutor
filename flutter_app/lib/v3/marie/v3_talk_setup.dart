import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/tutor_persona.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../services/ai_session_gate.dart';
import '../access/v3_access.dart';
import '../ui/v3_ui.dart';
import 'v3_call_screen.dart';
import 'v3_marie_session.dart';

/// The four practice modes. Each is a teaching routine, not a chat topic.
enum V3TalkMode {
  talk('talk', 'Talk it through', 'A focused conversation with gentle fixes.'),
  fix('fix', 'Fix my French', 'Say a sentence. She corrects it. You repeat.'),
  tcf('tcf', 'TCF speaking drill', 'Exam-style tasks, then one thing to fix.'),
  words(
    'words',
    'Words and sounds',
    'Three useful words, said until they land.',
  );

  const V3TalkMode(this.id, this.title, this.subtitle);
  final String id;
  final String title;
  final String subtitle;
}

enum V3TalkFocus {
  everyday('everyday', 'Everyday life'),
  work('work', 'Work and study'),
  canada('canada', 'Life in Canada'),
  exam('exam', 'TCF exam');

  const V3TalkFocus(this.id, this.label);
  final String id;
  final String label;
}

/// Screen: Talk with Marie setup. Key prefix: talk.setup.
///
/// User arrived to: practise speaking with the tutor.
/// They must understand: what each practice does, in one line.
/// Primary action: Start.
/// Secondary action: change the focus or level.
/// Success state: the call screen opens and she starts.
/// Must not contain: delivery styles, free-form topics, or settings sprawl.
class V3TalkSetupScreen extends ConsumerStatefulWidget {
  const V3TalkSetupScreen({super.key});

  @override
  ConsumerState<V3TalkSetupScreen> createState() => _V3TalkSetupScreenState();
}

class _V3TalkSetupScreenState extends ConsumerState<V3TalkSetupScreen> {
  static const _levels = ['A1', 'A2', 'B1', 'B2'];
  var _mode = V3TalkMode.talk;
  var _focus = V3TalkFocus.everyday;
  late String _level;
  var _starting = false;

  @override
  void initState() {
    super.initState();
    final stored = ref
        .read(learningStoreProvider)
        .profile()
        .level
        .toUpperCase();
    _level = _levels.contains(stored) ? stored : 'A2';
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final allowed = await ensureAiSessionQuota(
        context,
        ref.read(pilotAccessServiceProvider),
      );
      if (!allowed || !mounted) return;
      if (!V3Access.premium(ref)) {
        final uses = await V3FreeUsage.uses(V3PracticeKind.marie);
        if (!mounted) return;
        if (V3Access.practiceLocked(uses: uses, premium: false)) {
          final unlocked = await V3Access.openPaywall(
            context,
            ref,
            source: 'marie_locked',
          );
          if (!unlocked || !mounted) return;
        } else {
          await V3FreeUsage.recordUse(V3PracticeKind.marie);
          if (!mounted) return;
        }
      }
      final tutor = ActiveTutor.current;
      final store = ref.read(learningStoreProvider);
      await AppRouter.push<void>(
        context,
        (_) => V3CallScreen(
          title: _mode.title,
          subtitle: '${tutor.displayName} · $_level · ${_focus.label}',
          stage: 'free_talk',
          topic: '${_mode.title} · ${_focus.label}',
          createSession: () => V3MarieSession.createCall(
            store: () => store,
            context: () => '',
            systemPrompt: LivePrompts.talkTutor(
              persona: tutor,
              level: _level,
              mode: _mode.id,
              focus: _focus.id,
            ),
            opening: LivePrompts.talkOpening(
              mode: _mode.id,
              focus: _focus.label,
            ),
            reminder: LivePrompts.talkModeReminder(_mode.id),
            idleLimit: const Duration(seconds: 150),
          ),
        ),
        fullscreenDialog: true,
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = ActiveTutor.current.displayName;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.35,
      child: Scaffold(
        backgroundColor: DesignTokens.canvas,
        body: V3Width(
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: V3Pressable(
                          key: const ValueKey('talk.setup.back'),
                          label: 'Back',
                          onTap: () => Navigator.of(context).maybePop(),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(
                              CupertinoIcons.back,
                              size: 22,
                              color: DesignTokens.ink,
                            ),
                          ),
                        ),
                      ),
                      Text('SPEAKING PRACTICE', style: V3Type.eyebrow()),
                      const SizedBox(height: 6),
                      Text('Practise with $name', style: V3Type.hero(32)),
                      const SizedBox(height: 20),
                      for (final m in V3TalkMode.values) ...[
                        V3OptionCard(
                          key: ValueKey('talk.setup.mode.${m.id}'),
                          title: m.title,
                          subtitle: m.subtitle,
                          selected: _mode == m,
                          onTap: () => setState(() => _mode = m),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 10),
                      Text('FOCUS', style: V3Type.eyebrow()),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final f in V3TalkFocus.values)
                            _chip(
                              key: ValueKey('talk.setup.focus.${f.id}'),
                              label: f.label,
                              selected: _focus == f,
                              onTap: () => setState(() => _focus = f),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text('LEVEL', style: V3Type.eyebrow()),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final l in _levels)
                            _chip(
                              key: ValueKey('talk.setup.level.$l'),
                              label: l,
                              selected: _level == l,
                              onTap: () => setState(() => _level = l),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: V3Button(
                    key: const ValueKey('talk.setup.start'),
                    label: 'Start',
                    loading: _starting,
                    onTap: _starting ? null : () => unawaited(_start()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return V3Pressable(
      key: key,
      label: label,
      selected: selected,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? DesignTokens.primary : DesignTokens.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? DesignTokens.primary : DesignTokens.hairline,
          ),
        ),
        child: Text(
          label,
          style: V3Type.strong(
            15,
            selected ? DesignTokens.onPrimary : DesignTokens.ink,
          ),
        ),
      ),
    );
  }
}
