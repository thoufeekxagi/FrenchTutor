import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/database/storage_service.dart';
import '../design/tokens.dart';
import 'adaptive/adaptive.dart';

/// Shared state for the floating notetaker bubble.
/// Ported from iOS FloatingNotetaker — manages draft text, position, and expansion.
class NotetakerState extends ChangeNotifier {
  NotetakerState({required this.storage}) {
    unawaited(_loadPrefs());
  }

  final StorageService storage;

  bool _isEnabled = true;
  bool get isEnabled => _isEnabled;
  set isEnabled(bool value) {
    _isEnabled = value;
    notifyListeners();
    SharedPreferences.getInstance().then(
      (p) => p.setBool('notetaker.enabled', value),
    );
  }

  bool _isExpanded = false;
  bool get isExpanded => _isExpanded;
  set isExpanded(bool value) {
    _isExpanded = value;
    notifyListeners();
  }

  String _draftText = '';
  String get draftText => _draftText;
  set draftText(String value) {
    if (_draftText == value) return;
    _draftText = value;
    notifyListeners();
    _persistDraftSoon();
  }

  bool get hasDraft => _draftText.trim().isNotEmpty;

  int get draftWordCount => _draftText
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .length;

  Offset _offset = Offset.zero;
  Offset get offset => _offset;
  set offset(Offset value) {
    _offset = value;
    notifyListeners();
    _positionPersistTimer?.cancel();
    _positionPersistTimer = Timer(const Duration(milliseconds: 80), () {
      unawaited(
        SharedPreferences.getInstance().then((prefs) async {
          await prefs.setDouble('notetaker.offsetX', _offset.dx);
          await prefs.setDouble('notetaker.offsetY', _offset.dy);
        }),
      );
    });
  }

  String _currentContext = 'General';
  String get currentContext => _currentContext;
  set currentContext(String value) {
    if (_currentContext == value) return;
    _currentContext = value;
    notifyListeners();
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setString('notetaker.context', value),
      ),
    );
  }

  Timer? _draftPersistTimer;
  Timer? _positionPersistTimer;

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('notetaker.enabled') ?? true;
    _draftText = prefs.getString('notetaker.draftText') ?? '';
    _currentContext = prefs.getString('notetaker.context') ?? 'General';
    // Positions saved by the previous implementation used the opposite
    // sign. Keep old installs safe by treating those values as the corner.
    final dx = prefs.getDouble('notetaker.offsetX') ?? 0;
    final dy = prefs.getDouble('notetaker.offsetY') ?? 0;
    _offset = Offset(dx, dy.clamp(0.0, double.infinity));
    notifyListeners();
  }

  void _persistDraftSoon() {
    _draftPersistTimer?.cancel();
    _draftPersistTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(
        SharedPreferences.getInstance().then(
          (prefs) => prefs.setString('notetaker.draftText', _draftText),
        ),
      );
    });
  }

  /// Manual Save — this is the only path that moves a cached draft into the
  /// permanent notes table.
  void commitDraft() {
    final trimmed = _draftText.trim();
    if (trimmed.isNotEmpty) {
      storage.saveNote(tag: _currentContext, text: trimmed);
    }
    _draftText = '';
    _draftPersistTimer?.cancel();
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.remove('notetaker.draftText'),
      ),
    );
    _isExpanded = false;
    notifyListeners();
  }

  /// Collapse without discarding — partial draft stays in memory.
  void collapse() {
    _isExpanded = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _draftPersistTimer?.cancel();
    _positionPersistTimer?.cancel();
    super.dispose();
  }
}

/// A draggable floating action button that expands to a note-taking card.
/// Mount this as an overlay inside a Stack on screens that need it.
class FloatingNotetakerOverlay extends StatefulWidget {
  const FloatingNotetakerOverlay({super.key, required this.state});

  final NotetakerState state;

  @override
  State<FloatingNotetakerOverlay> createState() =>
      _FloatingNotetakerOverlayState();
}

