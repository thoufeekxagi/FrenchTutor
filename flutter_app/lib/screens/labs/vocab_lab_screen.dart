import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../utils/vocabulary_set_copy.dart';
import '../../widgets/learning_card.dart';
import '../../widgets/practice_content_card.dart';
import '../../widgets/responsive_card_grid.dart';
import '../../widgets/web/web_constrained_view.dart';
import '../lessons/vocabulary_workshop_screen.dart';
import '../pathway/vocab_picker_screen.dart';
import '../../widgets/v3/v3_surface.dart';

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

    return V3Scaffold(
      child: WebConstrainedView(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            V3Header(
              title: 'Vocabulary',
              subtitle: 'Words you can use next.',
              leading: const V3BackButton(),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 14),
            const SizedBox(height: 8),
            Text(
              'Open a short set, hear each word, and practise it in context.',
              style: DesignTokens.body(
                15,
              ).copyWith(color: DesignTokens.nightMuted, height: 1.35),
            ),
            const SizedBox(height: 18),
            V3PrimaryButton(
              label: 'Choose or generate a vocabulary session',
              icon: Icons.auto_awesome_rounded,
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
              ).copyWith(color: DesignTokens.nightMuted),
            ),
            const SizedBox(height: 24),
            if (visible.isEmpty)
              const _EmptyVocabularyLibrary()
            else
              ResponsiveCardGrid(
                itemCount: visible.length,
                maxColumns: 5,
                maxCardWidth: 176,
                mainAxisExtent: 292,
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
    final title = VocabularySetCopy.title(set);
    final summary = VocabularySetCopy.summary(set, displayedTitle: title);
    return PracticeContentCard(
      title: title,
      summary: summary,
      levelBand: set.levelBand,
      meta: '${set.entries.length} words',
      coverUrl: set.coverUrl,
      fallbackIcon: CupertinoIcons.textformat,
      onTap: onTap,
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
