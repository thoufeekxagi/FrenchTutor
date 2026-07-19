import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/theme.dart';

/// The in-call error banner, shared by every live screen. Most errors are
/// plain text — but a denied microphone permission gets a real recovery path:
/// iOS never re-prompts once denied, so "Open Settings" is the ONLY way back,
/// and a banner that just states the problem is a dead end.
class ErrorNotice extends StatelessWidget {
  const ErrorNotice({super.key, required this.message});

  final String message;

  bool get _isMicPermission =>
      message.toLowerCase().contains('microphone permission');

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(
        horizontal: DesignTokens.screenMargin,
        vertical: DesignTokens.space2,
      ),
      padding: const EdgeInsets.all(DesignTokens.space3),
      decoration: BoxDecoration(
        color: DesignTokens.primarySoft,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
      ),
      child: _isMicPermission
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Microphone access is needed to practice speaking. Enable '
                  'it in Settings, then come back, the session will pick up '
                  'right where you are.',
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: DesignTokens.inkSoft, height: 1.35),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: openAppSettings,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: DesignTokens.primary,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      'Open Settings',
                      style: DesignTokens.body(
                        12.5,
                        weight: FontWeight.w700,
                      ).copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ],
            )
          : Text(
              message,
              style: DesignTokens.body(
                13,
              ).copyWith(color: DesignTokens.inkSoft, height: 1.35),
            ),
    );
  }
}
