import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../models/tutor_persona.dart';
import '../../services/tutor_voice_preview.dart';
import '../ui/v3_ui.dart';

/// Screen: V3 tutor picker. Key prefix: tutor.
/// User arrived to: onboarding or Settings and wants to choose a tutor.
/// They must understand: the four available tutors and their speaking voices.
/// Primary action: use the selected tutor.
/// Secondary action: preview a voice or close without changing the choice.
/// Success state: the caller saves the selected persona.
/// Must not contain: unsupported teaching claims or a hidden voice preview.
/// States: default, selected, previewing, loading, interrupted, completed.
Future<TutorPersona?> showV3TutorPickerSheet({
  required BuildContext context,
  required TutorPersona selected,
}) => showModalBottomSheet<TutorPersona>(
  context: context,
  backgroundColor: DesignTokens.canvas,
  showDragHandle: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (_) => V3TutorPickerSheet(selected: selected),
);

class V3TutorPickerSheet extends StatefulWidget {
  const V3TutorPickerSheet({super.key, required this.selected});

  final TutorPersona selected;

  @override
  State<V3TutorPickerSheet> createState() => _V3TutorPickerSheetState();
}

class _V3TutorPickerSheetState extends State<V3TutorPickerSheet> {
  late TutorPersona _selected;
  late final TutorVoicePreviewer _previewer;

  @override
  void initState() {
    super.initState();
    _selected = widget.selected;
    _previewer = TutorVoicePreviewer()..addListener(_previewChanged);
  }

  @override
  void didUpdateWidget(covariant V3TutorPickerSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected.id != widget.selected.id) {
      _selected = widget.selected;
    }
  }

  void _previewChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _togglePreview(TutorPersona tutor) async {
    final active =
        _previewer.playingId == tutor.id || _previewer.loadingId == tutor.id;
    if (active) {
      await _previewer.stop();
    } else {
      await _previewer.play(tutor);
    }
  }

  Future<void> _confirm() async {
    await _previewer.stop();
    if (mounted) Navigator.of(context).pop(_selected);
  }

  @override
  void dispose() {
    _previewer.removeListener(_previewChanged);
    unawaited(_previewer.stop());
    _previewer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose your tutor',
                      style: DesignTokens.display(
                        24,
                      ).copyWith(color: DesignTokens.nightText),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('tutor.close'),
                    tooltip: 'Close tutor choices',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Choose the voice you want to learn with.',
                style: DesignTokens.body(
                  14,
                ).copyWith(color: DesignTokens.nightMuted),
              ),
              const SizedBox(height: 16),
              for (final tutor in TutorPersona.all) ...[
                _tutorOption(tutor),
                if (tutor != TutorPersona.all.last) const SizedBox(height: 8),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('tutor.confirm'),
                  onPressed: _confirm,
                  icon: const Icon(Icons.check_rounded),
                  label: Text('Use ${_selected.displayName}'),
                  style: FilledButton.styleFrom(
                    backgroundColor: DesignTokens.nightAccent,
                    foregroundColor: DesignTokens.onPrimary,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: DesignTokens.body(15, weight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tutorOption(TutorPersona tutor) {
    final selected = _selected.id == tutor.id;
    final loading = _previewer.loadingId == tutor.id;
    final playing = _previewer.playingId == tutor.id;

    return AnimatedContainer(
      duration: DesignTokens.durationFast,
      curve: DesignTokens.curveStandard,
      decoration: BoxDecoration(
        color: selected
            ? DesignTokens.nightAccentSoft
            : DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected
              ? DesignTokens.nightAccent
              : DesignTokens.nightHairline,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: V3Pressable(
              key: ValueKey('tutor.option.${tutor.id}'),
              label:
                  'Select ${tutor.displayName}, ${tutor.accent.label}. ${tutor.tagline}.',
              selected: selected,
              onTap: () => setState(() => _selected = tutor),
              child: SizedBox(
                height: 76,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  child: Row(
                    children: [
                      ClipOval(
                        child: Image.asset(
                          tutor.portraitAsset,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          errorBuilder: (_, _, _) => Container(
                            width: 50,
                            height: 50,
                            color: DesignTokens.nightAccentSoft,
                            alignment: Alignment.center,
                            child: Text(
                              tutor.initial,
                              style: DesignTokens.body(
                                18,
                                weight: FontWeight.w700,
                              ).copyWith(color: DesignTokens.nightAccent),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tutor.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DesignTokens.body(
                                16,
                                weight: FontWeight.w700,
                              ).copyWith(color: DesignTokens.nightText),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${tutor.tagline} · ${tutor.accent.label}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: DesignTokens.body(
                                12,
                              ).copyWith(color: DesignTokens.nightMuted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (selected)
                        Icon(
                          Icons.check_circle_rounded,
                          color: DesignTokens.nightAccent,
                          size: 21,
                        )
                      else
                        Icon(
                          Icons.circle_outlined,
                          color: DesignTokens.nightMuted.withValues(alpha: 0.6),
                          size: 21,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            key: ValueKey('tutor.preview.${tutor.id}'),
            tooltip: loading
                ? 'Stop ${tutor.displayName} preview'
                : 'Preview ${tutor.displayName}',
            onPressed: () => _togglePreview(tutor),
            color: DesignTokens.nightAccent,
            icon: loading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    playing
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outline_rounded,
                    size: 25,
                  ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
