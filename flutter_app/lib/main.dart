import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'config/api_keys.dart';
import 'data/content_service.dart';
import 'data/database/pilot_infrastructure_store.dart';
import 'data/database/competency_store.dart';
import 'models/tutor_persona.dart';
import 'orchestration/runtime/orchestration_bootstrapper.dart';
import 'providers/database_provider.dart';
import 'services/lesson_speech_service.dart';
import 'services/pilot_access_service.dart';
import 'services/subscription_gate_service.dart';

void main() {
  // SentryFlutter.init owns the appRunner error zone and wires Flutter errors
  // automatically. The startup try/catch below still renders a visible error
  // screen for failures before the app can mount. An empty DSN makes the SDK a
  // silent no-op, matching the other optional keys in ApiKeys.
  SentryFlutter.init(
    (options) {
      options.dsn = ApiKeys.sentryDsn;
      // Crash/error reporting only — no performance-trace overhead needed here.
      options.tracesSampleRate = 0.0;
    },
    appRunner: () async {
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
        if (ApiKeys.supabaseUrl.isEmpty || ApiKeys.supabaseAnonKey.isEmpty) {
          throw StateError(
            'Missing SUPABASE_URL / SUPABASE_ANON_KEY. Run via '
            './run_with_keys.sh or ./run_release_with_keys.sh (see '
            'BUILD_FLUTTER_TO_IPHONE.md), a plain `flutter run` ships '
            'without these and auth cannot work.',
          );
        }
        await Supabase.initialize(
          url: ApiKeys.supabaseUrl,
          // The modern "publishable" key (sb_publishable_...), not the
          // legacy anon JWT — see ApiKeys.supabaseAnonKey's doc comment.
          publishableKey: ApiKeys.supabaseAnonKey,
        );
        // Product-usage analytics (not crash reporting — that's Sentry
        // above). Empty key means no PostHog project is wired yet, so this
        // is a silent no-op, matching every other optional key's pattern.
        if (ApiKeys.posthogApiKey.isNotEmpty) {
          final config = PostHogConfig(ApiKeys.posthogApiKey)
            ..host = ApiKeys.posthogHost
            ..captureApplicationLifecycleEvents = true
            ..debug = kDebugMode;
          await Posthog().setup(config);
        }
        final db = await openAppDatabase();
        LessonSpeechService.configure(db);
        final infrastructure = PilotInfrastructureStore(db);
        final platform = _pilotPlatform();
        final installationId = infrastructure.installationId(platform.name);
        if (ApiKeys.posthogApiKey.isNotEmpty) {
          await Posthog().identify(userId: installationId);
        }
        PilotTelemetry(
          infrastructure: infrastructure,
          installationId: installationId,
        ).appStarted(platform: platform);
        await ContentService.shared.preload();
        // The chosen tutor persona must be readable synchronously anywhere
        // (P2.1) — loaded once here, updated only from Settings/Onboarding.
        await ActiveTutor.load();
        await DevSubscriptionOverride.load();
        const OrchestrationBootstrapper().bootstrap(
          content: ContentService.shared,
          store: CompetencyStore(db),
        );

        runApp(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: const FrenchTutorApp(),
          ),
        );
      } catch (error, stackTrace) {
        await Sentry.captureException(error, stackTrace: stackTrace);
        runApp(_StartupErrorApp(error: error, stackTrace: stackTrace));
      }
    },
  );
}

PilotPlatform _pilotPlatform() {
  if (kIsWeb) return PilotPlatform.web;
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => PilotPlatform.ios,
    TargetPlatform.android => PilotPlatform.android,
    _ => PilotPlatform.other,
  };
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
                const Text(
                  'Startup failed',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text('The app could not start. Details below:'),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      '$error\n\n$stackTrace',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
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
