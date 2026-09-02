import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/services/gemini_live_audio_service.dart';

void main() {
  test('live audio cache keys are stable and voice/pace scoped', () {
    final first = GeminiLiveAudioService.cacheKeyFor(
      text: '  Bonjour   tout le monde ',
      voiceName: 'Orus',
    );
    final normalized = GeminiLiveAudioService.cacheKeyFor(
      text: 'Bonjour tout le monde',
      voiceName: 'Orus',
    );
    final otherVoice = GeminiLiveAudioService.cacheKeyFor(
      text: 'Bonjour tout le monde',
      voiceName: 'Aoede',
    );
    final slower = GeminiLiveAudioService.cacheKeyFor(
      text: 'Bonjour tout le monde',
      voiceName: 'Orus',
      slow: true,
    );

    expect(first, normalized);
    expect(otherVoice, isNot(normalized));
    expect(slower, isNot(normalized));
  });

  test('private storage paths are scoped to the authenticated owner', () {
    expect(
      GeminiLiveAudioService.storagePathFor(
        userId: 'user-123',
        cacheKey: 'clip-key',
      ),
      'user-123/v1/clip-key.pcm',
    );
  });

  test('one-shot Live pronunciation uses realtime text input', () {
    expect(GeminiLiveAudioService.realtimeTextMessage('bonjour'), {
      'realtimeInput': {'text': 'bonjour'},
    });
  });

  test('one-shot pronunciation is an exact script, never a tutor reply', () {
    final prompt = GeminiLiveAudioService.pronunciationSystemInstruction(
      slow: false,
    );
    expect(prompt, contains('not a conversational tutor'));
    expect(prompt, contains('word for word'));
    expect(prompt, contains('Never answer it'));
  });
}
