// Aadhaar photo ko PHONE pe hi padhna (Google ML Kit, free, internet ki zaroorat nahi):
//   1) 12 digit Aadhaar / 16 digit VID dhoondho -> pehle 8 (ya 12) digit pe kaala box
//   2) QR code:
//        - Purana QR (XML, poora number hota hai)  -> us par bhi kaala box + details nikalo
//        - Naya Secure QR (bada number)              -> naam, DOB, gender, address, last 4 nikalo
//
// Note: Secure QR ka UIDAI signature yahan verify nahi hota (wo OVSE registration ke baad
// Phase 2 me). Abhi QR sirf form bharne ke liye hai, staff details check karke Confirm karta hai.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class AadhaarQrData {
  AadhaarQrData({
    this.name,
    this.dob,
    this.yob,
    this.gender,
    this.careOf,
    this.house,
    this.street,
    this.landmark,
    this.location,
    this.vtc,
    this.postOffice,
    this.subDistrict,
    this.district,
    this.state,
    this.pincode,
    this.last4,
    this.uid,
    required this.isSecure,
  });

  final String? name, dob, yob, gender, careOf, house, street, landmark, location, vtc;
  final String? postOffice, subDistrict, district, state, pincode, last4;

  /// Poora Aadhaar number: sirf purane (XML) QR me hota hai. Naye Secure QR me sirf last 4.
  final String? uid;
  final bool isSecure;

  /// male / female / other (server ke choices)
  String? get genderCode {
    final g = (gender ?? '').trim().toUpperCase();
    if (g.startsWith('M')) return 'male';
    if (g.startsWith('F')) return 'female';
    if (g.startsWith('T') || g.startsWith('O')) return 'other';
    return null;
  }

  /// YYYY-MM-DD (server ke liye). DD-MM-YYYY ya DD/MM/YYYY se.
  String? get dobIso {
    final m = RegExp(r'^(\d{2})[-/](\d{2})[-/](\d{4})$').firstMatch((dob ?? '').trim());
    if (m == null) return null;
    return '${m.group(3)}-${m.group(2)}-${m.group(1)}';
  }

  String get address {
    final seen = <String>{};
    final parts = [careOf, house, street, landmark, location, vtc, postOffice, subDistrict, district, state]
        .where((p) => p != null && p.trim().isNotEmpty)
        .map((p) => p!.trim())
        .where((p) => seen.add(p.toLowerCase())) // "Indore, Indore" jaisa repeat hatao
        .toList();
    var a = parts.join(', ');
    if ((pincode ?? '').trim().isNotEmpty) a = '$a - ${pincode!.trim()}';
    return a;
  }

  String? get maskedNumber => last4 == null ? null : 'XXXX XXXX $last4';
}

class AadhaarScanResult {
  AadhaarScanResult({
    required this.maskRects,
    required this.numberFound,
    required this.oldQrFound,
    this.qr,
    this.last4,
    this.text = '',
  });

  /// Card ka poora OCR text (id_parser.dart isse PAN/DL/Voter/Passport ki details nikaalta hai)
  final String text;

  /// [x1, y1, x2, y2] normalized JPEG ke pixels me
  final List<List<int>> maskRects;
  final bool numberFound;
  final bool oldQrFound;
  final AadhaarQrData? qr;
  final String? last4;
}

class AadhaarScanner {
  static final _four = RegExp(r'^\d{4}$');

  /// [normalizedJpeg] wahi file honi chahiye jo ImageGate.normalize() ne di (rotation theek),
  /// taaki box ki jagah sahi bane.
  static Future<AadhaarScanResult> scan(File normalizedJpeg) async {
    final input = InputImage.fromFile(normalizedJpeg);
    final rects = <List<int>>[];
    var numberFound = false;
    String? last4;
    var fullText = '';

    // QR aur text ek saath padho (tez)
    final scanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
    final codesFuture = scanner.processImage(input).catchError((Object _) => <Barcode>[]);

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final text = await recognizer.processImage(input);
      fullText = text.text;
      for (final block in text.blocks) {
        for (final line in block.lines) {
          final els = line.elements;
          // "1234 5678 9012" -> 3 alag words. VID me 4.
          var i = 0;
          while (i < els.length) {
            var j = i;
            while (j < els.length && _four.hasMatch(els[j].text.trim())) {
              j++;
            }
            final run = j - i;
            if (run >= 3) {
              final hide = els.sublist(i, j - 1).map((e) => e.boundingBox).toList();
              rects.add(_pad(_union(hide)));
              numberFound = true;
              last4 = els[j - 1].text.trim();
              i = j;
            } else {
              i = math.max(i + 1, j);
            }
          }
          // Kabhi OCR poora number ek hi word me deta hai: "123456789012"
          for (final e in els) {
            final t = e.text.trim();
            final d = t.replaceAll(RegExp(r'\D'), '');
            if ((d.length == 12 || d.length == 16) && RegExp(r'^\d+$').hasMatch(t)) {
              final b = e.boundingBox;
              final hideW = b.width * (d.length - 4) / d.length;
              rects.add(_pad(Rect.fromLTRB(b.left, b.top, b.left + hideW, b.bottom)));
              numberFound = true;
              last4 = d.substring(d.length - 4);
            }
          }
        }
      }
    } catch (_) {
      await codesFuture;
      await scanner.close();
      rethrow;
    } finally {
      await recognizer.close();
    }

