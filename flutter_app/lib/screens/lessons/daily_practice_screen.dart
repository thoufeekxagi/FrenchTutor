import '../../widgets/adaptive/adaptive.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../design/tokens.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../providers/database_provider.dart';
import '../../models/content_models.dart';
import '../../models/srs_state.dart';

enum _DailyStage { review, quiz, summary }

class DailyPracticeScreen extends ConsumerStatefulWidget {
  const DailyPracticeScreen({super.key});

  @override
  ConsumerState<DailyPracticeScreen> createState() =>
      _DailyPracticeScreenState();
}

class _DailyPracticeScreenState extends ConsumerState<DailyPracticeScreen> {
  _DailyStage _stage = _DailyStage.review;
  List<VocabEntry> _queue = [];
  int _index = 0;
  bool _isRevealed = false;
  final List<VocabEntry> _reviewedEntries = [];
  List<_QuizItem> _quizPool = [];
  int _quizIndex = 0;
  int _quizCorrect = 0;
  String? _quizSelected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final srs = ref.read(srsServiceProvider);
      srs.dailyMixedQueue().then((queue) {
        setState(() {
          _queue = queue;
          if (_queue.isEmpty) _buildQuiz();
        });
      });
    });
  }

  void _buildQuiz() {
    final srs = ref.read(srsServiceProvider);
    final pool = srs.knownSample(limit: 5);
    final content = ref.read(contentServiceProvider);
    final allEntries = content.vocabPhases
        .expand((p) => p.themes.expand((t) => t.entries))
        .toList();

    _quizPool = pool.map((entry) {
      final distractors =
          (allEntries.where((e) => e.id != entry.id).toList()..shuffle())
              .take(2)
              .map((e) => e.en)
              .toList();
      final choices = [...distractors, entry.en]..shuffle();
      return _QuizItem(entry: entry, choices: choices);
    }).toList();

    _quizIndex = 0;
    _quizCorrect = 0;
    _quizSelected = null;
    setState(() {
      _stage = _quizPool.isEmpty ? _DailyStage.summary : _DailyStage.quiz;
    });
  }

  void _grade(SRSGrade grade) {
    if (_index >= _queue.length) return;
    final entry = _queue[_index];
    ref.read(srsServiceProvider).grade(entryId: entry.id, grade: grade);
    _reviewedEntries.add(entry);
    setState(() {
      _isRevealed = false;
      _index++;
      if (_index >= _queue.length) _buildQuiz();
    });
  }

  void _answerQuiz(String choice) {
    if (_quizIndex >= _quizPool.length) return;
    final item = _quizPool[_quizIndex];
    setState(() {
      _quizSelected = choice;
      if (choice == item.entry.en) _quizCorrect++;
    });
  }

  void _nextQuiz() {
    setState(() {
      _quizIndex++;
      _quizSelected = null;
      if (_quizIndex >= _quizPool.length) _stage = _DailyStage.summary;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.parchmentDim,
      appBar: AppBar(
        title: const Text('Daily Practice'),
        backgroundColor: DesignTokens.parchment,
        foregroundColor: DesignTokens.text,
        elevation: 0,
      ),
      body: SafeArea(
        child: switch (_stage) {
          _DailyStage.review => _reviewBody(),
          _DailyStage.quiz => _quizBody(),
          _DailyStage.summary => _summaryBody(),
        },
      ),
    );
  }

  Widget _reviewBody() {
    if (_index >= _queue.length) {
      return const Center(child: PSProgressIndicator());
    }
    final entry = _queue[_index];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Row(
            children: [
              const KickerText("TODAY'S REVIEW"),
              const Spacer(),
              Text(
                '${_index + 1} / ${_queue.length}',
                style: DesignTokens.mono(
                  11,
                ).copyWith(color: DesignTokens.slateDim),
              ),
            ],
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: PasseportCard(
            padding: 28,
            child: Column(
              children: [
                Text(
                  entry.en,
                  style: DesignTokens.display(24),
                  textAlign: TextAlign.center,
                ),
                if (_isRevealed) ...[
                  const SizedBox(height: 16),
                  Text(
                    entry.fr,
                    style: DesignTokens.display(
                      22,
                    ).copyWith(color: DesignTokens.primary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    entry.phonetic,
                    style: DesignTokens.mono(
                      13,
                    ).copyWith(color: DesignTokens.slateDim),
                  ),
                ],
              ],
            ),
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          child: _isRevealed
              ? Row(
                  children: [
                    Expanded(
                      child: _gradeButton(
                        'Again',
                        DesignTokens.slate,
                        SRSGrade.again,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _gradeButton(
                        'Good',
                        DesignTokens.info,
                        SRSGrade.good,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _gradeButton(
                        'Easy',
                        DesignTokens.primary,
                        SRSGrade.easy,
                      ),
                    ),
                  ],
                )
              : PasseportPrimaryButton(
                  label: 'Reveal',
                  onPressed: () => setState(() => _isRevealed = true),
                ),
        ),
      ],
    );
  }

  Widget _gradeButton(String title, Color color, SRSGrade grade) {
    return ElevatedButton(
      onPressed: () => _grade(grade),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
      child: Text(
        title,
        style: DesignTokens.body(13.5, weight: FontWeight.w500),
      ),
    );
  }

  Widget _quizBody() {
    if (_quizIndex >= _quizPool.length) return const SizedBox();
    final item = _quizPool[_quizIndex];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Row(
            children: [
              const KickerText('QUICK RECALL CHECK'),
              const Spacer(),
              Text(
                '${_quizIndex + 1} / ${_quizPool.length}',
                style: DesignTokens.mono(
                  11,
                ).copyWith(color: DesignTokens.slateDim),
              ),
            ],
          ),
          const SizedBox(height: 18),
          PasseportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What does this mean?',
                  style: DesignTokens.body(
                    12.5,
                  ).copyWith(color: DesignTokens.slateDim),
                ),
                const SizedBox(height: 6),
                Text(item.entry.fr, style: DesignTokens.display(20)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ...item.choices.map(
            (choice) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _quizSelected == null
                      ? () => _answerQuiz(choice)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DesignTokens.card,
                    foregroundColor: _quizSelected == null
                        ? DesignTokens.text
                        : choice == item.entry.en
                        ? DesignTokens.info
                        : choice == _quizSelected
                        ? DesignTokens.primary
                        : DesignTokens.slate,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: DesignTokens.hairline),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        choice,
                        style: DesignTokens.body(13.5, weight: FontWeight.w500),
                      ),
                      if (_quizSelected != null && choice == item.entry.en) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: DesignTokens.success,
                          size: 18,
                        ),
                      ],
                      if (_quizSelected != null &&
                          choice == _quizSelected &&
                          choice != item.entry.en) ...[
                        const SizedBox(width: 8),
                        Icon(
                          CupertinoIcons.xmark_circle_fill,
                          color: DesignTokens.primary,
                          size: 18,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_quizSelected != null)
            PasseportPrimaryButton(
              label: _quizIndex + 1 < _quizPool.length ? 'Next' : 'Finish',
              onPressed: _nextQuiz,
            ),
        ],
      ),
    );
  }

  Widget _summaryBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.checkmark_seal_fill,
              size: 36,
              color: DesignTokens.info,
            ),
            const SizedBox(height: 14),
            Text('Daily practice complete', style: DesignTokens.display(19)),
            const SizedBox(height: 8),
            if (_reviewedEntries.isNotEmpty)
              Text(
                '${_reviewedEntries.length} words reviewed${_quizPool.isEmpty ? '.' : ' · $_quizCorrect/${_quizPool.length} recall correct.'}',
                style: DesignTokens.body(
                  13,
                ).copyWith(color: DesignTokens.slateDim),
              )
            else
              Text(
                'No new or due words right now — come back tomorrow, or study a specific theme in the Vocabulary lab.',
                style: DesignTokens.body(
                  13,
                ).copyWith(color: DesignTokens.slateDim),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: 200,
              child: PasseportPrimaryButton(
                label: 'Done',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuizItem {
  _QuizItem({required this.entry, required this.choices});
  final VocabEntry entry;
  final List<String> choices;
}
