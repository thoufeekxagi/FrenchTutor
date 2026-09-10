import 'package:flutter/material.dart';

/// The shared error surface for tutor/session failures.
///
/// Session screens use dark artwork and white controls, so the platform's
/// light SnackBar fallback makes failures unreadable. Keep this presentation
/// centralized so Reading, Listening, and future session surfaces stay
/// consistent.
void showDarkErrorSnackBar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFF202024),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          side: BorderSide(color: Colors.white24),
        ),
      ),
    );
}
