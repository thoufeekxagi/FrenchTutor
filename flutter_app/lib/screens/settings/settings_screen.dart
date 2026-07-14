import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../widgets/kicker_text.dart';

const availableModels = [
  'meta-llama/llama-3.3-70b-instruct:free',
  'google/gemma-3-27b-it:free',
  'mistralai/mistral-small-3.1-24b-instruct:free',
];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  double _narrationRate = 0.42;
  int _newCardsPerDay = 20;
  DateTime _roadmapStartDate = DateTime.now();
  String _modelOverride = '';
  String _openRouterKey = '';
  bool _notetakerEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _narrationRate = prefs.getDouble('lesson_narration_rate') ?? 0.42;
      _newCardsPerDay = prefs.getInt('srs_new_cards_per_day') ?? 20;
      _modelOverride = prefs.getString('openrouter_model_override') ?? '';
      _openRouterKey = prefs.getString('openrouter_api_key') ?? '';
      _notetakerEnabled = prefs.getBool('notetaker_enabled') ?? false;
      final timestamp = prefs.getInt('roadmap_start_date');
      if (timestamp != null) {
        _roadmapStartDate =
            DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    });
  }

  Future<void> _saveDouble(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
  }

  Future<void> _saveInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _pickRoadmapStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _roadmapStartDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Passeport.maroon,
              onPrimary: Colors.white,
              surface: Passeport.parchment,
              onSurface: Passeport.text,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _roadmapStartDate = picked);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          'roadmap_start_date', picked.millisecondsSinceEpoch);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Passeport.parchmentDim,
      appBar: AppBar(
        backgroundColor: Passeport.parchmentDim,
        title: Text('Settings', style: Passeport.display(20)),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        children: [
          // --- Exam / Target ---
          _PasseportCard(
            child: Column(
              children: [
                _SettingsRow(label: 'Exam', value: 'TEF Canada'),
                Divider(height: 1, color: Passeport.hairline),
                _SettingsRow(label: 'Target', value: 'CLB 7'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // --- Roadmap ---
          _PasseportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KickerText('Roadmap', color: Passeport.slateDim),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _pickRoadmapStartDate,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Text(
                          'Start date',
                          style: Passeport.body(12.5)
                              .copyWith(color: Passeport.slateDim),
                        ),
                        const Spacer(),
                        Text(
                          DateFormat.yMMMd().format(_roadmapStartDate),
                          style: Passeport.mono(12, weight: FontWeight.w500)
                              .copyWith(color: Passeport.maroon),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.calendar_today,
                            size: 14, color: Passeport.maroon),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // --- Lesson voice ---
          _PasseportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KickerText('Lesson voice', color: Passeport.slateDim),
                const SizedBox(height: 10),
                Text(
                  'Narration rate',
                  style: Passeport.body(12.5)
                      .copyWith(color: Passeport.slateDim),
                ),
                const SizedBox(height: 4),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: Passeport.maroon,
                    inactiveTrackColor: Passeport.maroon.withValues(alpha: 0.2),
                    thumbColor: Passeport.maroon,
                    overlayColor: Passeport.maroon.withValues(alpha: 0.12),
                  ),
                  child: Slider(
                    value: _narrationRate,
                    min: 0.3,
                    max: 0.55,
                    onChanged: (v) {
                      setState(() => _narrationRate = v);
                      _saveDouble('lesson_narration_rate', v);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'New cards/day: $_newCardsPerDay',
                      style: Passeport.body(12.5)
                          .copyWith(color: Passeport.text),
                    ),
                    const Spacer(),
                    _StepperButton(
                      icon: Icons.remove,
                      onTap: _newCardsPerDay > 5
                          ? () {
                              setState(() => _newCardsPerDay -= 5);
                              _saveInt(
                                  'srs_new_cards_per_day', _newCardsPerDay);
                            }
                          : null,
                    ),
                    const SizedBox(width: 8),
                    _StepperButton(
                      icon: Icons.add,
                      onTap: _newCardsPerDay < 50
                          ? () {
                              setState(() => _newCardsPerDay += 5);
                              _saveInt(
                                  'srs_new_cards_per_day', _newCardsPerDay);
                            }
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // --- AI tutor (OpenRouter) ---
          _PasseportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KickerText('AI tutor (OpenRouter)',
                    color: Passeport.slateDim),
                const SizedBox(height: 10),
                _SettingsRow(
                  label: 'Key status',
                  value: _openRouterKey.isEmpty ? 'Not set' : 'Configured',
                ),
                Divider(height: 1, color: Passeport.hairline),
                const SizedBox(height: 10),
                Text(
                  'Preferred model',
                  style: Passeport.body(12.5)
                      .copyWith(color: Passeport.slateDim),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Passeport.hairline),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _modelOverride,
                      isExpanded: true,
                      style: Passeport.body(12.5)
                          .copyWith(color: Passeport.text),
                      dropdownColor: Passeport.parchment,
                      icon: const Icon(Icons.arrow_drop_down,
                          color: Passeport.maroon),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text('Auto (fallback chain)',
                              style: Passeport.body(12.5)),
                        ),
                        ...availableModels.map((model) => DropdownMenuItem(
                              value: model,
                              child: Text(model,
                                  style: Passeport.mono(11),
                                  overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _modelOverride = v);
                        _saveString('openrouter_model_override', v);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // --- Notetaker ---
          _PasseportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KickerText('Notetaker', color: Passeport.slateDim),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text('Floating notetaker',
                        style: Passeport.body(12.5)),
                    const Spacer(),
                    Switch.adaptive(
                      value: _notetakerEnabled,
                      activeColor: Passeport.maroon,
                      onChanged: (v) {
                        setState(() => _notetakerEnabled = v);
                        _saveBool('notetaker_enabled', v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Shows a draggable note bubble during lessons so you can '
                  'jot things down while listening or writing.',
                  style: Passeport.body(11)
                      .copyWith(color: Passeport.slateDim),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable helpers
// ---------------------------------------------------------------------------

class _PasseportCard extends StatelessWidget {
  const _PasseportCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Passeport.hairline),
      ),
      child: child,
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Text(label,
              style:
                  Passeport.body(12.5).copyWith(color: Passeport.slateDim)),
          const Spacer(),
          Text(value,
              style: Passeport.mono(12, weight: FontWeight.w500)
                  .copyWith(color: Passeport.text)),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled
              ? Passeport.maroon.withValues(alpha: 0.1)
              : Passeport.slate.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? Passeport.maroon : Passeport.slate,
        ),
      ),
    );
  }
}
