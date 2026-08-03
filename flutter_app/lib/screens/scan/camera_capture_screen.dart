import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// Full-screen camera capture with pinch-to-zoom, used by Live Vision Scan.
/// Returns the captured JPEG bytes via `Navigator.pop`, or null if the user
/// backs out without taking a photo.
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  double _minZoom = 1;
  double _maxZoom = 1;
  double _zoom = 1;
  double _baseZoom = 1;
  String? _error;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera available on this device.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _minZoom = minZoom;
        _maxZoom = maxZoom;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              "Couldn't access the camera. Check camera permission in Settings.",
        );
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) Navigator.of(context).pop<Uint8List>(bytes);
    } catch (_) {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _setZoom(double zoom) async {
    final controller = _controller;
    if (controller == null) return;
    final clamped = zoom.clamp(_minZoom, _maxZoom).toDouble();
    if ((_zoom - clamped).abs() < 0.02) return;
    if (mounted) setState(() => _zoom = clamped);
    try {
      await controller.setZoomLevel(clamped);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null && controller.value.isInitialized)
              GestureDetector(
                onScaleStart: (_) => _baseZoom = _zoom,
                onScaleUpdate: (details) => _setZoom(_baseZoom * details.scale),
                child: Center(child: CameraPreview(controller)),
              )
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: DesignTokens.body(15).copyWith(color: Colors.white),
                  ),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: Semantics(
                button: true,
                label: 'Close camera',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Icon(CupertinoIcons.xmark, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            if (controller != null && _maxZoom > _minZoom)
              Positioned(
                top: 16,
                right: 16,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        '${_zoom.toStringAsFixed(1)}×',
                        style: DesignTokens.body(
                          13,
                          weight: FontWeight.w600,
                        ).copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: controller == null ? null : _capture,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.white38, width: 4),
                    ),
                    child: _capturing
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
