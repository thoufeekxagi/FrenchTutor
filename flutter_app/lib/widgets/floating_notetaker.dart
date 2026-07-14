import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../data/database/storage_service.dart';

/// Shared state for the floating notetaker bubble.
/// Ported from iOS FloatingNotetaker — manages draft text, position, and expansion.
class NotetakerState extends ChangeNotifier {
  NotetakerState({required this.storage}) {
    _loadPrefs();
  }

  final StorageService storage;

  bool _isEnabled = true;
  bool get isEnabled => _isEnabled;
  set isEnabled(bool value) {
    _isEnabled = value;
    notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setBool('notetaker.enabled', value));
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
    _draftText = value;
    notifyListeners();
    _autosaveIfNeeded();
  }

  Offset _offset = Offset.zero;
  Offset get offset => _offset;
  set offset(Offset value) {
    _offset = value;
    notifyListeners();
    SharedPreferences.getInstance().then((p) {
      p.setDouble('notetaker.offsetX', value.dx);
      p.setDouble('notetaker.offsetY', value.dy);
    });
  }

  String _currentContext = 'General';
  String get currentContext => _currentContext;
  set currentContext(String value) {
    _currentContext = value;
    notifyListeners();
  }

  int _lastAutosavedWordCount = 0;

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('notetaker.enabled') ?? true;
    final dx = prefs.getDouble('notetaker.offsetX') ?? 0;
    final dy = prefs.getDouble('notetaker.offsetY') ?? 0;
    _offset = Offset(dx, dy);
    notifyListeners();
  }

  void _autosaveIfNeeded() {
    final wordCount =
        _draftText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (wordCount > 0 && wordCount - _lastAutosavedWordCount >= 5) {
      _lastAutosavedWordCount = wordCount;
      storage.saveNote(tag: _currentContext, text: _draftText);
    }
  }

  /// Manual Save — commits the draft and clears state.
  void commitDraft() {
    final trimmed = _draftText.trim();
    if (trimmed.isNotEmpty) {
      storage.saveNote(tag: _currentContext, text: trimmed);
    }
    _draftText = '';
    _lastAutosavedWordCount = 0;
    _isExpanded = false;
    notifyListeners();
  }

  /// Collapse without discarding — partial draft stays in memory.
  void collapse() {
    _isExpanded = false;
    notifyListeners();
  }
}

/// A draggable floating action button that expands to a note-taking card.
/// Mount this as an overlay inside a Stack on screens that need it.
class FloatingNotetakerOverlay extends StatefulWidget {
  const FloatingNotetakerOverlay({
    super.key,
    required this.state,
  });

  final NotetakerState state;

  @override
  State<FloatingNotetakerOverlay> createState() =>
      _FloatingNotetakerOverlayState();
}

class _FloatingNotetakerOverlayState extends State<FloatingNotetakerOverlay> {
  static const double _bubbleSize = 52;
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
        // Clamp offset so the bubble stays on screen
        final maxDx = -(constraints.maxWidth - _bubbleSize - 32);
        final topInset = _state.isExpanded ? 280.0 : 16.0;
        final maxDy = -(constraints.maxHeight - _bubbleSize - 16 - topInset);
        final clampedOffset = Offset(
          _state.offset.dx.clamp(maxDx, 0),
          _state.offset.dy.clamp(maxDy, 0),
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
                      duration: const Duration(milliseconds: 200),
                      opacity: _state.isExpanded ? 1 : 0,
                      child: _buildExpandedCard(),
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
          color: Passeport.maroon,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Passeport.ink.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(
          _state.isExpanded ? Icons.keyboard_arrow_down : Icons.edit,
          size: 20,
          color: Passeport.parchment,
        ),
      ),
    );
  }

  void _showContextMenu() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notetaker'),
        content: const Text('Hide the floating notetaker?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _state.isEnabled = false;
              Navigator.pop(ctx);
            },
            child: Text(
              'Hide',
              style: TextStyle(color: Passeport.maroon),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedCard() {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Passeport.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Passeport.hairline, width: 1),
        boxShadow: [
          BoxShadow(
            color: Passeport.ink.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Context label + close button
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Passeport.maroon.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _state.currentContext.toUpperCase(),
                  style: Passeport.mono(9.5, weight: FontWeight.w500)
                      .copyWith(color: Passeport.maroon),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _state.collapse(),
                child: Icon(Icons.close, size: 16, color: Passeport.slateDim),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Text field
          SizedBox(
            height: 90,
            child: TextFormField(
              controller: _textController,
              focusNode: _focusNode,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: Passeport.body(13),
              decoration: InputDecoration(
                hintText: "Type what you're hearing or reading…",
                hintStyle: Passeport.body(13).copyWith(color: Passeport.slate),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onChanged: (value) {
                _state.draftText = value;
              },
            ),
          ),
          const SizedBox(height: 8),

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _state.draftText.trim().isEmpty
                  ? null
                  : () => _state.commitDraft(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Passeport.maroon,
                foregroundColor: Passeport.parchment,
                disabledBackgroundColor: Passeport.maroon.withValues(alpha: 0.4),
                disabledForegroundColor: Passeport.parchment.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: Text(
                'Save note',
                style: Passeport.body(12.5, weight: FontWeight.w500)
                    .copyWith(color: Passeport.parchment),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