    AadhaarQrData? qr;
    var oldQr = false;
    try {
      final codes = await codesFuture;
      for (final c in codes) {
        final raw = c.rawValue ?? '';
        final Rect? box = c.boundingBox;
        if (raw.contains('PrintLetterBarcodeData') || raw.contains('uid=')) {
          oldQr = true;
          if (box != null) rects.add(_pad(box, 8));
          qr = AadhaarQr.parseXml(raw) ?? qr;
        } else if (RegExp(r'^\d{100,}$').hasMatch(raw.trim())) {
          qr = AadhaarQr.parseSecure(raw.trim()) ?? qr;
        }
      }
    } finally {
      await scanner.close();
    }

    return AadhaarScanResult(
      maskRects: rects,
      numberFound: numberFound,
      oldQrFound: oldQr,
      qr: qr,
      last4: last4 ?? qr?.last4,
      text: fullText,
    );
  }

  static Rect _union(List<Rect> rs) {
    var r = rs.first;
    for (final x in rs.skip(1)) {
      r = r.expandToInclude(x);
    }
    return r;
  }

  static List<int> _pad(Rect r, [double p = 4]) => [
    (r.left - p).floor(),
    (r.top - p).floor(),
    (r.right + p).ceil(),
    (r.bottom + p).ceil(),
  ];
}

class AadhaarQr {
  /// Naya Secure QR: bada decimal number -> bytes -> gzip -> 255 se alag fields
  static AadhaarQrData? parseSecure(String raw) {
    try {
      var n = BigInt.parse(raw);
      final b256 = BigInt.from(256);
      final rev = <int>[];
      while (n > BigInt.zero) {
        rev.add((n % b256).toInt());
        n = n ~/ b256;
      }
      final bytes = rev.reversed.toList();
      List<int> data;
      try {
        data = gzip.decode(bytes);
      } catch (_) {
        data = zlib.decode(bytes);
      }
      final parts = <List<int>>[];
      var cur = <int>[];
      for (final x in data) {
        if (x == 255) {
          parts.add(cur);
          cur = <int>[];
          if (parts.length >= 18) break; // iske baad photo ke bytes hain
        } else {
          cur.add(x);
        }
      }
      String s(int i) {
        if (i < 0 || i >= parts.length) return '';
        try {
          return utf8.decode(parts[i]).trim();
        } catch (_) {
          return latin1.decode(parts[i], allowInvalid: true).trim();
        }
      }

      final off = s(0).toUpperCase().startsWith('V') ? 1 : 0; // V2, V3... me pehle version aata hai
      final ref = s(off + 1);
      return AadhaarQrData(
        last4: ref.length >= 4 ? ref.substring(0, 4) : null,
        name: s(off + 2),
        dob: s(off + 3),
        gender: s(off + 4),
        careOf: s(off + 5),
        district: s(off + 6),
        landmark: s(off + 7),
        house: s(off + 8),
        location: s(off + 9),
        pincode: s(off + 10),
        postOffice: s(off + 11),
        state: s(off + 12),
        street: s(off + 13),
        subDistrict: s(off + 14),
        vtc: s(off + 15),
        isSecure: true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Purana QR: <PrintLetterBarcodeData uid="..." name="..." .../>
  static AadhaarQrData? parseXml(String raw) {
    String? a(String k) {
      final m = RegExp('\\b$k="([^"]*)"').firstMatch(raw);
      final v = m?.group(1)?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    final uid = (a('uid') ?? '').replaceAll(RegExp(r'\D'), '');
    if (uid.isEmpty && a('name') == null) return null;
    return AadhaarQrData(
      last4: uid.length >= 4 ? uid.substring(uid.length - 4) : null,
      uid: uid.length == 12 ? uid : null,
      name: a('name'),
      dob: a('dob'),
      yob: a('yob'),
      gender: a('gender'),
      careOf: a('co'),
      house: a('house'),
      street: a('street'),
      landmark: a('lm'),
      location: a('loc'),
      vtc: a('vtc'),
      postOffice: a('po'),
      subDistrict: a('subdist'),
      district: a('dist'),
      state: a('state'),
      pincode: a('pc'),
      isSecure: false,
    );
  }
}