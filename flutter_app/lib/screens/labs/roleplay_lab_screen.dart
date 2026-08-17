import 'dart:async';
import 'dart:math';

import '../../design/app_router.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../data/database/generated_roleplay_store.dart';
import '../../design/tokens.dart';
import '../../flow/stage_outcome.dart';
import '../../models/content_models.dart';
import '../../models/profile.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/responsive_card_grid.dart';
import '../../widgets/web/web_constrained_view.dart';
import '../pathway/agent_led_listening_screen.dart';
import '../pathway/roleplay_review_screen.dart';

// Fixed scenario categories the learner can tap to steer generation,
// alongside "Surprise me" (fully random) — mirrors the story library's
// topic-chip picker. Each maps to a fuller description fed to the
// generator; the chip label stays short.
const _roleplayScenarioCategories = {
  'Café': 'ordering food and drinks at a café, chatting with the server',
  'Travel':
      'a travel scenario, like checking into a hotel or asking about a train or bus',
  'Airport':
      'checking in for a flight, going through security, or boarding at an airport',
  'Directions': 'asking a stranger for directions to a nearby place',
  'Shopping':
      'shopping for clothes or groceries, asking about sizes, prices, or availability',
};

// Fallback pool for when nothing's picked and there's no relevant onboarding
// interest to draw on — mirrors the story library's `_storyTopics`.
const _roleplayScenarios = [
  'ordering food at a small restaurant',
  'checking into a hotel after a long trip',
  'asking for directions to the train station',
  'buying a ticket at a station kiosk',
  'shopping for a gift at a local market',
  'meeting a new neighbour for the first time',
];

/// A standalone roleplay practice lab — pick (or randomize) a real-life
/// scenario and get a freshly generated scene, walked through in the same
/// live, button-only, drift-corrected screen already built for missions
/// (`AgentLedListeningScreen`, which acts as both the in-character partner
/// and the tutor). Every generated scene is saved to the learner's own
/// roleplay library so it can be replayed later, exactly like the story
/// library saves generated stories — never generate-and-discard.
class RoleplayLabScreen extends ConsumerStatefulWidget {
  const RoleplayLabScreen({super.key, this.topic, this.autoStart = false});

  final String? topic;
  final bool autoStart;

  @override
  ConsumerState<RoleplayLabScreen> createState() => _RoleplayLabScreenState();
}

class _RoleplayLabScreenState extends ConsumerState<RoleplayLabScreen> {
  bool _generating = false;
  List<GeneratedRoleplay>? _roleplays;
  final Set<String> _coverAttempts = <String>{};
  // null = "Surprise me" (fully random pick each generation).
  String? _selectedScenario;

