// ID card ke liye apna full-screen camera (WhatsApp jaisa):
//   - beech me card ka frame, bahar ka hissa halka andhera
//   - neeche: left me Gallery, beech me bada shutter
//   - upar: ✕ (wapas), torch
//
//   final shot = await IdCamera.open(context, label: 'Front side');
//   if (shot != null) { shot.path ... shot.crop (frame wala hissa, 0..1) }
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class IdShot {
  IdShot(this.path, {this.crop});
  final String path;

  /// Camera se li photo me frame wala hissa (0..1 fractions, thoda margin ke saath). Gallery = null.
  final Rect? crop;
}

class IdCamera {
  static Future<IdShot?> open(BuildContext context, {String label = 'Front side'}) {
    return Navigator.of(context).push<IdShot>(MaterialPageRoute<IdShot>(
      fullscreenDialog: true,
      builder: (_) => _IdCameraPage(label: label),
    ));
  }
}

class _IdCameraPage extends StatefulWidget {
  const _IdCameraPage({required this.label});
  final String label;

  @override
  State<_IdCameraPage> createState() => _IdCameraPageState();
}

class _IdCameraPageState extends State<_IdCameraPage> with WidgetsBindingObserver {
  static const double _cardAspect = 1.586; // ID card ka naap
  // Sasta phone har resolution nahi chala pata: pehle 720p (sabse zyada phones pe chalta hai),
  // dikkat ho to apne aap neeche wala. Card padhne ke liye 720p kaafi hai.
  static const _presets = [ResolutionPreset.high, ResolutionPreset.medium, ResolutionPreset.low];
  int _preset = 0;

