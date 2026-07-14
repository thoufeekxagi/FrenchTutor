import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../providers/database_provider.dart';
import '../../models/content_models.dart';
import '../../models/srs_state.dart';
import '../../services/lesson_speech_service.dart';

class FlashcardSessionScreen extends ConsumerStatefulWidget {
  const FlashcardSessionScreen({
    super.key,
    required this.phase,
    required this.theme,
  });

  final int phase;
  final VocabTheme theme;

  @override
  ConsumerState<FlashcardSessionScreen> createState() => _FlashcardSessionScreenState();
}

class _FlashcardSessionScreenState extends ConsumerState<FlashcardSessionScreen> {
  List<VocabEntry> _queue = [];
  int _currentIndex = 0;
  bool _isRevealed = false;
  bool _isLoading = true;
  bool _showSummary = false;
  int _reviewedCount = 0;

  // Drag state for swipe grading
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;

  // Speech state
  bool _isListeningBack = false;
  String? _sayItHint;

  static const _diacriticMap = {
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'à': 'a', 'â': 'a',
    'ç': 'c',
    'î': 'i', 'ï': 'i',
    'ô': 'o',
    'û': 'u', 'ù': 'u',
    'œ': 'oe',
  };

  String _fold(String text) {
    var result = text.toLowerCase().trim();
    _diacriticMap.forEach((accented, plain) {
      result = result.replaceAll(accented, plain);
    });
    return result;
  }

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  @override
  void dispose() {
    LessonSpeechService.shared.deactivate();
    super.dispose();
  }

  Future<void> _loadQueue() async {
    final srs = ref.read(srsServiceProvider);
    final queue = await srs.buildQueue(phase: widget.phase, themeId: widget.theme.id);
    if (!mounted) return;
    setState(() {
      _queue = queue;
      _isLoading = false;
      if (_queue.isEmpty) _showSummary = true;
    });
    _speakCurrentCard();
  }

  void _loadAllWords() {
    final srs = ref.read(srsServiceProvider);
    final all = srs.allEntries(phase: widget.phase, themeId: widget.theme.id);
    setState(() {
      _queue = all;
      _currentIndex = 0;
      _isRevealed = false;
      _showSummary = false;
      _reviewedCount = 0;
    });
    _speakCurrentCard();
  }

  void _speakCurrentCard() {
    if (_currentIndex >= _queue.length || _showSummary) return;
    final entry = _queue[_currentIndex];
    LessonSpeechService.shared.speak(
      items: [SpeechItem(text: entry.fr, language: 'fr-FR')],
    );
  }

  void _speakWord(VocabEntry entry, {double? rate}) {
    LessonSpeechService.shared.speak(
      items: [SpeechItem(text: entry.fr, language: 'fr-FR')],
      rate: rate,
    );
  }

  void _toggleSayIt(VocabEntry entry) {
    if (_isListeningBack) {
      LessonSpeechService.shared.stopListening();
      setState(() => _isListeningBack = false);
      return;
    }
    setState(() {
      _isListeningBack = true;
      _sayItHint = null;
    });
    LessonSpeechService.shared.startListening(
      locale: 'fr-FR',
      onPartial: (_) {},
      onFinal: (transcript) {
        if (!mounted) return;
        final foldedTranscript = _fold(transcript);
        final foldedTarget = _fold(entry.fr);
        String hint;
        if (foldedTranscript.isEmpty) {
          hint = "Didn't catch that — try again.";
        } else if (foldedTranscript.contains(foldedTarget) ||
            foldedTarget.contains(foldedTranscript)) {
          hint = 'Nice — that sounds right! 🎉';
        } else {
          hint = 'Close — target: "${entry.fr}". This is just a hint, not graded.';
        }
        setState(() {
          _isListeningBack = false;
          _sayItHint = hint;
        });
      },
    );
  }

  void _gradeCard(SRSGrade grade) {
    if (_currentIndex >= _queue.length) return;
    final entry = _queue[_currentIndex];
    final srs = ref.read(srsServiceProvider);
    srs.grade(entryId: entry.id, grade: grade);
    _reviewedCount++;
    _advance();
  }

  void _advance() {
    setState(() {
      _dragOffset = Offset.zero;
      _isDragging = false;
      _isRevealed = false;
      _isListeningBack = false;
      _sayItHint = null;
      if (_currentIndex + 1 >= _queue.length) {
        _showSummary = true;
      } else {
        _currentIndex++;
      }
    });
    if (!_showSummary) {
      _speakCurrentCard();
    }
  }

  SRSGrade? _gradeFromDrag(Offset offset) {
    const threshold = 60.0;
    if (offset.dx < -threshold) return SRSGrade.again;
    if (offset.dx > threshold) return SRSGrade.good;
    if (offset.dy < -threshold) return SRSGrade.easy;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Passeport.parchmentDim,
      appBar: AppBar(
        title: Text(widget.theme.title, style: Passeport.display(20)),
        backgroundColor: Passeport.parchmentDim,
        foregroundColor: Passeport.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _showSummary
              ? _buildSummary()
              : _buildSession(),
    );
  }

