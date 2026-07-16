import 'dart:async';
import 'dart:convert';
import 'dart:collection';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../data/database/learning_store.dart';
import '../models/agent_tool.dart';
import '../services/progress_service.dart';

/// Ported from GeminiLiveService.swift — bidirectional audio+text streaming over the
/// Gemini Live WebSocket, with tool-call support for the agent-led Daily Pathway stages.
class GeminiLiveService {
  GeminiLiveService({
    required this.apiKey,
    this.lessonContext,
    this.tools = const [],
    this.learningStoreForProfile,
  });

  final String apiKey;
  final String? lessonContext;
  final List<AgentTool> tools;
  final LearningStore? learningStoreForProfile;

  static const _model = 'models/gemini-3.1-flash-live-preview';
  static const _voiceName = 'Puck';

  void Function()? onConnected;
  void Function()? onDisconnected;
  void Function(String message)? onError;
  void Function(String text)? onUserTranscript;
  void Function(String text)? onTutorTranscript;
  void Function(List<int> pcmBytes)? onAudioChunk;
  void Function()? onTurnComplete;
  void Function()? onInterrupted;

  /// Fires when the model calls one of the declared [tools]. `callId` must be echoed back
  /// via [sendToolResponse]. Never fires when [tools] is empty.
  void Function(String name, Map<String, dynamic> args, String callId)?
  onToolCall;

  /// Fires with each incremental chunk of spoken output transcript AS IT STREAMS — a more
  /// reliable "she is saying this right now" signal than tool-call timing.
  void Function(String delta)? onTranscriptDelta;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _isSetupComplete = false;
  String _currentUserTranscript = '';
  String _currentTutorTranscript = '';
  bool _isIntentionalDisconnect = false;

  // Orphaned-reply suppression. When the app moves a card while Marie is mid-reply, that
  // reply is answering a world that no longer exists ("okay, here's the word…" for the OLD
  // card). Cutting playback alone produced an ugly start-chop-restart stutter: the user
  // heard the orphan's first second, then silence, then the real announcement. Instead the
  // whole stale generation is discarded — audio chunks AND transcript — so the user hears
  // one clean reply: the announcement. Cleared when the server signals the old generation
  // ended (interrupted / turnComplete), with a watchdog timer as backstop.
  bool _isModelGenerating = false;
  bool _suppressStaleReply = false;
  bool _suppressPreInjection = false;
  Timer? _suppressWatchdog;

  static const systemPrompt = '''
You are Marie, a warm, encouraging French tutor speaking to a student on a phone call. The student is working toward CLB 7 on the TEF/TCF Canada exam over a 6-month study plan — they are NOT necessarily a complete beginner, so calibrate your level from the STUDENT PROFILE you're given below rather than assuming. A student early in the plan needs slow, simple French with lots of English scaffolding; a student further along should be pushed with faster French, tougher vocabulary, and less hand-holding. Re-calibrate every call using the profile, don't default to "beginner mode" out of habit.

CRITICAL RULES — FOLLOW EXACTLY:
1. Reply ONLY as if you are talking to the student. Never describe your plan, your thoughts, or what you are about to do. Never say "I will" or "My aim is" or "I realize".
2. Match your pace to the student's level (see profile): slow and simple for someone early on; natural conversational speed for someone with more vocabulary/grammar under their belt.
3. Keep every reply short: one to three sentences max. This is a voice call, not a lecture.
4. You are fully bilingual and switch fluidly based on what the student needs:
   - If the student speaks or asks in English (e.g. asking for clarification, grammar help, or says they're confused), answer clearly in English first, then give the French equivalent.
   - If the student speaks in French, respond mostly in French, softly correcting mistakes by saying the correct French naturally, without lecturing.
   - Always let the student's own language choice guide you — never force French if they are clearly asking a question in English.
5. Ask one simple follow-up question at a time so the student keeps talking. Favor realistic, exam-relevant scenarios (roleplay a phone call, an opinion question, comparing two choices) over generic small talk once the profile shows they're past the basics.
6. No markdown, no bullet points, no asterisks, no headers, no numbered lists. Just plain natural speech.
7. If a LESSON CONTEXT block is provided below, that is what the student just studied or is currently working on — steer the conversation to practice exactly that material, using real-world use cases (not a dry recap).
8. Be encouraging and patient. Use short warm fillers like "très bien", "parfait", "doucement", "pas de souci" — or push a little harder ("essayons quelque chose de plus difficile") once the student is ready.

EXAMPLE OF A GOOD REPLY (student spoke French):
"Très bien! On dit... 'je m'appelle'. Tu peux essayer de le dire?"

EXAMPLE OF A GOOD REPLY (student asked in English):
"Sure! 'My name is' in French is 'je m'appelle'. Want to try saying it?"

EXAMPLE OF A BAD REPLY (NEVER DO THIS):
"I will now focus on greetings. My aim is to teach 'bonjour' and 'salut'. First, I will explain..."

START THE CALL WITH A WARM GREETING PITCHED AT THE STUDENT'S LEVEL FROM THE PROFILE. If a LESSON CONTEXT is provided, jump straight into practicing that material instead of a generic greeting.''';

