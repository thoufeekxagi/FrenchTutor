import 'dart:async';
import 'dart:math';

import '../../design/app_router.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../data/database/generated_roleplay_store.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../models/profile.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_card.dart';
import '../pathway/agent_led_listening_screen.dart';

// Fixed scenario categories the learner can tap to steer generation,
// alongside "Surprise me" (fully random) — mirrors the story library's
// topic-chip picker. Each maps to a fuller description fed to the
// generator; the chip label stays short.
const _roleplayScenarioCategories = {
  'Café': 'ordering food and drinks at a café, chatting with the server',
  'Travel': 'a travel scenario, like checking into a hotel or asking about a train or bus',
  'Airport': 'checking in for a flight, going through security, or boarding at an airport',
  'Directions': 'asking a stranger for directions to a nearby place',
  'Shopping': 'shopping for clothes or groceries, asking about sizes, prices, or availability',
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
  const RoleplayLabScreen({super.key});

  @override
  ConsumerState<RoleplayLabScreen> createState() => _RoleplayLabScreenState();
}

class _RoleplayLabScreenState extends ConsumerState<RoleplayLabScreen> {
  bool _generating = false;
  List<GeneratedRoleplay>? _roleplays;
  // null = "Surprise me" (fully random pick each generation).
  String? _selectedScenario;

  @override
  void initState() {
    super.initState();
    _loadRoleplays();
  }

  void _loadRoleplays() {
    final store = ref.read(generatedRoleplayStoreProvider);
    setState(() => _roleplays = store.list());
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
      if (!mounted) return;
      _loadRoleplays();
      await AppRouter.push(
        context,
        (_) => AgentLedListeningScreen(passage: roleplay.passage),
        fullscreenDialog: true,
      );
    } catch (e) {
      debugPrint('RoleplayLabScreen: scene generation failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not generate a scene. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// Synthesizes and caches both sides of every beat's dialogue (the
  /// character's line and the learner's line — the "tap a bubble's speaker
  /// to rehear it" feature in `AgentLedListeningScreen` plays either) right
  /// after the scene is written, so replaying this exact roleplay later
  /// never needs to call the TTS endpoint live again. Fire-and-forget:
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
    if (_selectedScenario != null) {
      return _roleplayScenarioCategories[_selectedScenario]!;
    }
    final pool = [
      ..._roleplayScenarioCategories.values,
      ...profile.interests.map(
        (i) => 'a roleplay scenario related to $i',
      ),
      ..._roleplayScenarios,
    ];
    return pool[Random().nextInt(pool.length)];
  }

  @override
  Widget build(BuildContext context) {
    final roleplays = _roleplays ?? const [];
    final starterRoleplays = ref.watch(contentServiceProvider).starterRoleplays();

    return Scaffold(
      backgroundColor: DesignTokens.parchmentDim,
      appBar: AppBar(
        title: Text('Roleplay', style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.parchmentDim,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        children: [
          _StartRoleplayTile(
            generating: _generating,
            selectedScenario: _selectedScenario,
            onTap: _startRoleplay,
          ),
          const SizedBox(height: 10),
          _ScenarioChipRow(
            selected: _selectedScenario,
            onSelect: (scenario) => setState(() => _selectedScenario = scenario),
          ),
          const SizedBox(height: 20),
          if (roleplays.isNotEmpty) ...[
            const KickerText('Your roleplays', color: DesignTokens.slateDim),
            const SizedBox(height: 10),
            for (final roleplay in roleplays)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RoleplayTile(
                  roleplay: roleplay,
                  onTap: () => AppRouter.push(
                    context,
                    (_) => AgentLedListeningScreen(passage: roleplay.passage),
                    fullscreenDialog: true,
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ] else
            _EmptyRoleplayLibraryNote(),
          if (starterRoleplays.isNotEmpty) ...[
            const SizedBox(height: 8),
            const KickerText('Starter roleplays', color: DesignTokens.slateDim),
            const SizedBox(height: 10),
            for (final roleplay in starterRoleplays)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RoleplayTile(
                  roleplay: roleplay,
                  isStarter: true,
                  onTap: () => AppRouter.push(
                    context,
                    (_) => AgentLedListeningScreen(passage: roleplay.passage),
                    fullscreenDialog: true,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StartRoleplayTile extends StatelessWidget {
  const _StartRoleplayTile({
    required this.generating,
    required this.onTap,
    this.selectedScenario,
  });

  final bool generating;
  final VoidCallback onTap;
  final String? selectedScenario;

  @override
  Widget build(BuildContext context) {
    return PasseportCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: DesignTokens.primarySoft,
            borderRadius: BorderRadius.circular(13),
          ),
          child: generating
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(
                  CupertinoIcons.bubble_left_bubble_right_fill,
                  color: DesignTokens.primary,
                ),
        ),
        title: Text(
          'Start a roleplay',
          style: DesignTokens.body(15, weight: FontWeight.w600),
        ),
        subtitle: Text(
          generating
              ? 'Setting the scene…'
              : selectedScenario != null
              ? 'A fresh $selectedScenario scene'
              : 'A fresh live scene, generated for you',
          style: DesignTokens.body(12.5).copyWith(color: DesignTokens.slateDim),
        ),
        trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
        onTap: generating ? null : onTap,
      ),
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
                color: isSelected ? DesignTokens.primary : DesignTokens.canvasDim,
                borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
              ),
              alignment: Alignment.center,
              child: Text(
                option ?? 'Surprise me',
                style: DesignTokens.body(12.5, weight: FontWeight.w600).copyWith(
                  color: isSelected ? Colors.white : DesignTokens.slateDim,
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
  const _RoleplayTile({
    required this.roleplay,
    required this.onTap,
    this.isStarter = false,
  });

  final GeneratedRoleplay roleplay;
  final VoidCallback onTap;
  final bool isStarter;

  @override
  Widget build(BuildContext context) {
    return PasseportCard(
      padding: 0,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          roleplay.displayTitle,
          style: DesignTokens.body(15, weight: FontWeight.w500),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            isStarter
                ? 'Ready to play'
                : DateFormat('MMM d, HH:mm').format(roleplay.createdAt),
            style: DesignTokens.mono(10.5).copyWith(color: DesignTokens.slateDim),
          ),
        ),
        trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
        onTap: onTap,
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
            color: DesignTokens.slateDim,
            size: 28,
          ),
          const SizedBox(height: 10),
          Text(
            'No roleplays of your own yet, start one above, or try a starter scene below',
            textAlign: TextAlign.center,
            style: DesignTokens.body(13).copyWith(color: DesignTokens.slateDim),
          ),
        ],
      ),
    );
  }
}
