// Permanently removes one explicitly selected learner and all learner-owned
// data. The tool is allowlist-first for interactive use, dry-run-first, and
// requires an exact confirmation value before any delete request is sent.
//
// Interactive (safe default; no deletion):
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
//   DELETE_ALLOWED_EMAILS='first@example.com,second@example.com' \
//   DELETE_DEFAULT_EMAIL='first@example.com' \
//     dart run tool/delete_test_user.dart
//
// Execute a selected account (still requires the exact confirmation value):
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
//   DELETE_ALLOWED_EMAILS='first@example.com,second@example.com' \
//   DELETE_USER_CONFIRM='first@example.com' \
//     dart run tool/delete_test_user.dart \
//       --email=first@example.com --execute
//
// Cloud/agent runs should always pass --email (or DELETE_USER_EMAIL). An
// exact email selector is allowed without DELETE_ALLOWED_EMAILS, but it still
// requires DELETE_USER_CONFIRM to match exactly. Interactive runs always
// require DELETE_ALLOWED_EMAILS so the tool can never enumerate production
// accounts by accident. Use --list to inspect the allowlisted accounts only.
//
// The service-role key is intentionally shell-only. Never put it in the app,
// Flutter assets, dart-defines, or this repository.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _storageBuckets = <String>[
  'story-covers',
  'vocabulary-audio',
  'listening-audio',
];
const _pageSize = 100;

