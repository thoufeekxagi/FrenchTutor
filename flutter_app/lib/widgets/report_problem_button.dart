import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/theme.dart';

/// Opens the device's own mail app with a pre-filled draft to support —
/// required in-call affordance for AI-generated content per Apple's 2026
/// review guidance. This never sends anything itself: the user still has to
/// tap send in their own mail app.
class ReportProblemButton extends StatelessWidget {
  const ReportProblemButton({
    super.key,
    required this.sessionType,
    this.personaName,
  });

  final String sessionType;
  final String? personaName;

  static const _supportEmail = 'thoufeekbaber1@gmail.com';

  Future<void> _report() async {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final body =
        'Describe what went wrong:\n\n\n'
        '---\n'
        'Session: $sessionType\n'
        'Tutor: ${personaName ?? '-'}\n'
        'Time (UTC): $timestamp\n';
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {
        'subject': 'ParleSprint — report a problem',
        'body': body,
      },
    );
    try {
      await launchUrl(uri);
    } catch (_) {
      // No mail app configured on this device — nothing more we can do here.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Report a problem',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _report,
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            CupertinoIcons.flag,
            size: 19,
            color: Passeport.slateDim,
          ),
        ),
      ),
    );
  }
}
