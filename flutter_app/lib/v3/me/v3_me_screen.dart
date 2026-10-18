import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/profile.dart';
import '../../models/tutor_persona.dart';
import '../../providers/appearance_provider.dart';
import '../../providers/database_provider.dart';
import '../../screens/speak/v3_settings_screen.dart';
import '../../services/app_appearance_settings.dart';
import '../ui/v3_ui.dart';

/// Me tab. Screen contract:
///
/// User arrived to: check progress and change settings.
/// They must understand: their starting level, their goal, and where settings live.
/// Primary action: none; a calm list.
/// Must not contain: invented per-skill levels. Until a real mock exists the
/// card says so and points to Tests.
class V3MeScreen extends ConsumerWidget {
  const V3MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(learningStoreProvider).profile();
    final dark = ref.watch(appearanceSettingsProvider).darkMode;
    final tutor = ActiveTutor.current;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        children: [
          Text('YOUR PROGRESS', style: V3Type.eyebrow()),
          const SizedBox(height: 6),
          Text('Me', style: V3Type.hero(44)),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: DesignTokens.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: DesignTokens.hairline),
              boxShadow: DesignTokens.surfaceShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'STARTING LEVEL',
                            style: V3Type.eyebrow(DesignTokens.inkSoft),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            LearnerLevel.displayLabel(profile.level),
                            style: V3Type.title(30),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'GOAL',
                          style: V3Type.eyebrow(DesignTokens.inkSoft),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'TCF Canada',
                          style: V3Type.title(24, color: DesignTokens.primary),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Your level estimate appears after your first mock test.',
                  style: V3Type.body(14.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _row(
            id: 'darkMode',
            title: 'Dark mode',
            subtitle: 'Black background instead of light',
            trailing: CupertinoSwitch(
              value: dark,
              activeTrackColor: DesignTokens.primary,
              onChanged: (v) => AppAppearanceSettings.shared.setDarkMode(v),
            ),
            label: 'Dark mode',
            onTap: () => AppAppearanceSettings.shared.setDarkMode(!dark),
          ),
          _row(
            id: 'tutor',
            title: 'Tutor voice',
            subtitle: tutor.tagline,
            trailing: Text(
              tutor.displayName,
              style: V3Type.strong(15, DesignTokens.primary),
            ),
            label: 'Tutor voice, ${tutor.displayName}',
            onTap: () =>
                AppRouter.push(context, (_) => const V3SettingsScreen()),
          ),
          _row(
            id: 'settings',
            title: 'Settings',
            subtitle: 'Reminders, membership, privacy, account',
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: DesignTokens.inkSoft,
            ),
            label: 'Settings',
            onTap: () =>
                AppRouter.push(context, (_) => const V3SettingsScreen()),
          ),
        ],
      ),
    );
  }

  Widget _row({
    required String id,
    required String title,
    required String subtitle,
    required Widget trailing,
    required String label,
    required VoidCallback onTap,
  }) {
    return V3Pressable(
      key: ValueKey('me.$id'),
      label: label,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: DesignTokens.hairline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: V3Type.strong(17)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: V3Type.body(13.5)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
      ),
    );
  }
}
