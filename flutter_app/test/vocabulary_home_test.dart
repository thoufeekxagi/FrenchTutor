import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:french_tutor/design/app_theme.dart';
import 'package:french_tutor/providers/database_provider.dart';
import 'package:french_tutor/screens/labs/vocab_lab_screen.dart';
import 'package:french_tutor/services/app_appearance_settings.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'sb_publishable_test_key',
    );
  });

  tearDown(() => AppAppearanceSettings.shared.adoptDarkMode(true));

  testWidgets('vocabulary home exposes five story-set tiles', (tester) async {
    AppAppearanceSettings.shared.adoptDarkMode(false);
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.themeData(darkMode: false),
          home: const VocabLabScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Make words stick'), findsOneWidget);
    expect(find.text('5 story sets · 0 complete'), findsOneWidget);
    expect(find.text('Context'), findsNothing);
    expect(find.text('Words only'), findsNothing);
    expect(find.text('Morning breakfast', skipOffstage: false), findsWidgets);
    expect(find.text('At the café', skipOffstage: false), findsOneWidget);
    expect(find.text('At the station', skipOffstage: false), findsOneWidget);
    expect(find.text('Home after work', skipOffstage: false), findsOneWidget);
    expect(find.text('Weekend market', skipOffstage: false), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Create a custom set'),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Create a custom set', skipOffstage: false),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
