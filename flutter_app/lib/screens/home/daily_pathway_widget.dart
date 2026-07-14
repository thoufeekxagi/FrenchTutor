import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_keys.dart';
import '../../config/theme.dart';
import '../../data/content_service.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../services/srs_service.dart';
import '../../widgets/passeport_card.dart';
import '../pathway/agent_led_grammar_screen.dart';
import '../pathway/agent_led_listening_screen.dart';
import '../pathway/agent_led_vocab_screen.dart';
import '../pathway/grammar_picker_screen.dart';
import '../pathway/pathway_writing_screen.dart';
import '../pathway/post_vocab_choice_screen.dart';
import '../pathway/vocab_picker_screen.dart';
import '../session/session_screen.dart';

enum _Stage { vocab, grammar, postVocabChoice, listening, writing, speaking }

extension on _Stage {
  String get title {
    switch (this) {
      case _Stage.vocab: return 'Vocabulary';
      case _Stage.grammar: return 'Grammar';
      case _Stage.postVocabChoice:
      case _Stage.listening: return 'Reading & Listening';
      case _Stage.writing: return 'Writing';
      case _Stage.speaking: return 'Speaking';
    }
  }

  String get detail {
    switch (this) {
      case _Stage.vocab: return 'Flashcards with spaced repetition';
      case _Stage.grammar: return "Pick a tense, or let Marie choose";
      case _Stage.postVocabChoice:
      case _Stage.listening: return 'Word-by-word passage walkthrough';
      case _Stage.writing: return 'Short emails, paragraphs, essays';
      case _Stage.speaking: return 'Closing roleplay with Marie';
    }
  }
}

// The choice screen is an internal hop on the way to Listening, not its own row in the stage
// list — it's shown automatically right after Reading & Listening is started.
const _visibleStages = [_Stage.vocab, _Stage.grammar, _Stage.listening, _Stage.writing, _Stage.speaking];

/// The Daily Pathway hub — lives directly inside the Dashboard's "Today's plan" card. Today's
/// material is assembled once here, then handed through five focused stages in sequence — each
/// its own small, reliable agent-led (or plain typed) screen. Each stage is fed a summary of
/// what came before, so the whole thing behaves as one continuous feedback loop even though
/// it's technically five separate steps: Vocabulary -> Grammar -> Reading & Listening -> Writing
/// -> Speaking (the closing roleplay, pulling together everything from the other four stages).
/// Ported from DailyPathwayView.swift.
class DailyPathwayWidget extends ConsumerStatefulWidget {
  const DailyPathwayWidget({super.key, this.onProgress});

  final VoidCallback? onProgress;

  @override
  ConsumerState<DailyPathwayWidget> createState() => _DailyPathwayWidgetState();
}

class _DailyPathwayWidgetState extends ConsumerState<DailyPathwayWidget> {
  final Set<_Stage> _completed = {};
  VocabStageResult? _vocabResult;
  GrammarStageResult? _grammarResult;
  ListeningStageResult? _listeningResult;
  WritingStageResult? _writingResult;
  // Set once, right after the post-vocab choice screen, then handed to AgentLedListeningScreen
  // unchanged — the passage is fixed content from that point on, never regenerated.
  ReadingPassage? _chosenReadingPassage;

  List<VocabEntry>? _vocabQueue;
  ListeningExercise? _listeningExercise;
  bool _loaded = false;

