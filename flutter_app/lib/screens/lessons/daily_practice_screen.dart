import '../../widgets/adaptive/adaptive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
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
  ConsumerState<DailyPracticeScreen> createState() => _DailyPracticeScreenState();
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
    final allEntries = content.vocabPhases.expand((p) => p.themes.expand((t) => t.entries)).toList();

    _quizPool = pool.map((entry) {
      final distractors = (allEntries.where((e) => e.id != entry.id).toList()..shuffle()).take(2).map((e) => e.en).toList();
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
      backgroundColor: Passeport.parchmentDim,
      appBar: AppBar(
        title: const Text('Daily Practice'),
        backgroundColor: Passeport.parchment,
        foregroundColor: Passeport.text,
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
              Text('${_index + 1} / ${_queue.length}', style: Passeport.mono(11).copyWith(color: Passeport.slateDim)),
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
                Text(entry.en, style: Passeport.display(24), textAlign: TextAlign.center),
                if (_isRevealed) ...[
                  const SizedBox(height: 16),
                  Text(entry.fr, style: Passeport.display(22).copyWith(color: Passeport.maroon)),
                  const SizedBox(height: 6),
                  Text(entry.phonetic, style: Passeport.mono(13).copyWith(color: Passeport.slateDim)),
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
                    Expanded(child: _gradeButton('Again', Passeport.slate, SRSGrade.again)),
                    const SizedBox(width: 10),
                    Expanded(child: _gradeButton('Good', Passeport.brass, SRSGrade.good)),
                    const SizedBox(width: 10),
                    Expanded(child: _gradeButton('Easy', Passeport.maroon, SRSGrade.easy)),
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
      child: Text(title, style: Passeport.body(13.5, weight: FontWeight.w500)),
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
              Text('${_quizIndex + 1} / ${_quizPool.length}', style: Passeport.mono(11).copyWith(color: Passeport.slateDim)),
            ],
          ),
          const SizedBox(height: 18),
          PasseportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What does this mean?', style: Passeport.body(12.5).copyWith(color: Passeport.slateDim)),
                const SizedBox(height: 6),
                Text(item.entry.fr, style: Passeport.display(20)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ...item.choices.map((choice) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _quizSelected == null ? () => _answerQuiz(choice) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Passeport.card,
                      foregroundColor: _quizSelected == null
                          ? Passeport.text
                          : choice == item.entry.en
                              ? Passeport.brass
                              : choice == _quizSelected
                                  ? Passeport.maroon
                                  : Passeport.slate,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Passeport.hairline),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(choice, style: Passeport.body(13.5, weight: FontWeight.w500)),
                        if (_quizSelected != null && choice == item.entry.en) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.check_circle, color: Passeport.brass, size: 18),
                        ],
                        if (_quizSelected != null && choice == _quizSelected && choice != item.entry.en) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.cancel, color: Passeport.maroon, size: 18),
                        ],
                      ],
                    ),
                  ),
                ),
              )),
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
            Icon(Icons.verified, size: 36, color: Passeport.brass),
            const SizedBox(height: 14),
            Text('Daily practice complete', style: Passeport.display(19)),
            const SizedBox(height: 8),
            if (_reviewedEntries.isNotEmpty)
              Text(
                '${_reviewedEntries.length} words reviewed${_quizPool.isEmpty ? '.' : ' · $_quizCorrect/${_quizPool.length} recall correct.'}',
                style: Passeport.body(13).copyWith(color: Passeport.slateDim),
              )
            else
              Text(
                'No new or due words right now — come back tomorrow, or study a specific theme in the Vocabulary lab.',
                style: Passeport.body(13).copyWith(color: Passeport.slateDim),
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