// Dependent rows precede parent rows. Shared course catalogs and authored
// lesson tables are deliberately absent from this list.
const _userTables = <(String, String)>[
  ('plan_task_state', 'user_id'),
  ('learning_plan_state', 'user_id'),
  ('adaptive_course_sessions', 'user_id'),
  ('adaptive_course_plans', 'user_id'),
  ('ai_session_state', 'user_id'),
  ('daily_session_state', 'user_id'),
  ('referral_redemptions', 'redeemed_by_user_id'),
  ('referral_codes', 'owner_user_id'),
  ('subscription_invite_redemptions', 'redeemed_by_user_id'),
  ('generated_grammar_stories', 'user_id'),
  ('generated_roleplays', 'user_id'),
  ('generated_stories', 'user_id'),
  ('generated_vocabulary_sets', 'user_id'),
  ('generated_writing_tasks', 'user_id'),
  ('vocabulary_audio_cache', 'user_id'),
  ('chat_messages_state', 'user_id'),
  ('notes_state', 'user_id'),
  ('sessions_state', 'user_id'),
  ('vocab_card_state', 'user_id'),
  ('learner_competency_state', 'user_id'),
  ('learner_events', 'user_id'),
  ('credit_usage_state', 'user_id'),
  ('lesson_progress_state', 'user_id'),
  ('mistake_tag_state', 'user_id'),
];

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  final cliEmail = _normalizeEmail(_argument(args, '--email'));
  final envEmail = _normalizeEmail(Platform.environment['DELETE_USER_EMAIL']);
  if (cliEmail != null && envEmail != null && cliEmail != envEmail) {
    stderr.writeln(
      'Refusing: --email and DELETE_USER_EMAIL select different accounts.',
    );
    exitCode = 64;
    return;
  }
  final requestedEmail = cliEmail ?? envEmail;
  final allowedEmails = _parseEmailList(
    Platform.environment['DELETE_ALLOWED_EMAILS'],
  );
  if (requestedEmail == null && allowedEmails.isEmpty) {
    stderr.writeln(
      'Interactive mode requires DELETE_ALLOWED_EMAILS. '
      'For an agent, pass --email=... and DELETE_USER_CONFIRM=... instead.',
    );
    exitCode = 64;
    return;
  }
  if (requestedEmail != null &&
      allowedEmails.isNotEmpty &&
      !allowedEmails.contains(requestedEmail)) {
    stderr.writeln(
      'Refusing: $requestedEmail is not in DELETE_ALLOWED_EMAILS.',
    );
    exitCode = 64;
    return;
  }

  final defaultEmail = _normalizeEmail(
    Platform.environment['DELETE_DEFAULT_EMAIL'],
  );
  if (defaultEmail != null &&
      allowedEmails.isNotEmpty &&
      !allowedEmails.contains(defaultEmail)) {
    stderr.writeln(
      'Refusing: DELETE_DEFAULT_EMAIL must be one of DELETE_ALLOWED_EMAILS.',
    );
    exitCode = 64;
    return;
  }

  final supabaseUrl = Platform.environment['SUPABASE_URL']?.replaceFirst(
    RegExp(r'/$'),
    '',
  );
  final serviceRoleKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  if (supabaseUrl == null || supabaseUrl.isEmpty) {
    stderr.writeln('Missing SUPABASE_URL.');
    exitCode = 64;
    return;
  }
  if (serviceRoleKey == null || serviceRoleKey.isEmpty) {
    stderr.writeln('Missing SUPABASE_SERVICE_ROLE_KEY.');
    exitCode = 64;
    return;
  }

  final admin = _SupabaseAdmin(
    supabaseUrl: supabaseUrl,
    serviceRoleKey: serviceRoleKey,
  );
  try {
    if (requestedEmail == null && !stdin.hasTerminal) {
      stderr.writeln(
        'No terminal is attached. Pass --email=... for a non-interactive run.',
      );
      exitCode = 64;
      return;
    }

    final allowlistedUsers = requestedEmail == null
        ? await admin.findUsersByEmails(allowedEmails)
        : const <Map<String, dynamic>>[];
    if (args.contains('--list')) {
      if (requestedEmail != null) {
        stdout.writeln(requestedEmail);
      } else if (allowlistedUsers.isEmpty) {
        stdout.writeln('No allowlisted accounts currently exist in Auth.');
      } else {
        stdout.writeln('Allowlisted Auth accounts:');
        for (final user in allowlistedUsers) {
          stdout.writeln(' - ${user['email']}');
        }
      }
      return;
    }

    final email =
        requestedEmail ??
        _chooseEmail(allowlistedUsers, defaultEmail: defaultEmail);
    if (email == null) {
      stdout.writeln('No account selected. Nothing was deleted.');
      return;
    }
    final user = await admin.findUserByEmail(email);
    if (user == null) {
      stdout.writeln('No Auth user exists for $email. Nothing was deleted.');
      return;
    }

    final userId = user['id']?.toString();
    if (userId == null || userId.isEmpty) {
      throw StateError('Auth returned a user without an id.');
    }

    final report = await admin.inspectUser(userId);
    stdout.writeln('Selected account: $email');
    stdout.writeln('User id: $userId');
    stdout.writeln('Learner-owned database rows: ${report.databaseRows}');
    stdout.writeln(
      'Learner-owned storage objects: ${report.storageObjectCount}',
    );

    if (!args.contains('--execute')) {
      stdout.writeln(
        'Dry run only. Add --execute with the confirmation env var.',
      );
      return;
    }

    final confirmation = _normalizeEmail(
      Platform.environment['DELETE_USER_CONFIRM'] ??
          Platform.environment['DELETE_TEST_USER_CONFIRM'],
    );
    if (confirmation != email) {
      stderr.writeln(
        'Refusing: DELETE_USER_CONFIRM must exactly equal $email.',
      );
      exitCode = 64;
      return;
    }

    await admin.deleteUserData(userId, report.storagePaths);
    await admin.deleteAuthUser(userId);

    final remainingUser = await admin.findUserByEmail(email);
    final remaining = await admin.inspectUser(userId);
    if (remainingUser != null ||
        remaining.databaseRows != 0 ||
        remaining.storagePaths.isNotEmpty) {
      throw StateError(
        'Verification failed: auth=${remainingUser == null ? 0 : 1}, '
        'rows=${remaining.databaseRows}, '
        'storage=${remaining.storageObjectCount}.',
      );
    }
    stdout.writeln('Deleted and verified $email.');
  } finally {
    admin.close();
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage:\n'
    '  dart run tool/delete_test_user.dart [--list]\n'
    '  dart run tool/delete_test_user.dart --email=EMAIL [--execute]\n\n'
    'Interactive mode uses DELETE_ALLOWED_EMAILS and optional '
    'DELETE_DEFAULT_EMAIL.\n'
    'Agent mode may use DELETE_USER_EMAIL instead of --email.\n'
    'Deletion requires --execute and DELETE_USER_CONFIRM=EMAIL.\n'
    'DELETE_TEST_USER_CONFIRM is accepted as a backwards-compatible alias.',
  );
}

