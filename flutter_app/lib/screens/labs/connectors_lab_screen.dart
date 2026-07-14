import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../services/lesson_speech_service.dart';

class ConnectorsLabScreen extends ConsumerStatefulWidget {
  const ConnectorsLabScreen({super.key});

  @override
  ConsumerState<ConnectorsLabScreen> createState() => _ConnectorsLabScreenState();
}

class _ConnectorsLabScreenState extends ConsumerState<ConnectorsLabScreen> {
  @override
  void dispose() {
    LessonSpeechService.shared.deactivate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pack = ref.watch(contentServiceProvider).connectors();

    return Scaffold(
      backgroundColor: Passeport.parchmentDim,
      appBar: AppBar(
        title: Text('Connectors', style: Passeport.display(20)),
        backgroundColor: Passeport.parchmentDim,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: pack == null
          ? Center(
              child: Text(
                'Connectors content unavailable.',
                style: Passeport.body(13).copyWith(color: Passeport.slateDim),
              ),
            )
          : _buildContent(pack),
    );
  }

  Widget _buildContent(ConnectorsPack pack) {
    final categories = _orderedCategories(pack.connectors);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      children: [
        Text(
          pack.tip,
          style: Passeport.body(12.5).copyWith(color: Passeport.slateDim),
        ),
        const SizedBox(height: 16),
        PasseportPrimaryButton(
          label: 'Take the 10-question quiz',
          onPressed: () => _showQuiz(pack.connectors),
        ),
        const SizedBox(height: 16),
        for (final category in categories) ...[
          KickerText(category, color: Passeport.slateDim),
          const SizedBox(height: 8),
          PasseportCard(
            padding: 10,
            child: Column(
              children: _buildCategoryRows(
                pack.connectors.where((c) => c.category == category).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  List<String> _orderedCategories(List<Connector> connectors) {
    final seen = <String>[];
    for (final c in connectors) {
      if (!seen.contains(c.category)) seen.add(c.category);
    }
    return seen;
  }

  List<Widget> _buildCategoryRows(List<Connector> items) {
    final widgets = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      widgets.add(_connectorRow(items[i]));
      if (i < items.length - 1) {
        widgets.add(Divider(color: Passeport.hairline, height: 1));
      }
    }
    return widgets;
  }

  Widget _connectorRow(Connector connector) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      connector.fr,
                      style: Passeport.body(13.5, weight: FontWeight.w500),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      connector.en,
                      style: Passeport.mono(10.5).copyWith(color: Passeport.slateDim),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  connector.example.fr,
                  style: Passeport.body(11.5).copyWith(
                    color: Passeport.slateDim,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            icon: Icon(Icons.volume_up, size: 16, color: Passeport.brass),
            onPressed: () {
              LessonSpeechService.shared.speak(
                items: [SpeechItem(text: connector.example.fr, language: 'fr-FR')],
              );
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  void _showQuiz(List<Connector> connectors) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => _ConnectorsQuizView(
          connectors: connectors,
          learningStore: ref.read(learningStoreProvider),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connectors Quiz
// ---------------------------------------------------------------------------

class _QuizQuestion {
  final Connector connector;
  final List<String> choices;
  _QuizQuestion({required this.connector, required this.choices});
}

class _ConnectorsQuizView extends StatefulWidget {
  const _ConnectorsQuizView({
    required this.connectors,
    required this.learningStore,
  });

  final List<Connector> connectors;
  final dynamic learningStore; // LearningStore

  @override
  State<_ConnectorsQuizView> createState() => _ConnectorsQuizViewState();
}

class _ConnectorsQuizViewState extends State<_ConnectorsQuizView> {
  late List<_QuizQuestion> _questions;
  int _index = 0;
  int _correctCount = 0;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _buildQuestions();
  }

  void _buildQuestions() {
    final rng = Random();
    final pool = List<Connector>.from(widget.connectors)..shuffle(rng);
    final picked = pool.take(10).toList();
    _questions = picked.map((connector) {
      final distractors = widget.connectors
          .where((c) => c.id != connector.id)
          .toList()
        ..shuffle(rng);
      final choices = distractors.take(2).map((c) => c.fr).toList()
        ..add(connector.fr)
        ..shuffle(rng);
      return _QuizQuestion(connector: connector, choices: choices);
    }).toList();
  }

  void _answer(String choice) {
    if (_selected != null) return;
    setState(() {
      _selected = choice;
      if (choice == _questions[_index].connector.fr) {
        _correctCount++;
      }
    });
  }

  void _next() {
    setState(() {
      _index++;
      _selected = null;
      if (_index == _questions.length) {
        _saveResult();
      }
    });
  }

  void _saveResult() {
    final score = _questions.isEmpty ? 0.0 : _correctCount / _questions.length;
    widget.learningStore.setLessonStatus(
      'connectors_quiz',
      score >= 0.7 ? 'completed' : 'in_progress',
      score: score,
    );
  }

  Color _choiceColor(String choice, _QuizQuestion q) {
    if (choice == q.connector.fr) return Passeport.brass;
    if (choice == _selected) return Passeport.maroon;
    return Passeport.slate;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Passeport.parchmentDim,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Passeport.slate,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                Text('Connectors quiz', style: Passeport.display(18)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Close', style: Passeport.body(14).copyWith(color: Passeport.maroon)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Body
          Expanded(
            child: _index < _questions.length ? _quizCard() : _resultCard(),
          ),
        ],
      ),
    );
  }

  Widget _quizCard() {
    final q = _questions[_index];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Center(
            child: Text(
              '${_index + 1} / ${_questions.length}',
              style: Passeport.mono(11).copyWith(color: Passeport.slateDim),
            ),
          ),
          const SizedBox(height: 18),
          PasseportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Which connector means:',
                  style: Passeport.body(12.5).copyWith(color: Passeport.slateDim),
                ),
                const SizedBox(height: 6),
                Text(
                  q.connector.en,
                  style: Passeport.display(18, weight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ...q.choices.map((choice) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _selected == null ? () => _answer(choice) : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _selected == null ? Passeport.text : _choiceColor(choice, q),
                      backgroundColor: Passeport.card,
                      side: BorderSide(color: Passeport.hairline),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: Passeport.body(13.5, weight: FontWeight.w500),
                    ),
                    child: Text(choice),
                  ),
                ),
              )),
          if (_selected != null) ...[
            const SizedBox(height: 8),
            PasseportPrimaryButton(
              label: _index + 1 < _questions.length ? 'Next' : 'See results',
              onPressed: _next,
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultCard() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified, size: 36, color: Passeport.brass),
            const SizedBox(height: 14),
            Text(
              '$_correctCount / ${_questions.length}',
              style: Passeport.display(24, weight: FontWeight.w500),
            ),
            const SizedBox(height: 14),
            Text(
              'Great connectors score points on TEF writing and speaking tasks.',
              style: Passeport.body(13).copyWith(color: Passeport.slateDim),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 60),
              child: PasseportPrimaryButton(
                label: 'Done',
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
