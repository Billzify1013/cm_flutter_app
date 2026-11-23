// "Scan ID" chhota icon (Guest Information wali line pe). SAB hotels ke liye, add-on ki zaroorat nahi:
// card phone pe hi padha jata hai (Google ML Kit), koi server call nahi.
//
//   IdScanButton(hintType: () => _idType, onResult: (r) async { ... form bharo ... })
//
// Tap = apna full-screen camera (card frame, andar Gallery button bhi).
// Address chahiye ho to neeche chhota message "Scan back side" (ek tap = phir camera).
import 'dart:io';

import 'package:flutter/material.dart';

import 'aadhaar_scan.dart';
import 'id_camera.dart';
import 'id_parser.dart';
import 'image_gate.dart';

class IdReadResult {
  IdReadResult(this.details, this.scan);
  final IdDetails details;
  final AadhaarScanResult scan; // Aadhaar photo ke mask boxes yahan hain
}

class IdReader {
  /// [normalized]: ImageGate.normalize() wali file. QR + OCR dono ek baar me.
  static Future<IdReadResult> read(File normalized, {String? hintType}) async {
    final scan = await AadhaarScanner.scan(normalized);
    final qr = scan.qr;
    final ocr = IdParser.parseText(scan.text, hintType: qr != null ? 'aadhaar' : hintType);
    if (qr == null) return IdReadResult(ocr, scan);

    // QR ka data sabse sahi. Poora number: purane QR se, warna card pe chhapa number (OCR)
    // tabhi lo jab uske last 4 QR se milte hon.
    final q = IdParser.fromQr(qr);
    var number = q.idNumber;
    final printed = (ocr.idNumber ?? '').replaceAll(RegExp(r'\D'), '');
    if (number == null && printed.length == 12 && (q.idLast4 == null || printed.endsWith(q.idLast4!))) {
      number = printed;
    }
    final d = q.withIdNumber(number).merge(ocr.withIdNumber(null));
    return IdReadResult(d, scan);
  }
}

/// Scan ka nateeja screen ko: form bharo; add-on ON ho to [file] ko ID photo me bhi save kar sakte ho.
/// [file] callback khatam hote hi delete ho jaati hai, isliye jo karna hai callback ke andar await karo.
class IdScanOutcome {
  IdScanOutcome({required this.all, required this.read, required this.file, required this.back, required this.sameCard});

  /// Front + back milake (front ki ID type/number/naam hi rehte hain)
  final IdDetails all;

  /// Sirf is photo ka read (mask boxes ke saath)
  final IdReadResult read;
  final File file;
  final bool back;

  /// Back side usi card ki hai (ya front). Doosra card (sirf address ke liye) ho to false.
  final bool sameCard;
}

const _noAddress = <String, List<String>>{
  'pan': ["PAN cards don't show an address.", 'Scan Aadhaar / DL'],
  'passport': ['The address is on the last page of the passport.', 'Scan last page'],
  'aadhaar': ['The address is on the back of the card.', 'Scan back side'],
  'voter': ['The address is on the back of the card.', 'Scan back side'],
  'driving': ["Couldn't read the address.", 'Scan again'],
};

class IdScanButton extends StatefulWidget {
  const IdScanButton({super.key, required this.onResult, this.hintType});

  final Future<void> Function(IdScanOutcome r) onResult;

  /// Staff ne form me jo ID type chuna hai (OCR ko madad milti hai)
  final String? Function()? hintType;

  @override
  State<IdScanButton> createState() => _IdScanButtonState();
}

class _IdScanButtonState extends State<IdScanButton> {
  bool _busy = false;
  bool _ok = false;
  IdDetails? _front;

  void _snack(String msg, {bool error = false, String? action, VoidCallback? onAction}) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? const Color(0xFFD63031) : const Color(0xFF1F2937),
      duration: Duration(seconds: action != null ? 8 : 4),
      action: action == null
          ? null
          : SnackBarAction(label: action, textColor: const Color(0xFFC4B5FD), onPressed: onAction!),
    ));
  }

  Future<void> _scan({required bool back}) async {
    final shot = await IdCamera.open(context, label: back ? 'Back side' : 'Front side');
    if (shot == null || !mounted) return;
    if (!back) _front = null;
    setState(() {
      _busy = true;
      _ok = false;
    });
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    File? normalized;
    File? framed;
    IdDetails? all;
    try {
      normalized = await ImageGate.normalize(shot.path);
      final cr = shot.crop;
      framed = cr == null ? normalized : await ImageGate.cropFraction(normalized, cr.left, cr.top, cr.right, cr.bottom);
      final r = await IdReader.read(framed, hintType: back ? null : widget.hintType?.call());
      final d = r.details;
      if (d.isEmpty) {
        throw Exception("Couldn't read this card. Take a straight, clear photo in good light.");
      }
      final front = _front;
      all = back && front != null ? front.merge(d) : d;
      final sameCard = !back || front == null || d.idType == null || d.idType == front.idType;
      if (!back) _front = d;
      await widget.onResult(IdScanOutcome(all: all, read: r, file: framed, back: back, sameCard: sameCard));
    } catch (e) {
      all = null;
      if (mounted) _snack('$e'.replaceFirst('Exception: ', ''), error: true);
    } finally {
      await ImageGate.deleteQuietly(framed?.path);
      await ImageGate.deleteQuietly(normalized?.path);
      await ImageGate.deleteQuietly(shot.path);
      if (mounted) setState(() => _busy = false);
    }
    final done = all;
    if (done == null || !mounted) return;
    setState(() => _ok = true);
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _ok = false);
    });
    final hint = _noAddress[done.idType];
    if (!back && done.address == null && hint != null) {
      _snack(hint[0], action: hint[1], onAction: () => _scan(back: true));
    } else if (done.idType == 'aadhaar' && done.displayNumber == null) {
      _snack("Couldn't read the full Aadhaar number. Please type it in.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _ok
        ? const [Color(0xFF10B981), Color(0xFF059669)]
        : const [Color(0xFF6366F1), Color(0xFF8B5CF6)];
    return Tooltip(
      message: 'Scan ID card',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _busy ? null : () => _scan(back: false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: colors.last.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            alignment: Alignment.center,
            child: _busy
                ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_ok ? Icons.check_rounded : Icons.document_scanner_outlined, size: 19, color: Colors.white),
          ),
        ),
      ),
    );
  }
}