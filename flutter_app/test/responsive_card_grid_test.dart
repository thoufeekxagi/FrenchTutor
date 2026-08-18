import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/widgets/responsive_card_grid.dart';

void main() {
  testWidgets('appends new cards after the existing five-card lane', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ResponsiveCardGrid(
            itemCount: 7,
            maxCardWidth: 100,
            mainAxisExtent: 80,
            itemBuilder: _card,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final newest = tester.getTopLeft(find.text('item 0'));
    final fifthOldest = tester.getTopLeft(find.text('item 2'));
    final oldest = tester.getTopLeft(find.text('item 6'));
    final secondOldest = tester.getTopLeft(find.text('item 5'));

    // The newest item is appended to the second lane, not inserted before
    // the first item and allowed to displace the fifth card.
    expect(newest.dy, greaterThan(fifthOldest.dy));
    expect(oldest.dy, fifthOldest.dy);
    expect(oldest.dx, lessThan(secondOldest.dx));
  });
}

Widget _card(BuildContext context, int index) {
  return ColoredBox(
    color: Colors.white,
    child: Center(child: Text('item $index')),
  );
}
