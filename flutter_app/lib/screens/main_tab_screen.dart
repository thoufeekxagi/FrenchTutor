import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_router.dart';
import '../design/tokens.dart';
import '../models/tutor_persona.dart';
import '../providers/database_provider.dart';
import '../services/app_tour.dart';
import '../widgets/adaptive/adaptive.dart';
import '../widgets/floating_notetaker.dart';
import '../widgets/web/web_app_shell.dart';
import 'speak/speak_home_screen.dart';
import 'speak/speak_practice_screen.dart';
import 'speak/speak_profile_screen.dart';
import 'speak/speak_roadmap_screen.dart';
import 'speak/speak_settings_screen.dart';
import 'scan/scan_screen.dart';

/// Primary navigation destinations, defined once and shared between the
/// mobile bottom tab bar and the desktop sidebar so neither shell can drift
/// out of sync with the other.
const _destinations = [
  NavDestination(
    icon: Icons.home_outlined,
    activeIcon: Icons.home_rounded,
    label: 'Home',
  ),
  NavDestination(
    icon: Icons.route_outlined,
    activeIcon: Icons.route_rounded,
    label: 'Course',
  ),
  NavDestination(
    icon: Icons.grid_view_outlined,
    activeIcon: Icons.grid_view_rounded,
    label: 'Practice',
  ),
  NavDestination(
    icon: Icons.photo_camera_outlined,
    activeIcon: Icons.photo_camera_rounded,
    label: 'Photo tutor',
  ),
  NavDestination(
    icon: Icons.person_outline_rounded,
    activeIcon: Icons.person_rounded,
    label: 'Profile',
  ),
];

class MainTabScreen extends ConsumerStatefulWidget {
  const MainTabScreen({super.key});

  @override
  ConsumerState<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends ConsumerState<MainTabScreen> {
  int _currentIndex = 0;

  void _selectTab(int index) {
    if (_currentIndex == index) return;
    PSHaptics.selection();
    setState(() => _currentIndex = index);
    if (index == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppTour.playPracticeIfNeeded(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TutorPersona>(
      valueListenable: ActiveTutor.notifier,
      builder: (context, _, child) => _buildShell(context),
    );
  }

  Widget _buildShell(BuildContext context) {
    final notetaker = ref.watch(notetakerStateProvider);
    // Built fresh every rebuild so each Speak tab can observe the latest
    // session/profile state while the tab shell keeps its navigation index.
    final screens = [
      const SpeakHomeScreen(),
      const SpeakRoadmapScreen(embedded: true),
      const SpeakPracticeScreen(),
      const ScanScreen(),
      SpeakProfileScreen(
        onBack: () => setState(() => _currentIndex = 0),
        onReplayPractice: () => _selectTab(2),
      ),
    ];
    final body = Stack(
      children: [
        IndexedStack(index: _currentIndex, children: screens),
        if (_currentIndex < 3) FloatingNotetakerOverlay(state: notetaker),
      ],
    );

    final isDesktop =
        MediaQuery.sizeOf(context).width >= DesignTokens.breakpointExpanded;
    if (isDesktop) {
      return WebAppShell(
        destinations: _destinations,
        currentIndex: _currentIndex,
        onSelect: _selectTab,
        topBarActions: [
          WebIconButton(
            icon: CupertinoIcons.person,
            tooltip: 'Profile',
            onTap: () => AppRouter.push(
              context,
              (_) => SpeakSettingsScreen(onReplayPractice: () => _selectTab(2)),
            ),
          ),
        ],
        body: body,
      );
    }

    return Scaffold(body: body, bottomNavigationBar: _mobileIslandNavigation());
  }

  Widget _mobileIslandNavigation() {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: DesignTokens.surface,
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: DesignTokens.hairline),
        ),
        child: Row(
          children: [
            for (var index = 0; index < _destinations.length; index++)
              Expanded(
                child: _mobileNavItem(
                  index: index,
                  destination: _destinations[index],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mobileNavItem({
    required int index,
    required NavDestination destination,
  }) {
    final selected = _currentIndex == index;
    final item = Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _selectTab(index);
        },
        child: AnimatedContainer(
          duration: DesignTokens.durationFast,
          curve: DesignTokens.curveStandard,
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? DesignTokens.canvasDim : Colors.transparent,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? destination.activeIcon : destination.icon,
                size: 21,
                color: selected ? DesignTokens.ink : DesignTokens.mutedDim,
              ),
              const SizedBox(height: 3),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    DesignTokens.body(
                      10.5,
                      weight: selected ? FontWeight.w700 : FontWeight.w500,
                    ).copyWith(
                      color: selected
                          ? DesignTokens.ink
                          : DesignTokens.mutedDim,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
    final tourKey = switch (index) {
      0 => AppTour.homeTabKey,
      1 => AppTour.courseTabKey,
      2 => AppTour.practiceTabKey,
      3 => AppTour.photoTutorTabKey,
      4 => AppTour.profileTabKey,
      _ => null,
    };
    return tourKey == null ? item : KeyedSubtree(key: tourKey, child: item);
  }
}
