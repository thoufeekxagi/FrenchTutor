import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/services/speaker_clip_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory dir;
  final pcm = List<int>.generate(2000, (i) => i % 200);

  setUp(() => dir = Directory.systemTemp.createTempSync('speaker_clips'));
  tearDown(() => dir.deleteSync(recursive: true));

  SpeakerClipService service(
    Future<http.Response> Function(http.Request) handler, {
    String? token = 'user-token',
  }) => SpeakerClipService(
    client: MockClient(handler),
    directory: () async => dir,
    baseUrl: 'https://example.test',
    anonKey: 'anon',
    accessToken: () => token,
  );

  test(
    'a shared clip is downloaded once, then played from the phone',
    () async {
      final calls = <String>[];
      final s = service((r) async {
        calls.add('${r.method} ${r.url.path}');
        return http.Response.bytes(pcm, 200);
      });
      expect(await s.clip('La banque est là.', 'Aoede'), pcm);
      expect(await s.clip('  La  banque est là. ', 'Aoede'), pcm);
      expect(calls, hasLength(1));
      expect(
        calls.single,
        startsWith('GET /storage/v1/object/public/speak-lines/tts1/Aoede/'),
      );
    },
  );

  test(
    'a missing clip is made once through the function, with the account',
    () async {
      final seen = <http.Request>[];
      final s = service((r) async {
        seen.add(r);
        if (r.method == 'GET') return http.Response('{}', 400);
        return http.Response.bytes(pcm, 200);
      });
      expect(await s.clip('Bonjour.', 'Puck'), pcm);
      final post = seen.last;
      expect(post.method, 'POST');
      expect(post.url.path, '/functions/v1/speak-line');
      expect(post.headers['Authorization'], 'Bearer user-token');
      expect(post.headers['apikey'], 'anon');
      expect(jsonDecode(post.body), {'text': 'Bonjour.', 'voice': 'Puck'});
      // Saved: no further network.
      seen.clear();
      expect(await s.clip('Bonjour.', 'Puck'), pcm);
      expect(seen, isEmpty);
    },
  );

  test('a failure is one attempt, and the next tap tries again', () async {
    var posts = 0;
    var healthy = false;
    final s = service((r) async {
      if (r.method == 'GET') return http.Response('{}', 400);
      posts++;
      return healthy ? http.Response.bytes(pcm, 200) : http.Response('no', 502);
    });
    expect(await s.clip('Merci.', 'Leda'), isNull);
    expect(posts, 1, reason: 'no hidden retry');
    healthy = true;
    expect(await s.clip('Merci.', 'Leda'), pcm);
    expect(posts, 2);
  });

  test('signed out: nothing is made, nothing crashes', () async {
    var posts = 0;
    final s = service((r) async {
      if (r.method == 'POST') posts++;
      return http.Response('{}', 400);
    }, token: null);
    expect(await s.clip('Merci.', 'Orus'), isNull);
    expect(posts, 0);
  });

  test('a clip that is too long or empty never reaches the network', () async {
    var calls = 0;
    final s = service((r) async {
      calls++;
      return http.Response.bytes(pcm, 200);
    });
    expect(await s.clip('   ', 'Aoede'), isNull);
    expect(await s.clip('a' * 201, 'Aoede'), isNull);
    expect(calls, 0);
  });

  test('a broken download (odd or tiny) is rejected and never saved', () async {
    final s = service((r) async => http.Response.bytes([1, 2, 3], 200));
    expect(await s.clip('Salut.', 'Aoede'), isNull);
    expect(await s.saved('Salut.', 'Aoede'), isNull);
  });

  test('voices do not share clips', () async {
    final s = service((r) async => http.Response.bytes(pcm, 200));
    await s.clip('Salut.', 'Aoede');
    expect(await s.saved('Salut.', 'Aoede'), isNotNull);
    expect(await s.saved('Salut.', 'Puck'), isNull);
  });

  test('two taps on one line share a single request', () async {
    var gets = 0;
    final gate = Completer<void>();
    final s = service((r) async {
      gets++;
      await gate.future;
      return http.Response.bytes(pcm, 200);
    });
    final a = s.clip('Salut.', 'Aoede');
    final b = s.clip('Salut.', 'Aoede');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    gate.complete();
    expect(await a, pcm);
    expect(await b, pcm);
    expect(gets, 1);
  });

  group('getting the next lines ready', () {
    test('each line is asked for once, at most two at a time', () async {
      final asked = <String>[];
      var running = 0;
      var peak = 0;
      final s = service((r) async {
        if (r.method == 'GET') {
          running++;
          if (running > peak) peak = running;
          asked.add(r.url.pathSegments.last);
          await Future<void>.delayed(const Duration(milliseconds: 30));
          running--;
          return http.Response.bytes(pcm, 200);
        }
        return http.Response('no', 500);
      });
      s.prefetch(['Un.', 'Deux.', 'Trois.', 'Quatre.', 'Un.'], 'Aoede');
      s.prefetch(['Deux.'], 'Aoede');
      while (s.prefetchBusy) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(asked, hasLength(4));
      expect(asked.toSet(), hasLength(4));
      expect(peak, lessThanOrEqualTo(2));
    });

    test(
      'a line that failed is not retried in the background, but a tap tries again',
      () async {
        var posts = 0;
        var healthy = false;
        final s = service((r) async {
          if (r.method == 'GET') return http.Response('{}', 400);
          posts++;
          return healthy
              ? http.Response.bytes(pcm, 200)
              : http.Response('x', 502);
        });
        s.prefetch(['Hôpital.'], 'Aoede');
        while (s.prefetchBusy) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(posts, 1);
        s.prefetch(['Hôpital.'], 'Aoede');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(posts, 1, reason: 'not asked a second time');
        healthy = true;
        expect(await s.clip('Hôpital.', 'Aoede'), pcm);
        expect(posts, 2);
      },
    );
  });

  group('wav handling', () {
    List<int> wav(List<int> samples) {
      final b = BytesBuilder()
        ..add(ascii.encode('RIFF'))
        ..add(_le32(36 + samples.length))
        ..add(ascii.encode('WAVEfmt '))
        ..add(_le32(16))
        ..add([1, 0, 1, 0])
        ..add(_le32(24000))
        ..add(_le32(48000))
        ..add([2, 0, 16, 0])
        ..add(ascii.encode('data'))
        ..add(_le32(samples.length))
        ..add(samples);
      return b.toBytes();
    }

    test('the header is removed and the samples kept', () {
      expect(SpeakerClipService.wavToPcm(wav(pcm)), pcm);
    });

    test('raw samples pass through, junk does not', () {
      expect(SpeakerClipService.wavToPcm(pcm), pcm);
      expect(SpeakerClipService.wavToPcm([1, 2, 3]), isNull);
    });
  });
}

List<int> _le32(int v) =>
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List().toList();
