import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';

class WritingTaskScreen extends ConsumerStatefulWidget {
  const WritingTaskScreen({super.key, required this.task});

  final WritingTask task;

  @override
  ConsumerState<WritingTaskScreen> createState() => _WritingTaskScreenState();
}

class _WritingTaskScreenState extends ConsumerState<WritingTaskScreen> {
  bool _showEnglish = false;
  String _content = '';
  final _textController = TextEditingController();

  WritingTask get task => widget.task;

  int get _wordCount {
    if (_content.trim().isEmpty) return 0;
    return _content.trim().split(RegExp(r'\s+')).length;
  }

  List<Connector> get _targetConnectorObjects {
    final pack = ref.read(contentServiceProvider).connectors();
    if (pack == null) return [];
    return pack.connectors.where((c) => task.targetConnectors.contains(c.id)).toList();
  }

  bool _connectorUsed(Connector connector) {
    final stem = connector.fr.toLowerCase().split('...').first;
    return _content.toLowerCase().contains(stem);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Passeport.parchmentDim,
      appBar: AppBar(
        title: Text(task.title, style: Passeport.display(18)),
        backgroundColor: Passeport.parchmentDim,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        children: [
          _promptCard(),
          const SizedBox(height: 16),
          _connectorsCard(),
          const SizedBox(height: 16),
          _editorCard(),
          const SizedBox(height: 16),
          PasseportPrimaryButton(
            label: 'Submit for grading',
            onPressed: null, // Disabled — Phase 4
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Grading requires API — Phase 4',
              style: Passeport.mono(10.5).copyWith(color: Passeport.slateDim),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // -- Prompt card --

  Widget _promptCard() {
    return PasseportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KickerText('Prompt', color: Passeport.slateDim),
          const SizedBox(height: 8),
          Text(
            task.promptFr,
            style: Passeport.body(14),
          ),
          const SizedBox(height: 6),
          if (_showEnglish)
            Text(
              task.promptEn,
              style: Passeport.body(12.5).copyWith(color: Passeport.slateDim),
            )
          else
            TextButton(
              onPressed: () => setState(() => _showEnglish = true),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(
                'Show English',
                style: Passeport.mono(10.5, weight: FontWeight.w500).copyWith(color: Passeport.maroon),
              ),
            ),
          if (task.rubricHints.isNotEmpty) ...[
            const SizedBox(height: 6),
            Divider(color: Passeport.hairline, height: 1),
            const SizedBox(height: 8),
            for (final hint in task.rubricHints)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: Passeport.brass, fontSize: 13)),
                    Expanded(
                      child: Text(
                        hint,
                        style: Passeport.mono(10.5).copyWith(color: Passeport.slateDim),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  // -- Connectors card --

  Widget _connectorsCard() {
    final connectors = _targetConnectorObjects;
    if (connectors.isEmpty) return const SizedBox.shrink();

    return PasseportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KickerText('Target connectors', color: Passeport.slateDim),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: connectors.map((c) {
              final used = _connectorUsed(c);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: used ? Passeport.brass : Passeport.maroon.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  c.fr,
                  style: Passeport.mono(10.5, weight: FontWeight.w500).copyWith(
                    color: used ? Colors.white : Passeport.maroon,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // -- Editor card --

  Widget _editorCard() {
    return PasseportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const KickerText('Your response', color: Passeport.slateDim),
              const Spacer(),
              Text(
                '$_wordCount / ${task.minWords} words',
                style: Passeport.mono(10.5).copyWith(
                  color: _wordCount >= task.minWords ? Passeport.brass : Passeport.slateDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 180),
            decoration: BoxDecoration(
              color: Passeport.parchmentDim,
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: _textController,
              onChanged: (val) => setState(() => _content = val),
              maxLines: null,
              minLines: 8,
              style: Passeport.body(13.5),
              cursorColor: Passeport.maroon,
              decoration: InputDecoration(
                hintText: 'Write your response here...',
                hintStyle: Passeport.body(13.5).copyWith(color: Passeport.slate),
                contentPadding: const EdgeInsets.all(12),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
