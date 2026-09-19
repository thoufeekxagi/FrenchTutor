import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/design/app_theme.dart';

void main() {
  test(
    'shared toast colors are fixed black background and white foreground',
    () {
      expect(AppTheme.snackBarBackgroundColor, Colors.black);
      expect(AppTheme.snackBarForegroundColor, Colors.white);
    },
  );
}