class _FloatingNotetakerOverlayState extends State<FloatingNotetakerOverlay> {
  static const double _bubbleSize = 56;
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  NotetakerState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    _textController.text = _state.draftText;
    _state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _state.removeListener(_onStateChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (_textController.text != _state.draftText) {
      _textController.text = _state.draftText;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_state.isEnabled) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = (constraints.maxWidth - 32).clamp(240.0, 340.0);
        final maxDx = -(constraints.maxWidth - _bubbleSize - 32).clamp(
          0.0,
          double.infinity,
        );
        final maxDy = (constraints.maxHeight - _bubbleSize - 32).clamp(
          0.0,
          double.infinity,
        );
        final clampedOffset = Offset(
          _state.offset.dx.clamp(maxDx, 0.0),
          _state.offset.dy.clamp(0.0, maxDy),
        );

        return Stack(
          children: [
            Positioned(
              right: 16 - clampedOffset.dx,
              bottom: 16 - clampedOffset.dy,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Expanded card
                  if (_state.isExpanded)
                    AnimatedOpacity(
                      duration: DesignTokens.durationFast,
                      opacity: _state.isExpanded ? 1 : 0,
                      child: _buildExpandedCard(panelWidth),
                    ),
                  if (_state.isExpanded) const SizedBox(height: 12),
                  // Bubble
                  _buildBubble(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBubble() {
    return GestureDetector(
      onTap: () {
        if (_state.isExpanded) {
          _state.collapse();
        } else {
          _state.isExpanded = true;
          _focusNode.requestFocus();
        }
      },
      onPanUpdate: (details) {
        _state.offset = Offset(
          _state.offset.dx + details.delta.dx,
          _state.offset.dy - details.delta.dy,
        );
      },
      onLongPress: () {
        _showContextMenu();
      },
      child: Container(
        width: _bubbleSize,
        height: _bubbleSize,
        decoration: BoxDecoration(
          color: DesignTokens.primary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: DesignTokens.surface.withValues(alpha: 0.9),
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: DesignTokens.ink.withValues(alpha: 0.14),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Icon(
                _state.isExpanded
                    ? CupertinoIcons.chevron_down
                    : CupertinoIcons.square_pencil,
                size: 22,
                color: Colors.white,
              ),
            ),
            if (!_state.isExpanded && _state.hasDraft)
              Positioned(
                right: -7,
                top: -7,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: DesignTokens.mastery,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: DesignTokens.surface, width: 2),
                  ),
                  child: Text(
                    _state.draftWordCount > 99
                        ? '99+'
                        : '${_state.draftWordCount}',
                    style: DesignTokens.body(
                      9,
                      weight: FontWeight.w800,
                    ).copyWith(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showContextMenu() async {
    final shouldHide = await showPSConfirmDialog(
      context,
      title: 'Hide notetaker?',
      message: 'You can turn it on again from Settings.',
      confirmLabel: 'Hide',
      destructive: true,
    );
    if (shouldHide) _state.isEnabled = false;
  }

  Widget _buildExpandedCard(double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLarge),
        border: Border.all(color: DesignTokens.hairline),
        boxShadow: [
          BoxShadow(
            color: DesignTokens.ink.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: DesignTokens.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  CupertinoIcons.square_pencil,
                  size: 17,
                  color: DesignTokens.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick notes',
                      style: DesignTokens.body(14, weight: FontWeight.w700),
                    ),
                    Text(
                      _state.currentContext,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.body(
                        11,
                      ).copyWith(color: DesignTokens.mutedDim),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Keep note for later',
                onPressed: () => _state.collapse(),
                icon: const Icon(CupertinoIcons.xmark, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _state.hasDraft
                ? '${_state.draftWordCount} words saved in this draft'
                : 'Keep a private draft across lessons. Save it when it is ready.',
            style: DesignTokens.body(
              11.5,
            ).copyWith(color: DesignTokens.mutedDim, height: 1.3),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 122,
            child: TextFormField(
              controller: _textController,
              focusNode: _focusNode,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: DesignTokens.body(13),
              decoration: InputDecoration(
                hintText: 'Type what you want to remember…',
                hintStyle: DesignTokens.body(
                  13,
                ).copyWith(color: DesignTokens.mutedDim),
                filled: true,
                fillColor: DesignTokens.canvas,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: DesignTokens.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: DesignTokens.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: DesignTokens.primary),
                ),
              ),
              onChanged: (value) {
                _state.draftText = value;
              },
            ),
          ),
          const SizedBox(height: 8),

          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _state.hasDraft ? _state.commitDraft : null,
              icon: const Icon(CupertinoIcons.checkmark, size: 17),
              label: const Text('Save note'),
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignTokens.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: DesignTokens.muted.withValues(
                  alpha: 0.18,
                ),
                disabledForegroundColor: DesignTokens.mutedDim,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    DesignTokens.radiusMedium,
                  ),
                ),
                textStyle: DesignTokens.body(13, weight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