  Widget _buildSession() {
    final entry = _queue[_currentIndex];
    final grade = _gradeFromDrag(_dragOffset);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            const SizedBox(height: 8),
            // Counter
            Text(
              '${_currentIndex + 1} / ${_queue.length}',
              style: Passeport.mono(13).copyWith(color: Passeport.slate),
            ),
            // Progress bar
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (_currentIndex + 1) / _queue.length,
                minHeight: 4,
                backgroundColor: Passeport.hairline,
                valueColor: const AlwaysStoppedAnimation(Passeport.brass),
              ),
            ),
            const Spacer(),
            // Card with gesture handling
            GestureDetector(
              onTap: () {
                if (!_isRevealed) {
                  setState(() => _isRevealed = true);
                }
              },
              onPanStart: (_) {
                if (_isRevealed) {
                  setState(() => _isDragging = true);
                }
              },
              onPanUpdate: (details) {
                if (_isRevealed) {
                  setState(() {
                    _dragOffset += details.delta;
                  });
                }
              },
              onPanEnd: (_) {
                if (!_isRevealed) return;
                final g = _gradeFromDrag(_dragOffset);
                if (g != null) {
                  _gradeCard(g);
                } else {
                  setState(() {
                    _dragOffset = Offset.zero;
                    _isDragging = false;
                  });
                }
              },
              child: Transform.translate(
                offset: _isRevealed ? _dragOffset : Offset.zero,
                child: Transform.rotate(
                  angle: _isRevealed ? _dragOffset.dx * 0.001 : 0,
                  child: Stack(
                    children: [
                      _buildCard(entry),
                      // Swipe hint badges
                      if (_isRevealed && _isDragging) ...[
                        if (grade == SRSGrade.again)
                          Positioned(
                            top: 16,
                            right: 16,
                            child: _swipeBadge('AGAIN', Passeport.maroon),
                          ),
                        if (grade == SRSGrade.good)
                          Positioned(
                            top: 16,
                            left: 16,
                            child: _swipeBadge('GOOD', Passeport.brass),
                          ),
                        if (grade == SRSGrade.easy)
                          Positioned(
                            bottom: 16,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: _swipeBadge('EASY', const Color(0xFF3A7D44)),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildSpeakerRow(entry),
            const SizedBox(height: 12),
            if (!_isRevealed)
              Text(
                'Tap to reveal',
                style: Passeport.body(13).copyWith(color: Passeport.slate),
              )
            else ...[
              Text(
                'Swipe: left = Again, right = Good, up = Easy',
                style: Passeport.body(12).copyWith(color: Passeport.slate),
              ),
              const SizedBox(height: 12),
              _buildSayItButton(entry),
              if (_sayItHint != null) ...[
                const SizedBox(height: 8),
                Text(
                  _sayItHint!,
                  textAlign: TextAlign.center,
                  style: Passeport.mono(12).copyWith(color: Passeport.slateDim),
                ),
              ],
            ],
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(VocabEntry entry) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 220),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Passeport.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Passeport.hairline, width: 1),
        boxShadow: [
          BoxShadow(
            color: Passeport.ink.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // French word
          Text(
            entry.fr,
            style: Passeport.display(28, weight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // Phonetic
          Text(
            entry.phonetic,
            style: Passeport.body(16).copyWith(
              color: Passeport.slate,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          // Reveal divider and English
          if (_isRevealed) ...[
            const SizedBox(height: 20),
            Container(
              height: 1,
              color: Passeport.hairline,
            ),
            const SizedBox(height: 20),
            Text(
              entry.en,
              style: Passeport.body(20, weight: FontWeight.w500).copyWith(
                color: Passeport.brass,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpeakerRow(VocabEntry entry) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _circleIconButton(
          icon: Icons.slow_motion_video,
          onTap: () => _speakWord(entry, rate: 0.3),
          tooltip: 'Slow',
        ),
        const SizedBox(width: 16),
        _circleIconButton(
          icon: Icons.volume_up,
          onTap: () => _speakWord(entry, rate: 0.45),
          tooltip: 'Normal',
        ),
      ],
    );
  }

  Widget _buildSayItButton(VocabEntry entry) {
    return Center(
      child: _circleIconButton(
        icon: _isListeningBack ? Icons.mic : Icons.mic_none,
        onTap: () => _toggleSayIt(entry),
        tooltip: 'Say it',
        active: _isListeningBack,
      ),
    );
  }

  Widget _circleIconButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    bool active = false,
  }) {
    final button = Material(
      color: active ? Passeport.maroon.withValues(alpha: 0.12) : Passeport.card,
      shape: CircleBorder(
        side: BorderSide(
          color: active ? Passeport.maroon : Passeport.hairline,
          width: 1,
        ),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            icon,
            size: 22,
            color: active ? Passeport.maroon : Passeport.ink,
          ),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: button) : button;
  }

  Widget _swipeBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        label,
        style: Passeport.mono(13, weight: FontWeight.w700).copyWith(color: color),
      ),
    );
  }

  Widget _buildSummary() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            Icon(Icons.check_circle_rounded, size: 64, color: Passeport.brass),
            const SizedBox(height: 20),
            Text(
              'Session Complete',
              style: Passeport.display(24, weight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              _reviewedCount > 0
                  ? '$_reviewedCount card${_reviewedCount == 1 ? '' : 's'} reviewed'
                  : 'No cards due right now',
              style: Passeport.body(16).copyWith(color: Passeport.slateDim),
            ),
            const Spacer(),
            PasseportPrimaryButton(
              label: 'Done',
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadAllWords,
              child: Text(
                'Review all words anyway',
                style: Passeport.body(14, weight: FontWeight.w500).copyWith(
                  color: Passeport.brass,
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
