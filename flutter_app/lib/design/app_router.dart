import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The one way screens navigate. Guarantees the right route type per platform
/// (CupertinoPageRoute on iOS keeps the edge-swipe back gesture alive) and a
/// typed result so stage screens can return evidence exactly once.
///
/// Screens must not construct MaterialPageRoute/PageRouteBuilder directly —
/// grep-enforced during review (see PILOT_PLAN.md Phase 0.2).
abstract final class AppRouter {
  static Route<T> route<T>(WidgetBuilder builder, {bool fullscreenDialog = false}) {
    if (AppTheme.isCupertino) {
      return CupertinoPageRoute<T>(builder: builder, fullscreenDialog: fullscreenDialog);
    }
    return MaterialPageRoute<T>(builder: builder, fullscreenDialog: fullscreenDialog);
  }

  static Future<T?> push<T>(BuildContext context, WidgetBuilder builder,
      {bool fullscreenDialog = false}) {
    return Navigator.of(context)
        .push<T>(route<T>(builder, fullscreenDialog: fullscreenDialog));
  }

  static Future<T?> pushReplacement<T>(BuildContext context, WidgetBuilder builder) {
    return Navigator.of(context).pushReplacement(route<T>(builder));
  }
}
