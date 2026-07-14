import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'data/content_service.dart';
import 'providers/database_provider.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Portrait-only on phones for the pilot — no landscape call/lesson
    // layouts have been designed or tested (PILOT_PLAN.md Phase 4).
    if (!kIsWeb) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    try {
      final db = await openAppDatabase();
      await ContentService.shared.preload();

      runApp(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
          ],
          child: const FrenchTutorApp(),
        ),
      );
    } catch (error, stackTrace) {
      runApp(_StartupErrorApp(error: error, stackTrace: stackTrace));
    }
  }, (error, stackTrace) {
    // Catches anything thrown asynchronously outside the try/catch above (e.g. a
    // dangling Future from a plugin's platform channel) so the app can never go
    // silently blank — always show something rather than nothing.
    debugPrint('Uncaught zone error: $error\n$stackTrace');
  });
}

/// Shown instead of a permanently blank screen if startup fails. Without this,
/// an exception thrown before runApp() (db open, content preload) means Flutter
/// never paints a frame — no crash log, no error UI, just a black/blank screen
/// forever, especially once no debugger is attached (e.g. after Xcode's WiFi
/// debug session drops).
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error, required this.stackTrace});

  final Object error;
  final StackTrace stackTrace;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFFAF9F6),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Startup failed', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                const Text('The app could not start. Details below:'),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      '$error\n\n$stackTrace',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
