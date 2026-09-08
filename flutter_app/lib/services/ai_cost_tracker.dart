import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

/// Lightweight, provider-agnostic cost ledger for development builds.
///
/// This is deliberately local and append-only: it never sends prompts or
/// audio off-device. Each line is JSON so it can be copied out of the app
/// support directory and summed without another paid model call.
class AiCostTracker {
  AiCostTracker._();

  static Future<void> _writeQueue = Future<void>.value();
  static File? _file;

  static const geminiLiveInputAudioUsdPerMinute = 0.005;
  static const geminiLiveOutputAudioUsdPerMinute = 0.018;
  static const geminiLiveInputTextUsdPerMillion = 0.75;
  static const geminiLiveOutputTextUsdPerMillion = 4.50;
  static const geminiFlashLiteInputUsdPerMillion = 0.25;
  static const geminiFlashLiteOutputUsdPerMillion = 1.50;
  static const lunaInputUsdPerMillion = 0.20;
  static const lunaOutputUsdPerMillion = 1.20;

  static double estimateGeminiLiveAudio({
    double inputSeconds = 0,
    double outputSeconds = 0,
  }) =>
      inputSeconds / 60 * geminiLiveInputAudioUsdPerMinute +
      outputSeconds / 60 * geminiLiveOutputAudioUsdPerMinute;

  static double estimateTokenCost({
    required String provider,
    required String model,
    int inputTokens = 0,
    int outputTokens = 0,
  }) {
    final normalized = '$provider $model'.toLowerCase();
    final inputRate = normalized.contains('luna')
        ? lunaInputUsdPerMillion
        : normalized.contains('flash-lite')
        ? geminiFlashLiteInputUsdPerMillion
        : geminiLiveInputTextUsdPerMillion;
    final outputRate = normalized.contains('luna')
        ? lunaOutputUsdPerMillion
        : normalized.contains('flash-lite')
        ? geminiFlashLiteOutputUsdPerMillion
        : geminiLiveOutputTextUsdPerMillion;
    return inputTokens / 1000000 * inputRate +
        outputTokens / 1000000 * outputRate;
  }

  static Future<void> record({
    required String provider,
    required String model,
    required String feature,
    required String event,
    String? requestId,
    bool cacheHit = false,
    bool success = true,
    int inputTokens = 0,
    int outputTokens = 0,
    double inputAudioSeconds = 0,
    double outputAudioSeconds = 0,
    double? estimatedUsd,
    Map<String, Object?> extra = const {},
  }) {
    final inputCost = estimateTokenCost(
      provider: provider,
      model: model,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
    );
    final audioCost = provider == 'google'
        ? estimateGeminiLiveAudio(
            inputSeconds: inputAudioSeconds,
            outputSeconds: outputAudioSeconds,
          )
        : 0.0;
    // A local or Supabase cache hit is not a provider request. Keep its
    // payload's audio duration for diagnostics, but never count cached bytes
    // as if they had just been generated.
    final cost = estimatedUsd ?? (cacheHit ? 0.0 : inputCost + audioCost);
    final payload = <String, Object?>{
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'provider': provider,
      'model': model,
      'feature': feature,
      'event': event,
      'request_id': requestId,
      'cache_hit': cacheHit,
      'success': success,
      'input_tokens': inputTokens,
      'output_tokens': outputTokens,
      'input_audio_seconds': inputAudioSeconds,
      'output_audio_seconds': outputAudioSeconds,
      'estimated_usd': double.parse(cost.toStringAsFixed(8)),
      // A provider failure can still have consumed input/context tokens before
      // returning no playable audio. The client cannot know the final billed
      // amount, so zero is only a lower bound, not proof of a free request.
      'estimated_usd_is_lower_bound': !success && provider != 'local',
      ...extra,
    };
    debugPrint('AI_COST ${jsonEncode(payload)}');
    _writeQueue = _writeQueue.then((_) async {
      try {
        // Do not put a timer on the test/event loop for telemetry. The
        // tracker is best-effort and its write is already detached from the
        // lesson operation; a platform directory lookup can simply finish
        // later without ever holding a provider or playback operation open.
        final supportDirectory = await getApplicationSupportDirectory();
        _file ??= File('${supportDirectory.path}/ai-cost.ndjson');
        await _file!.parent.create(recursive: true);
        await _file!.writeAsString(
          '${jsonEncode(payload)}\n',
          mode: FileMode.append,
          flush: false,
        );
      } catch (_) {
        // Cost telemetry must never break lesson playback.
      }
    });
    return _writeQueue;
  }

  /// Development-only structured trace for non-provider events. It shares the
  /// same append-only NDJSON file as cost records so one timeline can answer
  /// exactly when a cache miss, retry, socket, or explicit generation action
  /// happened. It never includes prompts or audio payloads.
  static Future<void> event({
    required String feature,
    required String event,
    String? requestId,
    Map<String, Object?> extra = const {},
  }) => record(
    provider: 'local',
    model: 'debug-trace',
    feature: feature,
    event: event,
    requestId: requestId,
    extra: extra,
  );
}
