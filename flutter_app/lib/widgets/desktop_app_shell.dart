import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'adaptive/adaptive.dart';

/// One entry in the primary navigation, shared between the mobile bottom tab
/// bar (`MainTabScreen`) and [DesktopSidebar] so the destination list is
/// defined exactly once regardless of which shell is active.
class NavDestination {
  const NavDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Desktop/wide-web navigation shell: a persistent left sidebar plus a top
/// bar, replacing the mobile bottom tab bar above `DesignTokens.breakpointExpanded`.
/// Wraps the same screens the mobile shell uses — see docs/web_migration/02_phase2_web_app_shell.md.
class DesktopAppShell extends StatelessWidget {
  const DesktopAppShell({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelect,
    required this.body,
  });

  final List<NavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _DesktopSidebar(
            destinations: destinations,
            currentIndex: currentIndex,
            onSelect: onSelect,
          ),
          Expanded(
            child: Column(
              children: [
                _DesktopTopBar(title: destinations[currentIndex].label),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.destinations,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<NavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: Passeport.surface,
        border: Border(right: BorderSide(color: Passeport.hairline)),
      ),
      child: SafeArea(
        right: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.space5,
                DesignTokens.space5,
                DesignTokens.space5,
                DesignTokens.space4,
              ),
              child: Text('ParleSprint', style: Passeport.display(20)),
            ),
            for (var i = 0; i < destinations.length; i++)
              _SidebarRow(
                destination: destinations[i],
                isActive: i == currentIndex,
                onTap: () {
                  if (i != currentIndex) PSHaptics.selection();
                  onSelect(i);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.destination,
    required this.isActive,
    required this.onTap,
  });

  final NavDestination destination;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? Passeport.primary : Passeport.mutedDim;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.space3,
        vertical: DesignTokens.space1 / 2,
      ),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: DesignTokens.curveStandard,
          constraints: const BoxConstraints(
            minHeight: DesignTokens.minTapTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.space4,
            vertical: DesignTokens.space2,
          ),
          decoration: BoxDecoration(
            color: isActive ? Passeport.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                isActive ? destination.activeIcon : destination.icon,
                size: 22,
                color: color,
              ),
              const SizedBox(width: DesignTokens.space3),
              Text(
                destination.label,
                style: Passeport.body(
                  15,
                  weight: isActive ? FontWeight.w600 : FontWeight.w400,
                ).copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Passeport.surface,
        border: Border(bottom: BorderSide(color: Passeport.hairline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.space6),
      alignment: Alignment.centerLeft,
      child: Text(title, style: Passeport.display(17)),
    );
  }
}
