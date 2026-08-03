import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../adaptive/adaptive.dart';

/// Sidebar width. Wide enough for icon + label without truncating any of our
/// destination names, narrow enough to leave the content column dominant.
const double kWebSidebarWidth = 244.0;

/// Top bar height.
const double kWebTopBarHeight = 60.0;

/// One entry in the primary navigation, shared between the mobile bottom tab
/// bar (`MainTabScreen`) and [WebAppShell]'s sidebar so the destination list
/// is defined exactly once regardless of which shell is active.
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
/// bar, replacing the mobile bottom tab bar above
/// `DesignTokens.breakpointExpanded`.
///
/// Structure follows the ElevenLabs dashboard reference — sidebar rail for
/// primary navigation, slim top bar for page context and account actions,
/// content on a slightly dimmed canvas so white cards read as raised without
/// needing shadows. Colours and type are entirely this app's own tokens.
///
/// The same screens the mobile shell shows are placed inside [body]; nothing
/// is duplicated or re-implemented per platform. See
/// docs/web_migration/02_phase2_web_app_shell.md.
class WebAppShell extends StatelessWidget {
  const WebAppShell({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelect,
    required this.body,
    this.topBarActions = const [],
    this.sidebarFooter,
  });

  final List<NavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final Widget body;

  /// Trailing widgets in the top bar (account, settings, etc.).
  final List<Widget> topBarActions;

  /// Optional block pinned to the bottom of the sidebar.
  final Widget? sidebarFooter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(
            destinations: destinations,
            currentIndex: currentIndex,
            onSelect: onSelect,
            footer: sidebarFooter,
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  title: destinations[currentIndex].label,
                  actions: topBarActions,
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.destinations,
    required this.currentIndex,
    required this.onSelect,
    this.footer,
  });

  final List<NavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kWebSidebarWidth,
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        border: Border(right: BorderSide(color: DesignTokens.hairline)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _BrandHeader(),
            const _GroupLabel('Learn'),
            for (var i = 0; i < destinations.length; i++)
              _NavRow(
                destination: destinations[i],
                isActive: i == currentIndex,
                onTap: () {
                  if (i != currentIndex) PSHaptics.selection();
                  onSelect(i);
                },
              ),
            const Spacer(),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.all(DesignTokens.space3),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// Brand lockup at the top of the sidebar: gradient mark plus wordmark, the
/// slot the reference uses for its workspace switcher.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.space5,
        DesignTokens.space5,
        DesignTokens.space4,
        DesignTokens.space6,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: DesignTokens.heroGradient,
              borderRadius: BorderRadius.circular(DesignTokens.radiusSmall),
            ),
            alignment: Alignment.center,
            child: Text(
              'P',
              style: Passeport.display(
                15,
              ).copyWith(color: DesignTokens.surface),
            ),
          ),
          const SizedBox(width: DesignTokens.space3),
          Expanded(
            child: Text(
              'ParleSprint',
              style: Passeport.display(17),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Quiet uppercase group heading — spaced caps, the reference's "Pinned"
/// treatment.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.space5 + 2,
        0,
        DesignTokens.space5,
        DesignTokens.space2,
      ),
      child: Text(
        label.toUpperCase(),
        style: Passeport.mono(
          11,
          weight: FontWeight.w600,
        ).copyWith(color: DesignTokens.muted),
      ),
    );
  }
}

class _NavRow extends StatefulWidget {
  const _NavRow({
    required this.destination,
    required this.isActive,
    required this.onTap,
  });

  final NavDestination destination;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    final foreground = active
        ? DesignTokens.primary
        : (_hovered ? DesignTokens.ink : DesignTokens.mutedDim);
    final background = active
        ? DesignTokens.primarySoft
        : (_hovered ? DesignTokens.canvasDim : null);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.space3,
        vertical: 2,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: DesignTokens.durationFast,
            curve: DesignTokens.curveStandard,
            constraints: const BoxConstraints(
              minHeight: DesignTokens.minTapTarget,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.space3,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(DesignTokens.radiusSmall),
            ),
            child: Row(
              children: [
                Icon(
                  active
                      ? widget.destination.activeIcon
                      : widget.destination.icon,
                  size: 20,
                  color: foreground,
                ),
                const SizedBox(width: DesignTokens.space3),
                Expanded(
                  child: Text(
                    widget.destination.label,
                    style: Passeport.body(
                      14,
                      weight: active ? FontWeight.w600 : FontWeight.w500,
                    ).copyWith(color: foreground),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kWebTopBarHeight,
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        border: Border(bottom: BorderSide(color: DesignTokens.hairline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.space6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Passeport.display(16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Circular icon button sized for the top bar. Quiet by default, tinted
/// canvas on hover — the standard web affordance for a toolbar control.
class WebIconButton extends StatefulWidget {
  const WebIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  State<WebIconButton> createState() => _WebIconButtonState();
}

class _WebIconButtonState extends State<WebIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: DesignTokens.durationFast,
            curve: DesignTokens.curveStandard,
            width: DesignTokens.minTapTarget,
            height: DesignTokens.minTapTarget,
            decoration: BoxDecoration(
              color: _hovered ? DesignTokens.canvasDim : null,
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.icon,
              size: 19,
              color: _hovered ? DesignTokens.ink : DesignTokens.mutedDim,
            ),
          ),
        ),
      ),
    );
  }
}
