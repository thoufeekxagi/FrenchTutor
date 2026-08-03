/// DEV-ONLY preview harness for the web design layer. NOT part of the shipped
/// app — it is a separate entrypoint, so it is only ever compiled when
/// explicitly targeted:
///
///   flutter run -d chrome -t lib/dev/web_preview.dart
///   flutter build web -t lib/dev/web_preview.dart
///
/// Why this exists: the real `WebAppShell` only appears after sign-in, which
/// makes iterating on its visual design slow and awkward (and impossible to
/// verify in CI or a sandbox without real credentials). This harness renders
/// the shell and every layout primitive against representative content, so the
/// web look can be reviewed and refined on its own. It also serves as the
/// living reference for what the primitives in `widgets/web/` look like.
///
/// Content here is placeholder text for layout purposes only. It is never
/// shown to a learner and is not wired to any real data.
library;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../design/app_theme.dart';
import '../widgets/web/web_app_shell.dart';
import '../widgets/web/web_layout.dart';

void main() => runApp(const WebPreviewApp());

const _destinations = [
  NavDestination(
    icon: CupertinoIcons.house,
    activeIcon: CupertinoIcons.house_fill,
    label: 'Today',
  ),
  NavDestination(
    icon: CupertinoIcons.map,
    activeIcon: CupertinoIcons.map_fill,
    label: 'Path',
  ),
  NavDestination(
    icon: CupertinoIcons.square_grid_2x2,
    activeIcon: CupertinoIcons.square_grid_2x2_fill,
    label: 'Practice',
  ),
  NavDestination(
    icon: CupertinoIcons.chart_bar_square,
    activeIcon: CupertinoIcons.chart_bar_square_fill,
    label: 'Progress',
  ),
];

class WebPreviewApp extends StatefulWidget {
  const WebPreviewApp({super.key});

  @override
  State<WebPreviewApp> createState() => _WebPreviewAppState();
}

class _WebPreviewAppState extends State<WebPreviewApp> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ParleSprint — web preview',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData(),
      home: WebAppShell(
        destinations: _destinations,
        currentIndex: _index,
        onSelect: (i) => setState(() => _index = i),
        topBarActions: [
          WebIconButton(
            icon: CupertinoIcons.gear,
            tooltip: 'Settings',
            onTap: () {},
          ),
        ],
        body: _PreviewBody(section: _destinations[_index].label),
      ),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.section});

  final String section;

  @override
  Widget build(BuildContext context) {
    return WebPage(
      header: WebPageHeader(
        title: 'Bonjour, Thoufeek',
        subtitle:
            'Twelve minutes today keeps your streak alive. Marie is ready when you are.',
      ),
      children: [
        // The primary "start here" surface — the equivalent of the reference's
        // hero composer card.
        WebCard(
          padding: const EdgeInsets.all(DesignTokens.space6),
          onTap: () {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: DesignTokens.heroGradient,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusMedium,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      CupertinoIcons.mic_fill,
                      size: 19,
                      color: DesignTokens.surface,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.space4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Today's mission", style: Passeport.display(18)),
                        const SizedBox(height: DesignTokens.space1),
                        Text(
                          'Ordering at a café, then five new connectors.',
                          style: Passeport.body(
                            14,
                          ).copyWith(color: DesignTokens.mutedDim),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.space5),
              Wrap(
                spacing: DesignTokens.space2,
                runSpacing: DesignTokens.space2,
                children: const [
                  WebChip(label: '12 min', icon: CupertinoIcons.clock),
                  WebChip(label: 'Speaking', icon: CupertinoIcons.waveform),
                  WebChip(label: 'A2 · Everyday', icon: CupertinoIcons.flag),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: DesignTokens.space6),
        const WebSectionHeader(title: 'Practice labs'),
        WebCardGrid(
          children: [
            for (final lab in const [
              (
                'Grammar lab',
                'Fix the six mistakes you keep repeating.',
                CupertinoIcons.textformat_abc,
              ),
              (
                'Writing lab',
                'One short paragraph, graded line by line.',
                CupertinoIcons.pencil_outline,
              ),
              (
                'Alphabet lab',
                'Hear every letter in a native voice.',
                CupertinoIcons.speaker_2,
              ),
              (
                'Liaison lab',
                'Where the words run together.',
                CupertinoIcons.link,
              ),
              (
                'Connectors lab',
                'Sound fluent, not like a phrasebook.',
                CupertinoIcons.arrow_right_arrow_left,
              ),
              (
                'Story reader',
                'Read with a tap-to-translate safety net.',
                CupertinoIcons.book,
              ),
            ])
              WebCard(
                onTap: () {},
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(lab.$3, size: 22, color: DesignTokens.primary),
                    const SizedBox(height: DesignTokens.space4),
                    Text(lab.$1, style: Passeport.display(16)),
                    const SizedBox(height: DesignTokens.space2),
                    Text(
                      lab.$2,
                      style: Passeport.body(
                        13,
                      ).copyWith(color: DesignTokens.mutedDim, height: 1.45),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: DesignTokens.space6),
        WebSectionHeader(
          title: 'Recent sessions',
          actionLabel: 'View all',
          onAction: () {},
        ),
        WebCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: DesignTokens.hairline,
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.space5,
                    vertical: DesignTokens.space4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.checkmark_seal_fill,
                        size: 18,
                        color: DesignTokens.success,
                      ),
                      const SizedBox(width: DesignTokens.space4),
                      Expanded(
                        child: Text(
                          [
                            'Café conversation with Marie',
                            'Connectors drill — 18 cards',
                            'Story: Le marché du samedi',
                          ][i],
                          style: Passeport.body(14, weight: FontWeight.w500),
                        ),
                      ),
                      Text(
                        ['Today', 'Yesterday', '3 days ago'][i],
                        style: Passeport.body(
                          13,
                        ).copyWith(color: DesignTokens.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: DesignTokens.space6),
        Text(
          'Preview harness · section: $section',
          style: Passeport.mono(11).copyWith(color: DesignTokens.muted),
        ),
      ],
    );
  }
}
