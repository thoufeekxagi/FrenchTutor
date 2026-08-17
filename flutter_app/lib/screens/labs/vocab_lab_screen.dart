import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../widgets/learning_card.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/responsive_card_grid.dart';
import '../../widgets/web/web_constrained_view.dart';
import '../lessons/vocabulary_workshop_screen.dart';
import '../pathway/vocab_picker_screen.dart';

/// The vocabulary library uses the same image-backed five-per-row card system
/// as Reading and Listening. The old bundled phase browser is intentionally
/// not rendered here; generated/assigned learner content is the source.
class VocabLabScreen extends ConsumerStatefulWidget {
  const VocabLabScreen({super.key, this.topic});

  final String? topic;

  @override
  ConsumerState<VocabLabScreen> createState() => _VocabLabScreenState();
}

class _VocabLabScreenState extends ConsumerState<VocabLabScreen> {
  List<GeneratedVocabularySet> _sets = const [];

  @override
  void initState() {
    super.initState();
    _load();
    unawaited(_refresh());
  }

  void _load() {
    if (!mounted) return;
    setState(
      () => _sets = ref.read(generatedVocabularySetStoreProvider).list(),
    );
  }

  Future<void> _refresh() async {
    try {
      await ref.read(syncServiceProvider).hydrateGeneratedVocabularySets();
    } catch (error, stackTrace) {
      debugPrint('Vocabulary hydration failed: $error\n$stackTrace');
    }
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.topic == null || widget.topic!.trim().isEmpty
        ? _sets
        : _sets
              .where(
                (set) => set.topic.toLowerCase() == widget.topic!.toLowerCase(),
              )
              .toList();

    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        title: Text('Vocabulary', style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.canvas,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: WebConstrainedView(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text('Words you can use next.', style: DesignTokens.display(28)),
            const SizedBox(height: 8),
            Text(
              'Open a short set, hear each word, and practise it in context.',
              style: DesignTokens.body(15).copyWith(color: DesignTokens.muted),
            ),
            const SizedBox(height: 18),
            PrimaryActionButton(
              label: 'Choose or generate a vocabulary session',
              icon: CupertinoIcons.sparkles,
              onPressed: () async {
                await AppRouter.push(
                  context,
                  (_) => const VocabPickerScreen(),
                  fullscreenDialog: true,
                );
                if (mounted) _load();
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Auto uses recent context and source vocabulary. You can also choose a category yourself.',
              style: DesignTokens.body(
                12,
              ).copyWith(color: DesignTokens.mutedDim),
            ),
            const SizedBox(height: 24),
            if (visible.isEmpty)
              const _EmptyVocabularyLibrary()
            else
              ResponsiveCardGrid(
                itemCount: visible.length,
                maxCardWidth: 176,
                mainAxisExtent: 294,
                itemBuilder: (context, index) {
                  final set = visible[index];
                  return _VocabularyCard(
                    set: set,
                    onTap: () => AppRouter.push(
                      context,
                      (_) => VocabularyWorkshopScreen(
                        phase: 1,
                        theme: set.asTheme,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _VocabularyCard extends StatelessWidget {
  const _VocabularyCard({required this.set, required this.onTap});

  final GeneratedVocabularySet set;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LearningCard(
      padding: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(DesignTokens.radiusCard),
              ),
              child: _VocabularyCover(source: set.coverUrl),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    set.topic.toUpperCase(),
                    style: DesignTokens.mono(
                      9.5,
                      weight: FontWeight.w700,
                    ).copyWith(color: DesignTokens.primary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    set.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.body(15, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${set.entries.length} words  •  ${set.levelBand}',
                    style: DesignTokens.body(
                      11,
                    ).copyWith(color: DesignTokens.mutedDim),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VocabularyCover extends StatelessWidget {
  const _VocabularyCover({required this.source});

  final String? source;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      height: 172,
      decoration: const BoxDecoration(gradient: DesignTokens.heroGradient),
      child: const Center(
        child: Icon(CupertinoIcons.textformat, color: Colors.white, size: 34),
      ),
    );
    if (source == null || source!.isEmpty) return fallback;
    if (source!.startsWith('asset:')) {
      return Image.asset(
        source!.substring('asset:'.length),
        width: double.infinity,
        height: 172,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return Image.network(
      source!,
      width: double.infinity,
      height: 172,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

class _EmptyVocabularyLibrary extends StatelessWidget {
  const _EmptyVocabularyLibrary();

  @override
  Widget build(BuildContext context) {
    return LearningCard(
      child: Column(
        children: [
          const Icon(
            CupertinoIcons.textformat,
            color: DesignTokens.primary,
            size: 30,
          ),
          const SizedBox(height: 10),
          Text(
            'Your vocabulary sets are preparing…',
            textAlign: TextAlign.center,
            style: DesignTokens.body(16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Return to this tab in a moment and your starter cards will be ready.',
            textAlign: TextAlign.center,
            style: DesignTokens.body(13).copyWith(color: DesignTokens.muted),
          ),
        ],
      ),
    );
  }
}
