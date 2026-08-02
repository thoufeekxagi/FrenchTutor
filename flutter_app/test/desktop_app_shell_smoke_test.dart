import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/widgets/desktop_app_shell.dart';

void main() {
  testWidgets('DesktopAppShell renders sidebar destinations and switches body on tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    var index = 0;
    const destinations = [
      NavDestination(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Today',
      ),
      NavDestination(
        icon: Icons.map_outlined,
        activeIcon: Icons.map,
        label: 'Path',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => DesktopAppShell(
            destinations: destinations,
            currentIndex: index,
            onSelect: (i) => setState(() => index = i),
            body: Text('Body for index $index'),
          ),
        ),
      ),
    );

    expect(find.text('ParleSprint'), findsOneWidget);
    // "Today" appears twice while active: once in the sidebar row, once
    // mirrored as the top bar title.
    expect(find.text('Today'), findsNWidgets(2));
    expect(find.text('Path'), findsOneWidget);
    expect(find.text('Body for index 0'), findsOneWidget);

    await tester.tap(find.text('Path'));
    await tester.pumpAndSettle();

    expect(find.text('Body for index 1'), findsOneWidget);
    expect(find.text('Path'), findsNWidgets(2));
  });
}