  Future<void> connect() async {
    _isIntentionalDisconnect = false;
    final uri = Uri.parse(
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=$apiKey',
    );
    try {
      _channel = WebSocketChannel.connect(uri);
    } catch (_) {
      onError?.call('Invalid API key or URL');
      return;
    }
    _sub = _channel!.stream.listen(
      (message) {
        if (message is String) {
          _handleMessage(message);
        } else if (message is List<int>) {
          _handleMessage(utf8.decode(message));
        }
      },
      onError: (error) {
        _isSetupComplete = false;
        if (!_isIntentionalDisconnect) {
          onError?.call('Connection closed: $error');
        }
        onDisconnected?.call();
      },
      onDone: () {
        _isSetupComplete = false;
        if (!_isIntentionalDisconnect) {
          onError?.call('Connection closed');
        }
        onDisconnected?.call();
      },
    );
    await _sendSetup();
  }

  void disconnect() {
    _isIntentionalDisconnect = true;
    _inputFlushTimer?.cancel();
    _suppressWatchdog?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isSetupComplete = false;
  }

  void sendAudioChunk(List<int> pcmBytes) {
    if (!_isSetupComplete) return;
    final b64 = base64Encode(pcmBytes);
    _send({
      'realtimeInput': {
        'audio': {'mimeType': 'audio/pcm;rate=16000', 'data': b64},
      },
    });
  }

