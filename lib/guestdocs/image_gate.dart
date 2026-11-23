// Image gate: koi bhi photo (iPhone HEIC, 48 MP, screenshot PNG, purani gallery photo)
// yahan se guzar ke 78 KB ya usse chhoti JPEG banti hai. Ye sab PHONE pe hota hai, server pe zero load.
//
//   1) normalize(): seedhi (rotation theek), EXIF/GPS hata ke, chhoti JPEG file
//   2) (Aadhaar ho to) aadhaar_scan.dart number dhoondh ke kaale box batata hai
//   3) finalize(): box lagao, lambi side 1280px, quality kam karo; phir bhi bada ho to
//      size 15% chhota karke dobara, jab tak 78 KB ke andar na aa jaye
//
// Server aur S3 dono 78 KB se badi file reject karte hain.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class GateConfig {
  static const int maxSide = 1280;
  static const int maxBytes = 78 * 1024;
  static const int minSide = 360;
}

class PreparedImage {
  PreparedImage(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;
  int get sizeKb => (bytes.lengthInBytes / 1024).round();
}

class _FracJob {
  _FracJob(this.bytes, this.l, this.t, this.r, this.b);
  final Uint8List bytes;
  final double l, t, r, b;
}

Uint8List? _cropFrac(_FracJob j) {
  final im = img.decodeJpg(j.bytes);
  if (im == null) return null;
  final x = (j.l * im.width).round().clamp(0, im.width - 1);
  final y = (j.t * im.height).round().clamp(0, im.height - 1);
  final w = ((j.r - j.l) * im.width).round().clamp(1, im.width - x);
  final h = ((j.b - j.t) * im.height).round().clamp(1, im.height - y);
  // Bahut chhota hissa bane to galti maan ke poori photo hi rakho
  if (w < im.width * 0.3 || h < im.height * 0.15) return null;
  if (w >= im.width && h >= im.height) return null;
  final c = img.copyCrop(im, x: x, y: y, width: w, height: h);
  return Uint8List.fromList(img.encodeJpg(c, quality: 92));
}

class _CropJob {
  _CropJob(this.bytes, this.aspect);
  final Uint8List bytes;
  final double aspect; // width / height
}

Uint8List? _crop(_CropJob job) {
  final im = img.decodeJpg(job.bytes);
  if (im == null || job.aspect <= 0) return null;
  final w = im.width, h = im.height;
  const margin = 1.15; // preview aur photo ka frame thoda alag ho sakta hai
  var cw = w;
  var ch = (w / job.aspect * margin).round();
  if (ch >= h) {
    ch = h;
    cw = math.min(w, (h * job.aspect * margin).round());
  }
  if (cw >= w && ch >= h) return null;
  final c = img.copyCrop(im, x: ((w - cw) / 2).round(), y: ((h - ch) / 2).round(), width: cw, height: ch);
  return Uint8List.fromList(img.encodeJpg(c, quality: 92));
}

/// compute() ke andar bhejne ke liye simple data (isolate me safe)
class _FinalizeJob {
  _FinalizeJob(this.bytes, this.rects);
  final Uint8List bytes;
  final List<List<int>> rects; // [x1, y1, x2, y2]
}


class ImageGate {
  /// Step 1: photo ko seedha karo, EXIF/GPS hatao, chhoti side ~1280px ki JPEG file.
  /// (OCR ke liye thodi badi rakhte hain; final size finalize() me aata hai.)
  static Future<File> normalize(String path) async {
    final out = await FlutterImageCompress.compressWithFile(
      path,
      minWidth: GateConfig.maxSide,
      minHeight: GateConfig.maxSide,
      quality: 92,
      format: CompressFormat.jpeg,
      keepExif: false,
      autoCorrectionAngle: true,
    );
    if (out == null || out.isEmpty) {
      throw Exception('Could not open this photo. Please take it again.');
    }
    return _tempFile(out, 'norm');
  }

  /// Step 3: kaale box lagao, 1280px, 78 KB ya usse kam tak compress.
  static Future<PreparedImage> finalize(Uint8List normalizedJpeg, List<List<int>> rects) {
    return compute(_finalize, _FinalizeJob(normalizedJpeg, rects));
  }


  /// Camera wali photo me se sirf wo hissa jo panel me dikh raha tha (card ke aas-paas), thoda margin ke saath.
  /// Kaatne ki zaroorat na ho to wahi file lautata hai.
  static Future<File> cropToAspect(File normalized, double aspect) async {
    final out = await compute(_crop, _CropJob(await normalized.readAsBytes(), aspect));
    if (out == null) return normalized;
    return _tempFile(out, 'crop');
  }

  /// Apne camera ki photo me se sirf frame wala hissa ([l,t,r,b] 0..1). Na kaatna ho to wahi file.
  static Future<File> cropFraction(File normalized, double l, double t, double r, double b) async {
    final out = await compute(_cropFrac, _FracJob(await normalized.readAsBytes(), l, t, r, b));
    if (out == null) return normalized;
    return _tempFile(out, 'frame');
  }

  static Future<File> _tempFile(List<int> bytes, String tag) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/gd_${tag}_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  static Future<void> deleteQuietly(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

PreparedImage _finalize(_FinalizeJob job) {
  var im = img.decodeJpg(job.bytes);
  if (im == null) {
    throw Exception('Could not open this photo. Please take it again.');
  }
  final black = img.ColorRgb8(0, 0, 0);
  int fit(int v, int maxV) => math.min(math.max(v, 0), maxV);
  for (final r in job.rects) {
    if (r.length != 4) continue;
    img.fillRect(im,
        x1: fit(r[0], im.width - 1),
        y1: fit(r[1], im.height - 1),
        x2: fit(r[2], im.width - 1),
        y2: fit(r[3], im.height - 1),
        color: black);
  }
  final longSide = math.max(im.width, im.height);
  if (longSide > GateConfig.maxSide) {
    im = im.width >= im.height
        ? img.copyResize(im, width: GateConfig.maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(im, height: GateConfig.maxSide, interpolation: img.Interpolation.average);
  }
  img.Image cur = im;
  const qualities = [70, 58, 48]; // kam encode = tez (78 KB tak 1280px pe aksar 58 pe hi aa jaata hai)
  while (true) {
    for (final q in qualities) {
      final b = Uint8List.fromList(img.encodeJpg(cur, quality: q));
      if (b.lengthInBytes <= GateConfig.maxBytes) {
        return PreparedImage(b, 'image/jpeg');
      }
    }
    final side = math.max(cur.width, cur.height);
    if (side <= GateConfig.minSide) {
      throw Exception('Could not make this photo small enough. Please take it again.');
    }
    final next = math.max(GateConfig.minSide, (side * 0.85).round());
    cur = cur.width >= cur.height
        ? img.copyResize(cur, width: next, interpolation: img.Interpolation.average)
        : img.copyResize(cur, height: next, interpolation: img.Interpolation.average);
  }
}