String? _normalizeEmail(String? value) {
  final normalized = value?.trim().toLowerCase();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

Set<String> _parseEmailList(String? value) =>
    (value ?? '').split(',').map(_normalizeEmail).whereType<String>().toSet();

String? _chooseEmail(
  List<Map<String, dynamic>> users, {
  required String? defaultEmail,
}) {
  if (users.isEmpty) return null;
  final defaultIndex = defaultEmail == null
      ? (users.length == 1 ? 0 : null)
      : users.indexWhere(
          (user) => _normalizeEmail(user['email']?.toString()) == defaultEmail,
        );
  final resolvedDefault = defaultIndex != null && defaultIndex >= 0
      ? defaultIndex
      : null;

  stdout.writeln('Select the exact account to inspect/delete:');
  for (var index = 0; index < users.length; index++) {
    final marker = index == resolvedDefault ? ' (default)' : '';
    stdout.writeln('  ${index + 1}) ${users[index]['email']}$marker');
  }
  stdout.write(
    resolvedDefault == null
        ? 'Choice (1-${users.length}): '
        : 'Choice [${resolvedDefault + 1}]: ',
  );
  final rawChoice = stdin.readLineSync()?.trim();
  if (rawChoice == null || rawChoice.isEmpty) {
    return resolvedDefault == null
        ? null
        : _normalizeEmail(users[resolvedDefault]['email']?.toString());
  }
  final choice = int.tryParse(rawChoice);
  if (choice == null || choice < 1 || choice > users.length) {
    stderr.writeln('Invalid choice. Nothing was deleted.');
    return null;
  }
  return _normalizeEmail(users[choice - 1]['email']?.toString());
}

String? _argument(List<String> args, String name) {
  final prefix = '$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}

class _UserReport {
  const _UserReport({required this.databaseRows, required this.storagePaths});

  final int databaseRows;
  final Map<String, List<String>> storagePaths;

  int get storageObjectCount =>
      storagePaths.values.fold<int>(0, (total, paths) => total + paths.length);
}

class _SupabaseAdmin {
  _SupabaseAdmin({required this.supabaseUrl, required this.serviceRoleKey});

  final String supabaseUrl;
  final String serviceRoleKey;
  final http.Client _client = http.Client();

  Map<String, String> get _headers => <String, String>{
    'Authorization': 'Bearer $serviceRoleKey',
    'apikey': serviceRoleKey,
    'Content-Type': 'application/json',
  };

  void close() => _client.close();

  Future<Map<String, dynamic>?> findUserByEmail(String email) async {
    for (var page = 1; ; page++) {
      final response = await _send(
        'GET',
        Uri.parse('$supabaseUrl/auth/v1/admin/users').replace(
          queryParameters: <String, String>{
            'page': '$page',
            'per_page': '$_pageSize',
          },
        ),
      );
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final users = (decoded['users'] as List? ?? const <dynamic>[])
          .cast<Map<String, dynamic>>();
      for (final user in users) {
        if (user['email']?.toString().toLowerCase() == email) return user;
      }
      if (users.length < _pageSize) return null;
    }
  }

  Future<List<Map<String, dynamic>>> findUsersByEmails(
    Iterable<String> emails,
  ) async {
    final users = <Map<String, dynamic>>[];
    for (final email in emails) {
      final user = await findUserByEmail(email);
      if (user != null) users.add(user);
    }
    return users;
  }

  Future<_UserReport> inspectUser(String userId) async {
    var databaseRows = await _countRows('profiles', 'id', userId);
    for (final (table, column) in _userTables) {
      databaseRows += await _countRows(table, column, userId);
    }

    final storagePaths = <String, List<String>>{};
    for (final bucket in _storageBuckets) {
      final paths = await _listFiles(bucket, userId);
      if (paths.isNotEmpty) storagePaths[bucket] = paths;
    }
    return _UserReport(databaseRows: databaseRows, storagePaths: storagePaths);
  }

  Future<void> deleteUserData(
    String userId,
    Map<String, List<String>> storagePaths,
  ) async {
    for (final entry in storagePaths.entries) {
      for (var index = 0; index < entry.value.length; index += _pageSize) {
        final end = (index + _pageSize).clamp(0, entry.value.length);
        await _send(
          'DELETE',
          Uri.parse('$supabaseUrl/storage/v1/object/${entry.key}'),
          body: <String, dynamic>{'prefixes': entry.value.sublist(index, end)},
        );
      }
    }

    // Codes owned by this account may be referenced by another learner's
    // redemption row. Remove those references before deleting the code.
    final codeResponse = await _send(
      'GET',
      _restUri('referral_codes', <String, String>{
        'select': 'code',
        'owner_user_id': 'eq.$userId',
      }),
    );
    final codes = (jsonDecode(codeResponse.body) as List)
        .cast<Map<String, dynamic>>()
        .map((row) => row['code']?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList();
    if (codes.isNotEmpty) {
      await _send(
        'DELETE',
        _restUri('referral_redemptions', <String, String>{
          'code': 'in.(${codes.join(',')})',
        }),
      );
    }

    for (final (table, column) in _userTables) {
      await _deleteRows(table, column, userId);
    }
    await _deleteRows('profiles', 'id', userId);
  }

  Future<void> deleteAuthUser(String userId) => _send(
    'DELETE',
    Uri.parse('$supabaseUrl/auth/v1/admin/users/$userId'),
    body: const <String, dynamic>{'should_soft_delete': false},
  );

  Future<int> _countRows(String table, String column, String userId) async {
    final response = await _send(
      'GET',
      _restUri(table, <String, String>{
        'select': column,
        column: 'eq.$userId',
        'limit': '1',
      }),
      extraHeaders: const <String, String>{
        'Prefer': 'count=exact',
        'Range': '0-0',
      },
    );
    final contentRange = response.headers['content-range'];
    if (contentRange == null || !contentRange.contains('/')) {
      throw StateError('Missing row count for $table.');
    }
    final count = int.tryParse(contentRange.split('/').last);
    if (count == null) throw StateError('Invalid row count for $table.');
    return count;
  }

  Future<List<String>> _listFiles(String bucket, String prefix) async {
    final paths = <String>[];
    var offset = 0;
    while (true) {
      final response = await _send(
        'POST',
        Uri.parse('$supabaseUrl/storage/v1/object/list/$bucket'),
        body: <String, dynamic>{
          'prefix': prefix,
          'limit': _pageSize,
          'offset': offset,
          'sortBy': const <String, String>{'column': 'name', 'order': 'asc'},
        },
      );
      final entries = (jsonDecode(response.body) as List)
          .cast<Map<String, dynamic>>();
      for (final entry in entries) {
        final path = '$prefix/${entry['name']}';
        if (entry['id'] == null) {
          paths.addAll(await _listFiles(bucket, path));
        } else {
          paths.add(path);
        }
      }
      if (entries.length < _pageSize) break;
      offset += entries.length;
    }
    return paths;
  }

  Future<void> _deleteRows(String table, String column, String userId) =>
      _send('DELETE', _restUri(table, <String, String>{column: 'eq.$userId'}));

  Uri _restUri(String table, Map<String, String> queryParameters) => Uri.parse(
    '$supabaseUrl/rest/v1/$table',
  ).replace(queryParameters: queryParameters);

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Object? body,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    final request = http.Request(method, uri)
      ..headers.addAll(<String, String>{..._headers, ...extraHeaders});
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        '$method ${uri.path} failed with ${response.statusCode}: '
        '${response.body}',
        uri: uri,
      );
    }
    return response;
  }
}
