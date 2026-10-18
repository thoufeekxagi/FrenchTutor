import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'v3_prefs.dart';

/// How a value is merged when the phone and the account disagree.
enum V3StateKind { set, positions, scalar }

class V3StateSpec {
  const V3StateSpec(this.key, this.kind);
  final String key;
  final V3StateKind kind;
}

/// V3 data that used to live only in SharedPreferences. Everything here is
/// copied to the learner's account and merged back on sign-in, so a reinstall
/// or a second phone restores it. Lesson progress, the profile and daily
/// challenges have their own sync and are not listed.
abstract final class V3CloudState {
  static const specs = [
    V3StateSpec('v3_story_done', V3StateKind.set),
    V3StateSpec('v3_story_saved_words', V3StateKind.set),
    V3StateSpec('v3_story_position', V3StateKind.positions),
    V3StateSpec('v3_story_hear_words', V3StateKind.scalar),
    V3StateSpec('learner_name', V3StateKind.scalar),
  ];

  static const _table = 'v3_user_state';

  static bool get _off => kDebugMode && const bool.fromEnvironment('E2E_SHELL');

  static String _atKey(String key) => '${v3Key(key)}.__at';

  static V3StateSpec _spec(String key) => specs.firstWhere((s) => s.key == key);

  /// Reads the current local value as JSON-ready data.
  static Object? _readLocal(SharedPreferences prefs, V3StateSpec spec) {
    final k = v3Key(spec.key);
    switch (spec.kind) {
      case V3StateKind.set:
      case V3StateKind.positions:
        return prefs.getStringList(k);
      case V3StateKind.scalar:
        return prefs.get(k);
    }
  }

  static Future<void> _writeLocal(
    SharedPreferences prefs,
    V3StateSpec spec,
    Object? value,
  ) async {
    final k = v3Key(spec.key);
    if (value == null) return;
    if (value is List) {
      await prefs.setStringList(k, [for (final e in value) e.toString()]);
    } else if (value is bool) {
      await prefs.setBool(k, value);
    } else if (value is int) {
      await prefs.setInt(k, value);
    } else {
      await prefs.setString(k, value.toString());
    }
  }

  /// Pure merge of one value. [localAt] and [remoteAt] decide scalars only.
  /// Sets are unioned, reading positions keep the furthest sentence, so a
  /// reinstall or a second phone can only add progress, never remove it.
  static Object? merge(
    V3StateKind kind,
    Object? local,
    Object? remote, {
    DateTime? localAt,
    DateTime? remoteAt,
  }) {
    switch (kind) {
      case V3StateKind.set:
        final a = <String>{
          ...?(local as List?)?.map((e) => e.toString()),
          ...?(remote as List?)?.map((e) => e.toString()),
        };
        return (a.toList()..sort());
      case V3StateKind.positions:
        final best = <String, int>{};
        for (final list in [local, remote]) {
          for (final entry in (list as List?) ?? const []) {
            final text = entry.toString();
            final i = text.lastIndexOf(':');
            if (i < 0) continue;
            final n = int.tryParse(text.substring(i + 1));
            if (n == null) continue;
            final id = text.substring(0, i);
            if (n > (best[id] ?? -1)) best[id] = n;
          }
        }
        return [for (final e in best.entries) '${e.key}:${e.value}'];
      case V3StateKind.scalar:
        if (remote == null) return local;
        if (local == null) return remote;
        final lt = localAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rt = remoteAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return rt.isAfter(lt) ? remote : local;
    }
  }

  /// Copies one key to the account. Call after every local write; it never
  /// throws and never blocks the screen.
  static void push(String key) {
    if (_off) return;
    unawaited(_push(key));
  }

  static Future<void> _push(String key) async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;
      final prefs = await SharedPreferences.getInstance();
      final spec = _spec(key);
      final now = DateTime.now().toUtc();
      await prefs.setString(_atKey(key), now.toIso8601String());
      final value = _readLocal(prefs, spec);
      if (value == null) return;
      await client.from(_table).upsert({
        'user_id': uid,
        'state_key': key,
        'value': {'v': value},
        'updated_at': now.toIso8601String(),
      }, onConflict: 'user_id,state_key');
    } catch (error) {
      debugPrint('V3CloudState.push($key) failed: $error');
    }
  }

  /// Merges the account's copy into the phone, then writes the merged result
  /// back. Safe to call on every sign-in and every Learn open.
  static Future<void> sync() async {
    if (_off) return;
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;
      final rows = await client
          .from(_table)
          .select('state_key, value, updated_at')
          .eq('user_id', uid);
      final remote = {
        for (final r in rows as List)
          (r as Map)['state_key'] as String: r.cast<String, dynamic>(),
      };
      final prefs = await SharedPreferences.getInstance();
      for (final spec in specs) {
        final row = remote[spec.key];
        final remoteValue = row == null ? null : ((row['value'] as Map?)?['v']);
        final local = _readLocal(prefs, spec);
        final merged = merge(
          spec.kind,
          local,
          remoteValue,
          localAt: DateTime.tryParse(prefs.getString(_atKey(spec.key)) ?? ''),
          remoteAt: row == null
              ? null
              : DateTime.tryParse('${row['updated_at']}'),
        );
        if (merged == null) continue;
        if (jsonEncode(merged) != jsonEncode(local)) {
          await _writeLocal(prefs, spec, merged);
        }
        if (jsonEncode(merged) != jsonEncode(remoteValue)) push(spec.key);
      }
    } catch (error) {
      debugPrint('V3CloudState.sync failed: $error');
    }
  }
}