  final _picker = ImagePicker();
  CameraController? _cam;
  bool _starting = false;
  bool _busy = false;
  bool _torch = false;
  bool _picking = false;
  String? _error;
  Rect? _crop;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cam?.removeListener(_onCamValue);
    _cam?.dispose();
    _cam = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      final c = _cam;
      _cam = null;
      _torch = false;
      c?.removeListener(_onCamValue);
      c?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _cam == null && !_picking) {
      _start();
    }
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('NoCamera', 'No camera');
      final rear = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final c = CameraController(rear, _presets[_preset], enableAudio: false);
      c.addListener(_onCamValue);
      await c.initialize();
      try {
        await c.setFocusMode(FocusMode.auto);
      } catch (_) {}
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _cam = c;
        _error = null;
      });
    } on CameraException catch (e) {
      final code = e.code.toLowerCase();
      final denied = code.contains('denied') || code.contains('restricted');
      if (!denied && _preset < _presets.length - 1) {
        _preset++;
        _starting = false;
        return _start();
      }
      if (mounted) {
        setState(() => _error = denied
            ? 'Camera permission is off. Allow it in phone Settings, or pick from the gallery.'
            : "Couldn't start the camera. Pick from the gallery instead.");
      }
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't start the camera. Pick from the gallery instead.");
    } finally {
      _starting = false;
    }
  }

  /// Camera chalu hone ke baad error (jaise "Unsupported set of outputs"): chhota resolution try karo
  void _onCamValue() {
    final c = _cam;
    if (c == null || !c.value.hasError) return;
    c.removeListener(_onCamValue);
    _cam = null;
    c.dispose();
    if (_preset < _presets.length - 1) {
      _preset++;
      _start();
    } else if (mounted) {
      setState(() => _error = "Couldn't start the camera. Use the phone camera or the gallery.");
    }
  }

  /// Apna camera na chale to phone ka camera (fallback)
  Future<void> _phoneCamera() async {
    _picking = true;
    try {
      final x = await _picker.pickImage(
          source: ImageSource.camera, maxWidth: 2400, maxHeight: 2400, imageQuality: 90, requestFullMetadata: false);
      if (x != null && mounted) {
        Navigator.pop(context, IdShot(x.path));
        return;
      }
    } catch (_) {
    } finally {
      _picking = false;
    }
  }

  Future<void> _toggleTorch() async {
    final c = _cam;
    if (c == null) return;
    try {
      await c.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _torch = !_torch);
    } catch (_) {}
  }

  Future<void> _shoot() async {
    final c = _cam;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture || _busy) return;
    setState(() => _busy = true);
    try {
      final x = await c.takePicture();
      if (_torch) {
        try {
          await c.setFlashMode(FlashMode.off);
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.pop(context, IdShot(x.path, crop: _crop));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text("Couldn't take the photo. Please try again.")));
    }
  }

  Future<void> _gallery() async {
    if (_busy) return;
    _picking = true;
    try {
      final x = await _picker.pickImage(
          source: ImageSource.gallery, maxWidth: 2400, maxHeight: 2400, imageQuality: 90, requestFullMetadata: false);
      if (x != null && mounted) {
        Navigator.pop(context, IdShot(x.path));
        return;
      }
    } catch (_) {
    } finally {
      _picking = false;
    }
    if (mounted && _cam == null) _start();
  }

  Rect _frameOn(Size s) {
    final w = s.width * 0.88;
    return Rect.fromCenter(center: Offset(s.width / 2, s.height * 0.44), width: w, height: w / _cardAspect);
  }

  /// Screen pe frame -> photo me kaunsa hissa (preview "cover" me dikhta hai, isliye hisaab)
  Rect? _cropFor(Size screen, Size? previewSize, Rect frame) {
    if (previewSize == null) return null;
    final pw = math.min(previewSize.width, previewSize.height); // portrait
    final ph = math.max(previewSize.width, previewSize.height);
    final scale = math.max(screen.width / pw, screen.height / ph);
    final dw = pw * scale, dh = ph * scale;
    final ox = (screen.width - dw) / 2, oy = (screen.height - dh) / 2;
    double fx(double x) => ((x - ox) / dw).clamp(0.0, 1.0);
    double fy(double y) => ((y - oy) / dh).clamp(0.0, 1.0);
    final mx = frame.width * 0.08, my = frame.height * 0.30; // margin: card kabhi na kate
    return Rect.fromLTRB(fx(frame.left - mx), fy(frame.top - my), fx(frame.right + mx), fy(frame.bottom + my));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(builder: (context, box) {
        final size = box.biggest;
        final frame = _frameOn(size);
        final c = _cam;
        final ready = c != null && c.value.isInitialized;
        final ps = ready ? c!.value.previewSize : null;
        _crop = _cropFor(size, ps, frame);
        // fit: expand = Stack poori screen leta hai (warna camera sirf upar ki patti me dikhta tha)
        return Stack(fit: StackFit.expand, children: [
          if (ready && ps != null)
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: math.min(ps.width, ps.height),
                  height: math.max(ps.width, ps.height),
                  child: CameraPreview(c!),
                ),
              ),
            ),
          if (!ready && _error == null)
            const Center(
                child: SizedBox(
                    width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _FramePainter(frame)))),
          if (_error != null)
            Positioned(
              left: 24,
              right: 24,
              top: frame.top + 12,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _phoneCamera,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Use phone camera'),
                ),
              ]),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: frame.bottom + 14,
            child: const Text('Keep the card inside the frame',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          // Upar: ✕, label, torch
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
                  ),
                  Expanded(
                    child: Text(widget.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: 'Torch',
                    onPressed: ready ? _toggleTorch : null,
                    icon: Icon(_torch ? Icons.flash_on_rounded : Icons.flash_off_rounded, color: Colors.white),
                  ),
                ]),
              ),
            ),
          ),
          // Neeche: Gallery, shutter
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _roundIcon(Icons.photo_library_outlined, 'Gallery', _busy ? null : _gallery),
                  GestureDetector(
                    onTap: (ready && !_busy) ? _shoot : null,
                    child: Container(
                      width: 74,
                      height: 74,
                      padding: const EdgeInsets.all(5),
                      decoration:
                      BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                      child: Container(
                        decoration: BoxDecoration(shape: BoxShape.circle, color: ready ? Colors.white : Colors.white38),
                        child: _busy
                            ? const Padding(
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF6C5CE7)))
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 52),
                ]),
              ),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _roundIcon(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
    message: tip,
    child: Material(
      color: Colors.white24,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 52, height: 52, child: Icon(icon, color: Colors.white, size: 24)),
      ),
    ),
  );
}

/// Frame ke bahar halka andhera + safed kinara
class _FramePainter extends CustomPainter {
  _FramePainter(this.frame);
  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(frame, const Radius.circular(14));
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(rr),
    );
    canvas.drawPath(outside, Paint()..color = Colors.black.withOpacity(0.55));
    canvas.drawRRect(
        rr,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) => old.frame != frame;
}