  void sendText(String text) {
    if (!_isSetupComplete) return;
    _send({
      'clientContent': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {'text': text},
            ],
          },
        ],
        'turnComplete': true,
      },
    });
  }

  Future<String> _fullSystemPrompt() async {
    var prompt = systemPrompt;
    final profile = await _learnerProfile();
    if (profile.isNotEmpty) {
      prompt +=
          '\n\nSTUDENT PROFILE — use this to calibrate level and pacing; never read it aloud:\n$profile';
    }
    final ctx = lessonContext;
    if (ctx != null && ctx.isNotEmpty) {
      prompt +=
          '\n\nLESSON CONTEXT — the student is currently studying this material; steer practice toward it while following ALL rules above:\n$ctx';
    }
    return prompt;
  }

  Future<String> _learnerProfile() async {
    final store = learningStoreForProfile;
    if (store == null) return '';
    try {
      return await ProgressService(store: store).learnerProfileSummary();
    } catch (_) {
      return '';
    }
  }

  /// Call at the moment the app invalidates Marie's in-flight reply (card move, drift cut).
  /// If she's mid-generation, the rest of that generation is discarded — never played,
  /// never surfaced as transcript — so her next audible words are her response to the
  /// follow-up injection, with no stutter. If she's silent, incoming strays are dropped
  /// only until the next spoken injection goes out, so the announcement reply itself is
  /// never at risk.
  void suppressCurrentReply() {
    if (_isModelGenerating) {
      _suppressStaleReply = true;
      // Backstop: if neither interrupted nor turnComplete ever arrives for the stale
      // generation (connection hiccup), don't mute her forever.
      _suppressWatchdog?.cancel();
      _suppressWatchdog = Timer(const Duration(seconds: 4), () {
        _suppressStaleReply = false;
      });
    } else {
      _suppressPreInjection = true;
    }
  }

  void _clearStaleSuppression() {
    _isModelGenerating = false;
    _suppressStaleReply = false;
    _suppressWatchdog?.cancel();
  }

  /// Sends a context note mid-call so Marie can be redirected toward a new topic without
  /// ending the conversation. By default it's silent — she absorbs it and doesn't reply.
  /// With `expectReply: true` the note is framed as something to react to out loud NOW and
  /// the turn is closed so she actually generates a response — used for card changes, where
  /// she should announce what's newly on screen ("now the word is…") instead of going quiet
  /// or, worse, finishing a sentence about a card that's no longer there. Also used as the
  /// session kickoff so SHE opens the call instead of waiting for the student to speak first.
  void injectContext(String note, {bool expectReply = false}) {
    if (!_isSetupComplete || note.isEmpty) return;
    final framed = expectReply
        ? '(Note from the app, not the student — the on-screen card just changed or the '
              'session needs you to speak. Your audio may have been cut off mid-sentence; do '
              'NOT finish or refer back to your previous thought. React to this note now, '
              'briefly: ) $note'
        : '(Note de contexte silencieuse pour toi, Marie — ne réponds pas directement à '
              'ceci, utilise-le seulement pour orienter la suite de la conversation) : $note';
    _send({
      'clientContent': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {'text': framed},
            ],
          },
        ],
        'turnComplete': expectReply,
      },
    });
    // The reply this injection triggers is wanted — stop dropping stray chunks now.
    if (expectReply) _suppressPreInjection = false;
  }

  Future<void> _sendSetup() async {
    final generationConfig = <String, dynamic>{
      'responseModalities': ['AUDIO'],
      'speechConfig': {
        'voiceConfig': {
          'prebuiltVoiceConfig': {'voiceName': _voiceName},
        },
      },
    };
    // Structured, tool-driven sessions (vocab/listening choreography) need disciplined
    // instruction-following far more than they need creative variety — lower temperature
    // measurably improves that. Freeform "Discuss with Marie" calls (no tools) keep the
    // default so that experience stays exactly as natural/varied as it's always been.
    if (tools.isNotEmpty) {
      generationConfig['temperature'] = 0.65;
    }
    final setupBody = <String, dynamic>{
      'model': _model,
      'generationConfig': generationConfig,
      'systemInstruction': {
        'parts': [
          {'text': await _fullSystemPrompt()},
        ],
      },
      'outputAudioTranscription': <String, dynamic>{},
      'inputAudioTranscription': <String, dynamic>{},
      'realtimeInputConfig': {
        'automaticActivityDetection': {
          'disabled': false,
          'startOfSpeechSensitivity': 'START_SENSITIVITY_LOW',
          'endOfSpeechSensitivity': 'END_SENSITIVITY_LOW',
          'prefixPaddingMs': 300,
          'silenceDurationMs': 2500,
        },
      },
    };
    if (tools.isNotEmpty) {
      setupBody['tools'] = [
        {'functionDeclarations': tools.map((t) => t.declaration).toList()},
      ];
    }
    _send({'setup': setupBody});
  }

  /// Answers a tool call the model made via [onToolCall]. Must be sent for every call, even
  /// ones that are pure UI updates, so the model knows to continue. `scheduling` of "SILENT"
  /// absorbs the result without generating a reaction (use for pure bookkeeping calls like
  /// grading/advancing); leave null for calls whose result should shape what she says next.
  /// Other values: "WHEN_IDLE", "INTERRUPT".
  void sendToolResponse({
    required String callId,
    required String name,
    required Map<String, dynamic> result,
    String? scheduling,
  }) {
    final response = Map<String, dynamic>.from(result);
    if (scheduling != null) response['scheduling'] = scheduling;
    _send({
      'toolResponse': {
        'functionResponses': [
          {'id': callId, 'name': name, 'response': response},
        ],
      },
    });
  }

  final Queue<String> _pendingMessages = Queue<String>();
  static const _maxQueuedAudioMessages = 10;

  void _send(Map<String, dynamic> dict) {
    final str = jsonEncode(dict);
    _enqueueMessage(str);
  }

  void _enqueueMessage(String message) {
    _pendingMessages.add(message);
    while (_pendingMessages.length > _maxQueuedAudioMessages) {
      _pendingMessages.removeFirst();
    }
    _flushQueue();
  }

  void _flushQueue() {
    final channel = _channel;
    if (channel == null) return;
    while (_pendingMessages.isNotEmpty) {
      final message = _pendingMessages.removeFirst();
      try {
        channel.sink.add(message);
      } catch (e) {
        onError?.call('Send error: $e');
      }
    }
  }

  void _handleMessage(String text) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final errorObj = json['error'];
    if (errorObj is Map) {
      final message = errorObj['message'] as String? ?? 'Unknown error';
      onError?.call(message);
      return;
    }

    if (json.containsKey('setupComplete')) {
      _isSetupComplete = true;
      onConnected?.call();
      return;
    }

    final toolCall = json['toolCall'];
    if (toolCall is Map) {
      final calls = toolCall['functionCalls'];
      if (calls is List) {
        for (final call in calls) {
          if (call is! Map) continue;
          final name = call['name'] as String?;
          final id = call['id'] as String?;
          if (name == null || id == null) continue;
          final args =
              (call['args'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          onToolCall?.call(name, args, id);
        }
      }
      return;
    }

    final serverContent = json['serverContent'];
    if (serverContent is! Map) return;

    final interrupted = serverContent['interrupted'];
    if (interrupted == true) {
      final wasSuppressed = _suppressStaleReply;
      _clearStaleSuppression();
      // A suppressed generation officially never happened — don't surface its partial
      // transcript as a spoken tutor line.
      if (wasSuppressed) {
        _currentTutorTranscript = '';
        return;
      }
      if (_currentTutorTranscript.isNotEmpty) {
        final t = _currentTutorTranscript;
        _currentTutorTranscript = '';
        onTutorTranscript?.call(t);
      }
      onInterrupted?.call();
      return;
    }

    final inputTranscription = serverContent['inputTranscription'];
    if (inputTranscription is Map) {
      final t = inputTranscription['text'] as String?;
      if (t != null && t.isNotEmpty) {
        _currentUserTranscript += t;
        // THE core sync fix: the student's transcript used to be delivered only when the
        // MODEL's reply started streaming (or on turnComplete) — so with Marie instructed
        // to wait silently, a spoken "next" sat in this buffer indefinitely and the card
        // never moved. Input transcription streams in near-realtime while the student
        // talks, so flush on a short trailing debounce instead: the utterance reaches the
        // intent judge ~800ms after they stop speaking, with zero dependence on whether
        // or when Marie replies.
        _inputFlushTimer?.cancel();
        _inputFlushTimer = Timer(
          const Duration(milliseconds: 800),
          _flushUserTranscript,
        );
      }
    }

    final outputTranscription = serverContent['outputTranscription'];
    if (outputTranscription is Map) {
      final t = outputTranscription['text'] as String?;
      if (t != null && t.isNotEmpty) {
        _isModelGenerating = true;
        if (!_suppressStaleReply && !_suppressPreInjection) {
          onTranscriptDelta?.call(t);
          _flushUserTranscript();
          _currentTutorTranscript += t;
        }
      }
    }

    final modelTurn = serverContent['modelTurn'];
    if (modelTurn is Map) {
      _isModelGenerating = true;
      final parts = modelTurn['parts'];
      if (parts is List && !_suppressStaleReply && !_suppressPreInjection) {
        for (final part in parts) {
          if (part is! Map) continue;
          final inlineData = part['inlineData'];
          if (inlineData is Map) {
            final audioB64 = inlineData['data'] as String?;
            if (audioB64 != null) {
              try {
                onAudioChunk?.call(base64Decode(audioB64));
              } catch (_) {}
            }
          }
        }
      }
    }

    final turnComplete = serverContent['turnComplete'];
    if (turnComplete == true) {
      final wasSuppressed = _suppressStaleReply;
      _clearStaleSuppression();
      _flushUserTranscript();
      if (wasSuppressed) {
        // The stale generation ended naturally before the follow-up injection landed —
        // swallow it whole; the announcement reply will be its own fresh turn.
        _currentTutorTranscript = '';
        return;
      }
      if (_currentTutorTranscript.isNotEmpty) {
        final tutorTranscript = _currentTutorTranscript;
        _currentTutorTranscript = '';
        onTutorTranscript?.call(tutorTranscript);
      }
      onTurnComplete?.call();
    }
  }

  Timer? _inputFlushTimer;

  void _flushUserTranscript() {
    _inputFlushTimer?.cancel();
    if (_currentUserTranscript.isEmpty) return;
    final t = _currentUserTranscript;
    _currentUserTranscript = '';
    onUserTranscript?.call(t);
  }
}
