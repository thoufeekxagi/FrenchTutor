import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../models/tutor_persona.dart';
import '../../providers/database_provider.dart';
import '../../services/gemini_live_audio_service.dart';
import '../../services/review_material_service.dart';
import '../../widgets/tts_play_button.dart';
import 'speak_ui.dart';

enum SpeakReviewMode { speaking, listening, stories, roleplay }

class SpeakReviewDetailScreen extends ConsumerStatefulWidget {
  const SpeakReviewDetailScreen({
    super.key,
    this.mode = SpeakReviewMode.speaking,
    this.phrases,
  });

  final SpeakReviewMode mode;
  final List<ReviewPhrase>? phrases;

  @override
  ConsumerState<SpeakReviewDetailScreen> createState() =>
      _SpeakReviewDetailScreenState();
}

class _SpeakReviewDetailScreenState
    extends ConsumerState<SpeakReviewDetailScreen> {
  late final List<ReviewPhrase> _phrases;
  var _index = 0;
  var _showContext = false;

  @override
  void initState() {
    super.initState();
    _phrases =
        widget.phrases ??
        ReviewMaterialService.recent(ref.read(storageServiceProvider));
    if (_phrases.isNotEmpty) unawaited(_warmReviewAudio());
  }

  Future<void> _warmReviewAudio() {
    return GeminiLiveAudioService.shared.warmDeck(
      voiceName: ActiveTutor.current.voiceName,
      items: [
        for (var index = 0; index < _phrases.length; index++)
          (text: _phrases[index].text, contentItemId: 'speak-review:$index'),
      ],
    );
  }

  void _next() {
    if (_index == _phrases.length - 1) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _index++;
      _showContext = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_phrases.isEmpty) return _emptyState();
    final phrase = _phrases[_index];
    return SpeakScaffold(
      child: Column(
        children: [
          SpeakHeader(
            leading: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(false),
              child: const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: SpeakColors.inkSoft,
                  size: 25,
                ),
              ),
            ),
            title: _modeTitle,
            subtitle: 'Recent practice · ${_index + 1} of ${_phrases.length}',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 12, 40, 0),
            child: SpeakProgressBar(value: (_index + 1) / _phrases.length),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: SpeakCard(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            'PHRASE ${_index + 1} OF ${_phrases.length}',
                            style: DesignTokens.label(10).copyWith(
                              color: SpeakColors.inkSoft,
                              letterSpacing: 1,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            phrase.role == 'assistant' ? 'TUTOR' : 'YOU',
                            style: DesignTokens.label(10).copyWith(
                              color: SpeakColors.inkSoft,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 38),
                      Text(
                        phrase.text,
                        textAlign: TextAlign.center,
                        style: DesignTokens.display(
                          30,
                        ).copyWith(color: SpeakColors.navy),
                      ),
                      const SizedBox(height: 14),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _showContext
                            ? Text(
                                'From ${phrase.source}',
                                key: ValueKey(phrase.source),
                                textAlign: TextAlign.center,
                                style: DesignTokens.body(
                                  17,
                                ).copyWith(color: SpeakColors.inkSoft),
                              )
                            : GestureDetector(
                                key: const ValueKey('context'),
                                onTap: () =>
                                    setState(() => _showContext = true),
                                child: Text(
                                  'Tap to see where you practised it',
                                  style: DesignTokens.body(
                                    14,
                                    weight: FontWeight.w600,
                                  ).copyWith(color: SpeakColors.blue),
                                ),
                              ),
                      ),
                      const SizedBox(height: 34),
                      _listenAction(phrase.text),
                      const SizedBox(height: 28),
                      const Divider(color: SpeakColors.line),
                      const SizedBox(height: 14),
                      Text(
                        'Say the phrase naturally before continuing.',
                        textAlign: TextAlign.center,
                        style: DesignTokens.body(
                          12,
                        ).copyWith(color: SpeakColors.inkSoft),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            child: SpeakPrimaryButton(
              label: _index == _phrases.length - 1
                  ? 'Finish review'
                  : 'Tap to continue',
              icon: _index == _phrases.length - 1
                  ? Icons.check_rounded
                  : Icons.arrow_forward_rounded,
              onTap: _next,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return SpeakScaffold(
      child: Column(
        children: [
          SpeakHeader(
            leading: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(false),
              child: const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: SpeakColors.inkSoft,
                  size: 25,
                ),
              ),
            ),
            title: _modeTitle,
          ),
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: SpeakCard(
                  color: SpeakColors.blueSoft,
                  child: Text(
                    'There is no recent transcript to review yet. Finish a practice session first.',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _listenAction(String phrase) {
    return Column(
      children: [
        TtsPlayButton(
          text: phrase,
          size: 28,
          iconSize: 22,
          color: SpeakColors.blue,
          contentItemId: 'speak-review:$_index',
        ),
        const SizedBox(height: 5),
        Text(
          'Listen',
          style: DesignTokens.body(
            11,
            weight: FontWeight.w600,
          ).copyWith(color: SpeakColors.inkSoft),
        ),
      ],
    );
  }

  String get _modeTitle => switch (widget.mode) {
    SpeakReviewMode.speaking => 'Speaking review',
    SpeakReviewMode.listening => 'Listening review',
    SpeakReviewMode.stories => 'Story review',
    SpeakReviewMode.roleplay => 'Roleplay review',
  };
}
