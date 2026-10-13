import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../learn/v3_learn_screen.dart';
import '../marie/v3_marie_screen.dart';
import '../me/v3_me_screen.dart';
import '../tests/v3_tests_screen.dart';
import '../ui/v3_ui.dart';

/// V3 main shell. Screen contract:
///
/// User arrived to: the app after onboarding, consent and sign-in.
/// They must understand: four places only (Learn, Marie, Tests, Me).
/// Primary action: whatever the selected tab offers.
/// Must not contain: a fifth tab, floating navigation, tour overlays.
class V3Shell extends StatefulWidget {
  const V3Shell({super.key});

  @override
  State<V3Shell> createState() => _V3ShellState();
}

class _V3ShellState extends State<V3Shell> {
  var _index = 0;

  static const _tabs = [
    (Icons.menu_book_outlined, Icons.menu_book_rounded, 'Learn', 'learn'),
    (Icons.mic_none_rounded, Icons.mic_rounded, 'Marie', 'marie'),
    (Icons.timer_outlined, Icons.timer_rounded, 'Tests', 'tests'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Me', 'me'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: V3Width(
        child: IndexedStack(
          index: _index,
          children: const [
            V3LearnScreen(),
            V3MarieScreen(),
            V3TestsScreen(),
            V3MeScreen(),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: DesignTokens.surface,
          border: Border(top: BorderSide(color: DesignTokens.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(child: _item(i)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(int i) {
    final (icon, activeIcon, label, id) = _tabs[i];
    final selected = _index == i;
    final color = selected ? DesignTokens.primary : DesignTokens.inkSoft;
    return V3Pressable(
      key: ValueKey('shell.tab.$id'),
      label: label,
      onTap: () => setState(() => _index = i),
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? activeIcon : icon, size: 24, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: V3Type.strong(11, color).copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