  _Stage? get _nextStage {
    for (final stage in _visibleStages) {
      if (!_completed.contains(stage)) return stage;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(learningStoreProvider);
    final vocabQueue = await SRSService(store: store).dailyMixedQueue();
    final listeningPack = ContentService.shared.listening();
    final sortedExercises = [...(listeningPack?.exercises ?? <ListeningExercise>[])]..sort((a, b) => a.phase.compareTo(b.phase));
    ListeningExercise? exercise;
    for (final e in sortedExercises) {
      if (store.lessonStatus('listening_${e.id}').status != 'completed') {
        exercise = e;
        break;
      }
    }
    exercise ??= sortedExercises.isNotEmpty ? sortedExercises.first : null;
    if (!mounted) return;
    setState(() {
      _vocabQueue = vocabQueue;
      _listeningExercise = exercise;
      _loaded = true;
    });
  }

  void _openStage(_Stage stage) {
    final store = ref.read(learningStoreProvider);
    switch (stage) {
      case _Stage.vocab:
        Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) {
          return VocabPickerScreen(onComplete: (result) {
            setState(() {
              _vocabResult = result;
              _completed.add(_Stage.vocab);
            });
            if (result.reviewedCount > 0) {
              store.markHabit('anki', minutes: 5);
            }
            widget.onProgress?.call();
          });
        }));
      case _Stage.grammar:
        Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) {
          return GrammarPickerScreen(
            vocabSummary: _vocabResult,
            onComplete: (result) {
              setState(() {
                _grammarResult = result;
                _completed.add(_Stage.grammar);
              });
              store.markHabit('reading', minutes: 8);
              widget.onProgress?.call();
              // Route through the choice screen next, not straight to Listening.
              _openStage(_Stage.postVocabChoice);
            },
          );
        }));
      case _Stage.postVocabChoice:
        Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) {
          return PostVocabChoiceScreen(
            vocabResult: _vocabResult,
            fallbackExercise: _listeningExercise,
            onChoice: (passage) {
              _chosenReadingPassage = passage;
              Navigator.of(context).pop();
              _openStage(_Stage.listening);
            },
          );
        }));
      case _Stage.listening:
        final passage = _chosenReadingPassage;
        if (passage != null) {
          Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) {
            return AgentLedListeningScreen(
              passage: passage,
              vocabSummary: _vocabResult,
              onComplete: (result) {
                setState(() {
                  _listeningResult = result;
                  _completed.add(_Stage.listening);
                });
                if (result.listeningAttempted > 0) {
                  store.markHabit('listening', minutes: 8);
                }
                widget.onProgress?.call();
              },
            );
          }));
        } else {
          // Nothing to read today (no vocab covered and no lab exercise available) — skip
          // straight through rather than show an empty session.
          setState(() {
            _listeningResult = ListeningStageResult(grammarDrillResults: [], listeningCorrect: 0, listeningAttempted: 0);
            _completed.add(_Stage.listening);
          });
          widget.onProgress?.call();
        }
      case _Stage.writing:
        Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) {
          return PathwayWritingScreen(
            targetWords: _writingTargets(),
            onComplete: (result) {
              setState(() {
                _writingResult = result;
                _completed.add(_Stage.writing);
              });
              store.markHabit('writing', minutes: 5);
              widget.onProgress?.call();
            },
          );
        }));
      case _Stage.speaking:
        Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) {
          return SessionScreen(apiKey: ApiKeys.geminiKey, lessonContext: _speakingContext(), stage: 'speaking');
        })).then((_) {
          setState(() => _completed.add(_Stage.speaking));
          widget.onProgress?.call();
        });
    }
  }

  List<VocabEntry> _writingTargets() {
    final covered = _vocabResult?.wordsCovered ?? [];
    if (covered.isEmpty) {
      final queue = _vocabQueue ?? [];
      return queue.take(2).toList();
    }
    final shuffled = [...covered]..shuffle();
    return shuffled.take(2).toList();
  }

  /// Rich context for the closing Speaking stage, built from what actually happened across all
  /// four earlier stages — the roleplay uses real material from today, not a generic prompt.
  String _speakingContext() {
    final parts = <String>[
      'DAILY PATHWAY — CLOSING ROLEPLAY: have a short natural conversation using today\'s material in a real-world scenario relevant to TEF/TCF Canada prep.',
    ];
    final vocabResult = _vocabResult;
    if (vocabResult != null && vocabResult.wordsCovered.isNotEmpty) {
      parts.add('Vocabulary covered today: ${vocabResult.wordsCovered.map((e) => e.fr).join(", ")}');
    }
    final grammarResult = _grammarResult;
    if (grammarResult != null) {
      parts.add('Grammar focus today: ${grammarResult.topicTitle}.');
    }
    final listeningResult = _listeningResult;
    if (listeningResult != null && listeningResult.listeningAttempted > 0) {
      parts.add('Reading & listening: went through ${listeningResult.listeningAttempted} part(s) of today\'s passage.');
    }
    final writingResult = _writingResult;
    if (writingResult != null && writingResult.score != null) {
      parts.add('Writing score today: ${writingResult.score!.toStringAsFixed(1)}/10.');
    }
    return parts.join('\n\n');
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const PasseportCard(
        child: Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 24), child: CircularProgressIndicator(color: Passeport.maroon))),
      );
    }
    return PasseportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text("Today's plan", style: Passeport.display(16, weight: FontWeight.w500)),
              const Spacer(),
              Text('auto-tracked', style: Passeport.mono(9, weight: FontWeight.w500).copyWith(color: Passeport.slateDim)),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < _visibleStages.length; i++) ...[
            _stageRow(_visibleStages[i]),
            if (i < _visibleStages.length - 1) Divider(height: 1, color: Passeport.hairline),
          ],
          if (_completed.length == _visibleStages.length) _doneCard(),
        ],
      ),
    );
  }

  Widget _stageRow(_Stage stage) {
    final isDone = _completed.contains(stage);
    final isNext = stage == _nextStage;
    return InkWell(
      onTap: () => _openStage(stage),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(isDone ? Icons.check_circle : Icons.circle_outlined, size: 19, color: isDone ? Passeport.brass : Passeport.slate),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stage.title,
                    style: Passeport.body(13, weight: FontWeight.w500).copyWith(
                      color: Passeport.text,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                      decorationColor: Passeport.slateDim,
                    ),
                  ),
                  Text(stage.detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: Passeport.body(11).copyWith(color: Passeport.slateDim)),
                ],
              ),
            ),
            if (isNext)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Passeport.maroon, borderRadius: BorderRadius.circular(100)),
                child: Text('Start', style: Passeport.mono(10.5, weight: FontWeight.w500).copyWith(color: Passeport.parchment)),
              )
            else if (!isDone)
              const Icon(Icons.chevron_right, size: 15, color: Passeport.slate),
          ],
        ),
      ),
    );
  }

  Widget _doneCard() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.celebration, size: 16, color: Passeport.brass),
          const SizedBox(width: 8),
          Text("Today's pathway complete!", style: Passeport.body(13, weight: FontWeight.w500)),
        ],
      ),
    );
  }
}
