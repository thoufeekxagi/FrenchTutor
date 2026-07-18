import 'dart:async';
import 'dart:convert';
import 'dart:collection';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../data/database/learning_store.dart';
import '../models/agent_tool.dart';
import '../models/tutor_persona.dart';
import '../prompts/live_prompts.dart';
import '../services/progress_service.dart';

/// Ported from GeminiLiveService.swift — bidirectional audio+text streaming over the
/// Gemini Live WebSocket, with tool-call support for the agent-led Daily Pathway stages.
///
/// Connection lifecycle (PILOT_EXECUTION_PLAN.md P0.4) is owned HERE so every live
/// screen inherits it: connect timeout, automatic reconnection with backoff and Gemini
/// session-resumption handles, and proactive reconnect on server goAway. Screens only
/// hear `onDisconnected` when the connection is genuinely gone for good.
class GeminiLiveService {
  GeminiLiveService({
    required this.apiKey,
    this.sessionType = LiveSessionType.freeTalk,
    this.lessonContext,
    this.tools = const [],
    this.learningStoreForProfile,
    this.autoReconnect = true,
  });

  final String apiKey;
  final LiveSessionType sessionType;
  final String? lessonContext;
  final List<AgentTool> tools;
  final LearningStore? learningStoreForProfile;

  /// Reconnect automatically on unintentional socket loss. On by default; tests and
  /// one-shot probes can turn it off.
  final bool autoReconnect;

  static const _model = 'models/gemini-3.1-flash-live-preview';

  /// Persona is captured ONCE at construction (P2.1): a call keeps the tutor it
  /// was dialed with, even across reconnects — the voice and identity never
  /// change mid-conversation.
  final TutorPersona _persona = ActiveTutor.current;
  TutorPersona get persona => _persona;

  void Function()? onConnected;
  void Function()? onDisconnected;
  void Function(String message)? onError;

  /// Reconnection is in progress (attempt 1-based). UI can show "Reconnecting…";
  /// `onDisconnected` will NOT fire unless every attempt fails.
  void Function(int attempt)? onReconnecting;

  /// A reconnection attempt succeeded — the call continues.
  void Function()? onReconnected;
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

  // Reconnection state (P0.4). The resumption handle lets Gemini continue the SAME
  // conversation (context intact) across a new socket; when the server never granted
  // one, the fresh session gets a silent context note instead so Marie doesn't
  // re-greet mid-call.
  static const _maxReconnectAttempts = 3;
  static const _connectTimeout = Duration(seconds: 10);
  int _reconnectAttempt = 0;
  bool _isReconnecting = false;
  bool _hasConnectedOnce = false;
  bool _resumedWithHandle = false;
  String? _resumptionHandle;
  Timer? _reconnectTimer;
  Timer? _connectTimeoutTimer;

  bool get isConnected => _isSetupComplete;

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

  Future<void> connect() async {
    _isIntentionalDisconnect = false;
    final uri = Uri.parse(
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=$apiKey',
    );
    try {
      _channel = WebSocketChannel.connect(uri);
    } catch (_) {
      _handleConnectionLoss('Invalid API key or URL');
      return;
    }
    // A socket that never reaches setupComplete (bad network, server hiccup) used to
    // hang on "Connecting…" forever — now it's a normal connection loss after 10s.
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = Timer(_connectTimeout, () {
      if (!_isSetupComplete && !_isIntentionalDisconnect) {
        _teardownSocket();
        _handleConnectionLoss('Connection timed out');
      }
    });
    _sub = _channel!.stream.listen(
      (message) {
        if (message is String) {
          _handleMessage(message);
        } else if (message is List<int>) {
          _handleMessage(utf8.decode(message));
        }
      },
      onError: (error) {
        if (_isIntentionalDisconnect) return;
        _handleConnectionLoss('Connection closed: $error');
      },
      onDone: () {
        if (_isIntentionalDisconnect) return;
        _handleConnectionLoss('Connection closed');
      },
    );
    await _sendSetup();
  }

  void disconnect() {
    _isIntentionalDisconnect = true;
    _inputFlushTimer?.cancel();
    _suppressWatchdog?.cancel();
    _reconnectTimer?.cancel();
    _connectTimeoutTimer?.cancel();
    _teardownSocket();
    onDisconnected?.call();
  }

  void _teardownSocket() {
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    _isSetupComplete = false;
  }

  /// Every unintentional path to a dead socket funnels here: stream error, stream done,
  /// connect failure, connect timeout, server goAway. Decides between another attempt
  /// and giving up for real.
  void _handleConnectionLoss(String reason) {
    _connectTimeoutTimer?.cancel();
    _isSetupComplete = false;
    if (!autoReconnect || _reconnectAttempt >= _maxReconnectAttempts) {
      _isReconnecting = false;
      _teardownSocket();
      onError?.call(reason);
      onDisconnected?.call();
      return;
    }
    _reconnectAttempt += 1;
    _isReconnecting = true;
    onReconnecting?.call(_reconnectAttempt);
    _teardownSocket();
    // 1s / 2s / 4s backoff — long enough for a network blip, short enough that the
    // student is still holding the phone to their ear.
    final delay = Duration(seconds: 1 << (_reconnectAttempt - 1));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_isIntentionalDisconnect) return;
      connect();
    });
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
    var prompt = LivePrompts.forSession(
      sessionType,
      persona: _persona,
      languageMix: await TutorTuning.languageMix(),
      voiceSpeed: await TutorTuning.voiceSpeed(),
    );
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
        : '(Note de contexte silencieuse pour toi — ne réponds pas directement à '
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
          'prebuiltVoiceConfig': {'voiceName': _persona.voiceName},
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
      // Always request resumption handles; on reconnect, present the last handle so
      // the SAME conversation continues (Marie keeps her context) on the new socket.
      'sessionResumption': _resumptionHandle == null
          ? <String, dynamic>{}
          : {'handle': _resumptionHandle},
    };
    _resumedWithHandle = _isReconnecting && _resumptionHandle != null;
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
      _connectTimeoutTimer?.cancel();
      _reconnectAttempt = 0;
      if (!_hasConnectedOnce) {
        // First successful setup — even if it took retries to get here, the screen
        // hasn't seen onConnected yet (mic, session record, kickoff all hang off it).
        _hasConnectedOnce = true;
        _isReconnecting = false;
        onConnected?.call();
      } else if (_isReconnecting) {
        _isReconnecting = false;
        // Without a resumption handle this is a FRESH conversation — tell Marie
        // silently so she picks up mid-call instead of re-greeting from zero.
        if (!_resumedWithHandle) {
          injectContext(
            'The phone connection dropped briefly and has just been restored '
            'mid-session. Continue naturally from wherever the conversation was — '
            'do NOT greet the student again or restart.',
          );
        }
        onReconnected?.call();
      }
      // A duplicate setupComplete (already connected, not reconnecting) is ignored.
      return;
    }

    // Server is about to close this connection (maintenance, session time limit) —
    // reconnect proactively instead of waiting for the drop mid-sentence.
    if (json.containsKey('goAway')) {
      if (!_isIntentionalDisconnect && autoReconnect) {
        _teardownSocket();
        _handleConnectionLoss('Server ending connection');
      }
      return;
    }

    final resumptionUpdate = json['sessionResumptionUpdate'];
    if (resumptionUpdate is Map) {
      if (resumptionUpdate['resumable'] == true &&
          resumptionUpdate['newHandle'] is String) {
        _resumptionHandle = resumptionUpdate['newHandle'] as String;
      }
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