  @override
  void initState() {
    super.initState();
    _loadRoleplays();
    unawaited(_refreshRoleplays());
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_startRoleplay());
      });
    }
  }

  void _loadRoleplays() {
    if (!mounted) return;
    final store = ref.read(generatedRoleplayStoreProvider);
    setState(() => _roleplays = store.list());
  }

  Future<void> _refreshRoleplays() async {
    try {
      await ref.read(syncServiceProvider).hydrateGeneratedRoleplays();
    } catch (error, stackTrace) {
      debugPrint('Roleplay hydration failed: $error\n$stackTrace');
    }
    if (mounted) {
      _loadRoleplays();
      // A scene is useful without artwork, so cover generation is deliberately
      // asynchronous. Repair any saved roleplays whose previous image request
      // or upload was interrupted instead of leaving a permanent placeholder.
      unawaited(_retryMissingRoleplayCovers());
    }
  }

  Future<void> _retryMissingRoleplayCovers() async {
    final missing = ref
        .read(generatedRoleplayStoreProvider)
        .list()
        .where(
          (roleplay) => roleplay.coverUrl == null || roleplay.coverUrl!.isEmpty,
        )
        .take(6)
        .toList();
    for (final roleplay in missing) {
      await _generateRoleplayCover(roleplay);
    }
  }

  Future<void> _startRoleplay() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final profile = ref.read(learningStoreProvider).profile();
      final scene = await LessonAgentService.shared.buildStandaloneRoleplay(
        scenario: _scenarioFor(profile),
        levelBand: profile.level,
      );
      final roleplay = GeneratedRoleplay(
        id: newGeneratedRoleplayId(),
        passage: scene,
        createdAt: DateTime.now(),
      );
      ref.read(generatedRoleplayStoreProvider).insert(roleplay);
      unawaited(_prewarmNarration(roleplay));
      // Artwork is deliberately independent of scene generation and live
      // practice. The learner can start immediately while the private cover
      // is generated and attached to the library card in the background.
      unawaited(_generateRoleplayCover(roleplay));
      if (!mounted) return;
      _loadRoleplays();
      final completed = await _openRoleplay(roleplay);
      if (widget.autoStart && mounted) {
        Navigator.of(context).pop(completed);
      }
    } catch (e) {
      debugPrint('RoleplayLabScreen: scene generation failed: $e');
      if (mounted) {
        if (widget.autoStart) {
          Navigator.of(context).pop(false);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not generate a scene. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _generateRoleplayCover(GeneratedRoleplay roleplay) async {
    if (!_coverAttempts.add(roleplay.id)) return;
    // Capture provider-backed services before the route can be popped. Cover
    // generation intentionally outlives the live practice route when needed.
    final sync = ref.read(syncServiceProvider);
    final store = ref.read(generatedRoleplayStoreProvider);
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final bytes = await LessonAgentService.shared.generateStoryCover(
          title: roleplay.displayTitle,
          summary: roleplay.passage.segments
              .take(2)
              .map((segment) => segment.en.isNotEmpty ? segment.en : segment.fr)
              .join(' '),
          topic: roleplay.displayTitle,
          levelBand: 'A1',
          coverPrompt:
              'A premium editorial cover for a French language roleplay scene. '
              'Show one cinematic real-life moment that matches the title and dialogue. '
              'Make it feel like a published language-learning book, with human-scale '
              'characters and a clear setting, never an app screenshot or cartoon.',
        );
        final url = await sync.uploadStoryCover(
          storyId: roleplay.id,
          bytes: bytes,
        );
        if (url == null || url.isEmpty) {
          throw StateError('cover upload returned no signed URL');
        }
        store.updateCoverUrl(roleplay.id, url);
        if (mounted) _loadRoleplays();
        return;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: 2 << attempt));
        }
      }
    }
    debugPrint(
      'Roleplay cover generation failed after 3 attempts: $lastError\n$lastStackTrace',
    );
  }

  /// Synthesizes and caches both sides of every beat's dialogue (the
  /// character's line and the learner's line — the "tap a bubble's speaker
  /// to rehear it" feature in `AgentLedListeningScreen` plays either) right
  /// after the scene is written, so replaying this exact roleplay later
  /// never needs to call Gemini Live again. Fire-and-forget:
  /// a partial failure just means those specific lines re-synthesize (with
  /// the same retry) the first time they're actually tapped.
  Future<void> _prewarmNarration(GeneratedRoleplay roleplay) {
    final segments = roleplay.passage.segments;
    final items = <SpeechItem>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (segment.characterFr?.isNotEmpty ?? false) {
        items.add(
          SpeechItem(
            text: segment.characterFr!,
            language: 'fr-FR',
            contentItemId: '${roleplay.id}_seg${i}_char',
          ),
        );
      }
      if (segment.fr.isNotEmpty) {
        items.add(
          SpeechItem(
            text: segment.fr,
            language: 'fr-FR',
            contentItemId: '${roleplay.id}_seg${i}_learner',
          ),
        );
      }
    }
    return LessonSpeechService.shared.prewarmNarration(items);
  }

  /// If the learner tapped a scenario chip, use its full description
  /// directly. Otherwise pick fully at random from a pool mixing the fixed
  /// categories, the onboarding interests, and the generic fallback pool as
  /// equal citizens — same rationale as the story library's `_topicFor`.
  String _scenarioFor(Profile profile) {
    if (widget.topic != null && widget.topic!.trim().isNotEmpty) {
      return widget.topic!;
    }
    if (_selectedScenario != null) {
      return _roleplayScenarioCategories[_selectedScenario]!;
    }
    final pool = [
      ..._roleplayScenarioCategories.values,
      ...profile.interests.map((i) => 'a roleplay scenario related to $i'),
      ..._roleplayScenarios,
    ];
    return pool[Random().nextInt(pool.length)];
  }

  Future<bool> _openRoleplay(GeneratedRoleplay roleplay) async {
    final outcome = await AppRouter.push<StageOutcome<ListeningStageResult>>(
      context,
      (_) => AgentLedListeningScreen(
        passage: roleplay.passage,
        noteContext: 'Roleplay',
        sessionStage: 'roleplay',
        sessionTopic: roleplay.displayTitle,
      ),
      fullscreenDialog: true,
    );
    if (!mounted || outcome == null || !outcome.isCompleted) return false;
    await AppRouter.push(
      context,
      (_) => RoleplayReviewScreen(roleplay: roleplay),
      fullscreenDialog: true,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.autoStart) {
      return Scaffold(
        backgroundColor: DesignTokens.canvasDim,
        appBar: AppBar(
          title: Text('Roleplay', style: DesignTokens.display(20)),
          backgroundColor: DesignTokens.canvasDim,
          elevation: 0,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    final roleplays = _roleplays ?? const [];

    return Scaffold(
      backgroundColor: DesignTokens.canvasDim,
      appBar: AppBar(
        title: Text('Roleplay', style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.canvasDim,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: WebConstrainedView(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          children: [
            _RoleplayStartSection(
              generating: _generating,
              onTap: _startRoleplay,
            ),
            const SizedBox(height: 14),
            _ScenarioChipRow(
              selected: _selectedScenario,
              onSelect: (scenario) =>
                  setState(() => _selectedScenario = scenario),
            ),
            const SizedBox(height: 20),
            if (roleplays.isNotEmpty) ...[
              const KickerText('Your roleplays', color: DesignTokens.mutedDim),
              const SizedBox(height: 10),
              ResponsiveCardGrid(
                mainAxisExtent: 280,
                itemCount: roleplays.length,
                itemBuilder: (context, index) {
                  final roleplay = roleplays[index];
                  return _RoleplayTile(
                    roleplay: roleplay,
                    onTap: () => _openRoleplay(roleplay),
                  );
                },
              ),
            ] else
              _EmptyRoleplayLibraryNote(),
          ],
        ),
      ),
    );
  }
}

class _RoleplayStartSection extends StatelessWidget {
  const _RoleplayStartSection({required this.generating, required this.onTap});

  final bool generating;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Practice a real situation', style: DesignTokens.display(26)),
        const SizedBox(height: 6),
        Text(
          'Choose the moment you want to rehearse. Marie sets the scene, teaches one turn at a time, and lets you try it for yourself.',
          style: DesignTokens.body(
            13.5,
          ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
        ),
        const SizedBox(height: 18),
        PrimaryActionButton(
          label: generating ? 'Setting the scene…' : 'Build roleplay',
          icon: CupertinoIcons.play_fill,
          isLoading: generating,
          onPressed: generating ? null : onTap,
        ),
      ],
    );
  }
}

/// "Surprise me" (random pick, the default) plus the fixed scenario
/// categories — tapping one steers generation toward it; tapping it again
/// (or "Surprise me") clears the pick back to fully random.
class _ScenarioChipRow extends StatelessWidget {
  const _ScenarioChipRow({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final options = <String?>[null, ..._roleplayScenarioCategories.keys];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          final isSelected = option == selected;
          return GestureDetector(
            onTap: () => onSelect(isSelected ? null : option),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected
                    ? DesignTokens.primary
                    : DesignTokens.canvasDim,
                borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
              ),
              alignment: Alignment.center,
              child: Text(
                option ?? 'Surprise me',
                style: DesignTokens.body(12.5, weight: FontWeight.w600)
                    .copyWith(
                      color: isSelected ? Colors.white : DesignTokens.mutedDim,
                    ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RoleplayTile extends StatelessWidget {
  const _RoleplayTile({required this.roleplay, required this.onTap});

  final GeneratedRoleplay roleplay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ModernCard(
        padding: 0,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 280,
          child: Column(
            children: [
              _RoleplayCover(
                roleplay: roleplay,
                width: double.infinity,
                height: 166,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YOUR ROLEPLAY',
                        style: DesignTokens.mono(10, weight: FontWeight.w700)
                            .copyWith(
                              color: DesignTokens.primary,
                              letterSpacing: 0.8,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        roleplay.displayTitle,
                        style: DesignTokens.display(17),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${DateFormat('MMM d, HH:mm').format(roleplay.createdAt)} · ${roleplay.passage.segments.length} turns',
                        style: DesignTokens.mono(
                          10.5,
                        ).copyWith(color: DesignTokens.mutedDim),
                      ),
                      const SizedBox(height: 13),
                      Row(
                        children: [
                          const Icon(CupertinoIcons.play_fill, size: 13),
                          const SizedBox(width: 6),
                          Text(
                            'Open roleplay',
                            style: DesignTokens.body(
                              12.5,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleplayCover extends StatelessWidget {
  const _RoleplayCover({
    required this.roleplay,
    required this.width,
    required this.height,
  });

  final GeneratedRoleplay roleplay;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final url = roleplay.coverUrl;
    final fallback = Container(
      decoration: const BoxDecoration(gradient: DesignTokens.heroGradient),
      child: const Center(
        child: Icon(
          CupertinoIcons.bubble_left_bubble_right_fill,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(DesignTokens.radiusMedium),
        ),
        child: url != null && url.startsWith('asset:')
            ? Image.asset(
                url.substring('asset:'.length),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              )
            : url == null || url.isEmpty
            ? fallback
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _EmptyRoleplayLibraryNote extends StatelessWidget {
  const _EmptyRoleplayLibraryNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const Icon(
            CupertinoIcons.bubble_left_bubble_right,
            color: DesignTokens.mutedDim,
            size: 28,
          ),
          const SizedBox(height: 10),
          Text(
            'No roleplays yet. Start one above to build your library.',
            textAlign: TextAlign.center,
            style: DesignTokens.body(13).copyWith(color: DesignTokens.mutedDim),
          ),
        ],
      ),
    );
  }
}
