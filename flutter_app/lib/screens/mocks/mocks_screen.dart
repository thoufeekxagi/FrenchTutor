import '../../design/app_router.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../labs/listening_lab_screen.dart';
import '../labs/writing_lab_screen.dart';
import '../labs/connectors_lab_screen.dart';

/// Ported from MocksView.swift. Full timed mock exam simulation is a future feature
/// ("coming soon") — for now each skill links straight to its lab so students can build
/// foundations there first.
class MocksScreen extends StatelessWidget {
  const MocksScreen({super.key});

  static const _sections = [
    (name: 'Listening', icon: CupertinoIcons.headphones, time: '40 min', labId: 'listening'),
    (name: 'Reading', icon: CupertinoIcons.book, time: '60 min', labId: 'connectors'),
    (name: 'Writing', icon: CupertinoIcons.pencil, time: '60 min', labId: 'writing'),
    (name: 'Speaking', icon: CupertinoIcons.mic_fill, time: '15 min', labId: 'marie'),
  ];

  Widget? _destination(String labId) {
    switch (labId) {
      case 'listening':
        return const ListeningLabScreen();
      case 'writing':
        return const WritingLabScreen();
      case 'connectors':
        return const ConnectorsLabScreen();
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Passeport.parchmentDim,
      appBar: AppBar(
        title: Text('Mocks', style: Passeport.display(20)),
        backgroundColor: Passeport.parchmentDim,
        foregroundColor: Passeport.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          PasseportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const KickerText('Full simulation'),
                const SizedBox(height: 8),
                Text('TEF Canada mock exam', style: Passeport.display(18)),
                const SizedBox(height: 4),
                Text(
                  'All four skills, timed like the real exam. Coming soon — build your foundations in the Labs first.',
                  style: Passeport.body(12).copyWith(color: Passeport.slateDim),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ..._sections.map((section) {
            final destination = _destination(section.labId);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: destination == null
                    ? null
                    : () => Navigator.of(context).push(AppRouter.route(builder: (_) => destination)),
                child: PasseportCard(
                  padding: 13,
                  child: Row(
                    children: [
                      SizedBox(width: 22, child: Icon(section.icon, size: 16, color: Passeport.maroon)),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(section.name, style: Passeport.body(13)),
                            const SizedBox(height: 1),
                            Text(
                              'Practice in the lab first',
                              style: Passeport.mono(9.5).copyWith(color: Passeport.slateDim),
                            ),
                          ],
                        ),
                      ),
                      Text(section.time, style: Passeport.mono(11).copyWith(color: Passeport.slateDim)),
                      const SizedBox(width: 6),
                      Icon(CupertinoIcons.chevron_right, size: 16, color: Passeport.slate),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
