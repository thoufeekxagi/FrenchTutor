import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../models/profile.dart';
import '../../providers/database_provider.dart';
import 'speak_ui.dart';

/// The deep learning controls live inside the same visual system as the
/// primary app. Keeping them separate from the compact settings landing page
/// mirrors Speak's focused, drill-down settings flow.
class SpeakAdvancedSettingsScreen extends ConsumerStatefulWidget {
  const SpeakAdvancedSettingsScreen({super.key});

  @override
  ConsumerState<SpeakAdvancedSettingsScreen> createState() =>
      _SpeakAdvancedSettingsScreenState();
}

class _SpeakAdvancedSettingsScreenState
    extends ConsumerState<SpeakAdvancedSettingsScreen> {
  var _voiceRecognition = true;
  var _autoMode = true;
  var _speaking = true;
  var _roleplay = true;
  var _stories = false;
  var _listening = true;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(learningStoreProvider).profile();
    final level = _normaliseLevel(profile.level);
    final minutes = switch (profile.sessionLength) {
      'quick' => 5,
      'deep' => 20,
      _ => 10,
    };

    return SpeakScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          SpeakHeader(
            title: 'Learning controls',
            subtitle: 'Shape the way your course feels.',
            leading: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: SpeakColors.inkSoft,
              ),
            ),
          ),
          const SizedBox(height: 26),
          _sectionLabel('Course level'),
          const SizedBox(height: 9),
          SpeakCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The path uses this to choose the difficulty of every next session.',
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in LearnerLevel.cefrValues)
                      SpeakPill(
                        label: option.toUpperCase(),
                        selected: option == level,
                        onTap: () => _saveLevel(option),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _sectionLabel('Daily practice'),
          const SizedBox(height: 9),
          SpeakCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A shorter promise is better than a plan you stop using.',
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final option in [5, 10, 15, 20])
                      SpeakPill(
                        label: '$option min',
                        selected: option == minutes,
                        onTap: () => _saveMinutes(option),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _sectionLabel('Practice modes'),
          const SizedBox(height: 9),
          SpeakCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _toggle(
                  'Speaking',
                  'Say the useful line out loud',
                  _speaking,
                  (value) => setState(() => _speaking = value),
                ),
                const Divider(height: 1, color: SpeakColors.line),
                _toggle(
                  'Roleplay',
                  'Use it in a real situation',
                  _roleplay,
                  (value) => setState(() => _roleplay = value),
                ),
                const Divider(height: 1, color: SpeakColors.line),
                _toggle(
                  'Stories',
                  'Meet the phrase in context',
                  _stories,
                  (value) => setState(() => _stories = value),
                ),
                const Divider(height: 1, color: SpeakColors.line),
                _toggle(
                  'Listening',
                  'Train your ear before speaking',
                  _listening,
                  (value) => setState(() => _listening = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _sectionLabel('Session behavior'),
          const SizedBox(height: 9),
          SpeakCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _toggle(
                  'Voice recognition',
                  'Let the tutor listen for pronunciation feedback',
                  _voiceRecognition,
                  (value) => setState(() => _voiceRecognition = value),
                ),
                const Divider(height: 1, color: SpeakColors.line),
                _toggle(
                  'Auto mode',
                  'Keep the conversation moving naturally',
                  _autoMode,
                  (value) => setState(() => _autoMode = value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _normaliseLevel(String value) {
    return LearnerLevel.cefrValues.contains(value) ? value : 'a1';
  }

  void _saveLevel(String value) {
    final store = ref.read(learningStoreProvider);
    final profile = store.profile()..level = value;
    store.saveProfile(profile);
    setState(() {});
  }

  void _saveMinutes(int value) {
    final store = ref.read(learningStoreProvider);
    final profile = store.profile()
      ..sessionLength = switch (value) {
        5 => 'quick',
        20 => 'deep',
        _ => 'standard',
      };
    store.saveProfile(profile);
    setState(() {});
  }

  Widget _sectionLabel(String label) => Text(
    label.toUpperCase(),
    style: DesignTokens.label(
      10,
    ).copyWith(color: SpeakColors.inkSoft, letterSpacing: 1),
  );

  Widget _toggle(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DesignTokens.body(14, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: DesignTokens.body(
                    11.5,
                  ).copyWith(color: SpeakColors.inkSoft),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: SpeakColors.blue,
          ),
        ],
      ),
    );
  }
}
