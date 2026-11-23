// ID card ke text (ML Kit OCR) se guest details nikaalna. Pure Dart, koi plugin nahi.
// Web wale idscan.js ke parser jaisa hi logic hai (wahan same cases pe test hua hai).
//
// Aadhaar, PAN (naya + purana), Driving Licence, Voter ID, Passport (MRZ lines).
import 'aadhaar_scan.dart';

class IdDetails {
  IdDetails({
    this.idType,
    this.idNumber,
    this.idLast4,
    this.name,
    this.dob,
    this.yob,
    this.gender,
    this.address,
    this.pincode,
    this.city,
    this.nationality,
    this.source,
  });

  final String? idType; // aadhaar / pan / driving / voter / passport
  final String? idNumber; // Aadhaar: poore 12 digit (bina space), sirf tab jab card se pura number padha gaya
  final String? idLast4;
  final String? name;
  final String? dob; // YYYY-MM-DD
  final String? yob;
  final String? gender; // male / female / other
  final String? address;
  final String? pincode;
  final String? city;
  final String? nationality;
  final String? source; // qr / ocr

  /// Form me dikhane wala number. Aadhaar: poora "1234 5678 9012" (Mask button se chhupa sakte hain).
  /// Aadhaar ka poora number na mila ho to null (staff khud type kare).
  String? get displayNumber {
    if (idType == 'aadhaar') {
      final n = idNumber ?? '';
      return n.length == 12 ? spacedAadhaar(n) : null;
    }
    return idNumber;
  }

  /// Aadhaar: XXXX XXXX 1234
  String? get maskedNumber => idLast4 == null ? null : 'XXXX XXXX $idLast4';

  static String spacedAadhaar(String digits12) =>
      '${digits12.substring(0, 4)} ${digits12.substring(4, 8)} ${digits12.substring(8, 12)}';

  bool get isEmpty => name == null && idNumber == null && idLast4 == null && address == null;

  /// Same details, sirf ID number badla hua (null = hata do)
  IdDetails withIdNumber(String? n) => IdDetails(
    idType: idType,
    idNumber: n,
    idLast4: idLast4,
    name: name,
    dob: dob,
    yob: yob,
    gender: gender,
    address: address,
    pincode: pincode,
    city: city,
    nationality: nationality,
    source: source,
  );

  /// Pehle wale ki value bachti hai, khaali jagah doosre se bharti hai (front + back)
  IdDetails merge(IdDetails? o) {
    if (o == null) return this;
    return IdDetails(
      idType: idType ?? o.idType,
      idNumber: idNumber ?? o.idNumber,
      idLast4: idLast4 ?? o.idLast4,
      name: name ?? o.name,
      dob: dob ?? o.dob,
      yob: yob ?? o.yob,
      gender: gender ?? o.gender,
      address: address ?? o.address,
      pincode: pincode ?? o.pincode,
      city: city ?? o.city,
      nationality: nationality ?? o.nationality,
      source: source ?? o.source,
    );
  }
}

class _LabelValue {
  _LabelValue(this.value, this.index);
  final String value;
  final int index;
}

class IdParser {
  static const _states = [
    'andhra pradesh', 'arunachal pradesh', 'assam', 'bihar', 'chhattisgarh', 'goa', 'gujarat', 'haryana',
    'himachal pradesh', 'jharkhand', 'karnataka', 'kerala', 'madhya pradesh', 'maharashtra', 'manipur',
    'meghalaya', 'mizoram', 'nagaland', 'odisha', 'orissa', 'punjab', 'rajasthan', 'sikkim', 'tamil nadu',
    'telangana', 'tripura', 'uttar pradesh', 'uttarakhand', 'uttaranchal', 'west bengal', 'delhi',
    'nct of delhi', 'jammu and kashmir', 'jammu & kashmir', 'ladakh', 'puducherry', 'pondicherry',
    'chandigarh', 'andaman and nicobar islands', 'dadra and nagar haveli', 'daman and diu', 'lakshadweep',
  ];

  static final _notName = RegExp(
      r'(GOVERNMENT|GOVT|INDIA|INCOME|TAX|DEPARTMENT|PERMANENT|ACCOUNT|NUMBER|CARD|ELECTION|COMMISSION|IDENTITY|'
      r'DRIVING|LICEN[CS]E|UNION|AADHAAR|AADHAR|UNIQUE|AUTHORITY|DOB|BIRTH|MALE|FEMALE|ADDRESS|SIGNATURE|FATHER|'
      r'MOTHER|HUSBAND|ISSUE|VALID|REPUBLIC|PASSPORT|TRANSPORT|ELECTOR|DATE|BLOOD|GROUP|HOLDER|ENROL|VID|HELP|WWW)',
      caseSensitive: false);
  static final _relation = RegExp(
      r'(father|mother|husband|guardian|son|daughter|wife|\bs\s*/\s*o\b|\bd\s*/\s*o\b|\bw\s*/\s*o\b|\bc\s*/\s*o\b)',
      caseSensitive: false);
  static final _date = RegExp(r'(\d{2}[/\-.]\d{2}[/\-.]\d{4})');
  static final _addrStop = RegExp(
      r'(\b\d{4}\s?\d{4}\s?\d{4}\b|www\.|help@|uidai|\b1947\b|signature|date\s*of|validity|dl\s*no|issue|holder|'
      r'electoral|registration\s*officer|blood)',
      caseSensitive: false);

  static List<String> lines(String text) => text
      .split(RegExp(r'\r?\n'))
      .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((l) => l.isNotEmpty)
      .toList();

  static String titleCase(String s) =>
      s.toLowerCase().replaceAllMapped(RegExp(r'\b([a-z])'), (m) => m.group(1)!.toUpperCase());

  static String cleanName(String? s) {
    var n = (s ?? '').replaceAll(RegExp(r'[^A-Za-z .]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    n = n.replaceFirst(RegExp(r'^(name|nam|naam)\s*', caseSensitive: false), '').trim();
    if (n.length < 3 || n.length > 50 || _notName.hasMatch(n) || n.split(' ').length > 5) return '';
    if (!RegExp(r'[A-Za-z]{2,}').hasMatch(n)) return '';
    return titleCase(n);
  }

  static String? toIso(String? d) {
    final m = RegExp(r'^(\d{2})[/\-.](\d{2})[/\-.](\d{4})$').firstMatch((d ?? '').trim());
    if (m == null) return null;
    final dd = int.parse(m.group(1)!), mm = int.parse(m.group(2)!), yy = int.parse(m.group(3)!);
    if (dd < 1 || dd > 31 || mm < 1 || mm > 12 || yy < 1900 || yy > DateTime.now().year) return null;
    return '${m.group(3)}-${m.group(2)}-${m.group(1)}';
  }

  static String? _afterLabel(String line, RegExp label) {
    final m = label.firstMatch(line);
    if (m == null) return null;
    return line.substring(m.end).replaceFirst(RegExp(r'^[\s:;.\-/|]+'), '').trim();
  }

  static _LabelValue? _labelValue(List<String> ls, RegExp label, {RegExp? skip, bool Function(String)? accept}) {
    for (var i = 0; i < ls.length; i++) {
      if (!label.hasMatch(ls[i])) continue;
      if (skip != null && skip.hasMatch(ls[i])) continue;
      final v = _afterLabel(ls[i], label);
      if (v != null && v.isNotEmpty && (accept == null || accept(v))) return _LabelValue(v, i);
      if (i + 1 < ls.length && (accept == null || accept(ls[i + 1]))) return _LabelValue(ls[i + 1], i + 1);
    }
    return null;
  }

  static ({String? dob, String? yob, int index})? _findDob(List<String> ls, String text) {
    final lv = _labelValue(ls, RegExp(r'(date\s*of\s*birth|d\.?\s*o\.?\s*b\.?|\bdob\b|birth)', caseSensitive: false),
        accept: (v) => _date.hasMatch(v));
    if (lv != null) {
      final iso = toIso(_date.firstMatch(lv.value)!.group(1));
      if (iso != null) return (dob: iso, yob: null, index: lv.index);
    }
    final y = RegExp(r'year\s*of\s*birth\s*[:\-]?\s*(\d{4})', caseSensitive: false).firstMatch(text);
    if (y != null) return (dob: null, yob: y.group(1), index: -1);
    final dates = <({String iso, int index})>[];
    for (var i = 0; i < ls.length; i++) {
      final m = _date.firstMatch(ls[i]);
      final iso = m == null ? null : toIso(m.group(1));
      if (iso != null) dates.add((iso: iso, index: i));
    }
    if (dates.length == 1) return (dob: dates.first.iso, yob: null, index: dates.first.index);
    return null;
  }

  static String? _findGender(String text) {
    var m = RegExp(r'\b(female|male|transgender)\b', caseSensitive: false).firstMatch(text);
    if (m != null) {
      final g = m.group(1)!.toLowerCase();
      return g == 'female' ? 'female' : (g == 'male' ? 'male' : 'other');
    }
    m = RegExp(r'\b(?:sex|gender)\s*[:\-/]?\s*(m|f)\b', caseSensitive: false).firstMatch(text);
    if (m != null) return m.group(1)!.toUpperCase() == 'F' ? 'female' : 'male';
    return null;
  }

  static String? _findAddress(List<String> ls) {
    final label = RegExp(r'\b(address|addr|add)\b\s*[:\-]?', caseSensitive: false);
    for (var i = 0; i < ls.length; i++) {
      final m = label.firstMatch(ls[i]);
      if (m == null) continue;
      final parts = <String>[ls[i].substring(m.end).trim()];
      for (var j = i + 1; j < ls.length && j <= i + 5; j++) {
        if (_addrStop.hasMatch(ls[j])) break;
        parts.add(ls[j]);
      }
      var a = parts
          .join(', ')
          .replaceAll(RegExp(r'\s*,\s*,+'), ', ')
          .replaceAll(RegExp(r'^[,\s:]+|[,\s]+$'), '')
          .replaceAll(RegExp(r'\s+'), ' ');
      a = a.replaceFirst(_addrStop, '').trim();
      if (a.length >= 8) return a;
    }
    return null;
  }

  static String? cityFromAddress(String? addr) {
    if (addr == null) return null;
    final segs = addr
        .split(',')
        .map((s) => s.replaceAll(RegExp(r'\b\d{6}\b'), '').replaceFirst(RegExp(r'[-\s]+$'), '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
    for (var i = segs.length - 1; i >= 0; i--) {
      final low = segs[i].toLowerCase();
      for (final st in _states) {
        final pos = low.indexOf(st);
        if (pos < 0) continue;
        final before = segs[i].substring(0, pos).trim();
        if (before.length >= 3) return titleCase(before);
        if (i > 0) return titleCase(segs[i - 1].replaceFirst(RegExp(r'^(dist|district)\s*[:\-]?\s*', caseSensitive: false), ''));
      }
    }
    return null;
  }

  static String? _pincode(String? addr) => RegExp(r'\b(\d{6})\b').firstMatch(addr ?? '')?.group(1);

  static String? _mrzDate(String yymmdd, bool future) {
    if (!RegExp(r'^\d{6}$').hasMatch(yymmdd)) return null;
    final yy = int.parse(yymmdd.substring(0, 2));
    final cur = DateTime.now().year % 100;
    final century = future ? 2000 : (yy > cur ? 1900 : 2000);
    return '${century + yy}-${yymmdd.substring(2, 4)}-${yymmdd.substring(4, 6)}';
  }

  static IdDetails? parseMrz(List<String> ls) {
    final cand = ls
        .map((l) => l.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp('[«‹]'), '<').toUpperCase())
        .where((l) => l.length >= 30 && RegExp(r'^[A-Z0-9<]+$').hasMatch(l) && '<'.allMatches(l).length >= 2)
        .toList();
    for (var i = 0; i + 1 < cand.length; i++) {
      final l1 = cand[i], l2 = cand[i + 1];
      if (!l1.startsWith('P') || l2.length < 28) continue;
      final names = l1.substring(5).split('<<');
      final surname = names.isNotEmpty ? names[0].replaceAll('<', ' ').trim() : '';
      final given = names.length > 1 ? names[1].replaceAll('<', ' ').trim() : '';
      final num = l2.substring(0, 9).replaceAll('<', '');
      final nat = l2.substring(10, 13).replaceAll('<', '');
      final sex = l2[20];
      final name = titleCase('$given $surname'.trim());
      return IdDetails(
        idType: 'passport',
        idNumber: num.isEmpty ? null : num,
        name: name.isEmpty ? null : name,
        dob: _mrzDate(l2.substring(13, 19), false),
        gender: sex == 'F' ? 'female' : (sex == 'M' ? 'male' : null),
        nationality: nat == 'IND' ? 'Indian' : (nat.isEmpty ? null : nat),
        source: 'ocr',
      );
    }
    return null;
  }

  static String? detectType(String text, List<String> ls) {
    final up = text.toUpperCase();
    if (parseMrz(ls) != null) return 'passport';
    if (RegExp(r'INCOME\s*TAX|PERMANENT\s*ACCOUNT').hasMatch(up)) return 'pan';
    if (RegExp(r'ELECTION\s*COMMISSION|ELECTOR|EPIC').hasMatch(up)) return 'voter';
    if (RegExp(r'DRIVING\s*LICEN[CS]E|\bDL\s*NO|LICENCE\s*NO|TRANSPORT\s*DEPARTMENT').hasMatch(up)) return 'driving';
    if (RegExp(r'AADHAAR|AADHAR|UNIQUE\s*IDENTIFICATION|\b\d{4}\s\d{4}\s\d{4}\b').hasMatch(up)) return 'aadhaar';
    if (RegExp(r'PASSPORT|REPUBLIC\s*OF\s*INDIA').hasMatch(up)) return 'passport';
    if (RegExp(r'\b[A-Z]{5}\d{4}[A-Z]\b').hasMatch(up)) return 'pan';
    if (RegExp(r'\b[A-Z]{3}\d{7}\b').hasMatch(up)) return 'voter';
    return null;
  }

  static String? _findName(List<String> ls, String? type, int dobIndex) {
    final lv = _labelValue(ls, RegExp(r"\b(elector'?s\s*name|name)\b", caseSensitive: false),
        skip: _relation, accept: (v) => cleanName(v).isNotEmpty);
    if (lv != null) return cleanName(lv.value);
    if (type == 'pan') {
      for (final l in ls) {
        if (RegExp(r'[A-Z]{5}\d{4}[A-Z]').hasMatch(l)) break;
        final c = cleanName(l);
        if (c.isNotEmpty && l == l.toUpperCase()) return c;
      }
    }
    if (dobIndex > 0) {
      for (var i = dobIndex - 1; i >= 0 && i >= dobIndex - 3; i--) {
        final n = cleanName(ls[i]);
        if (n.isNotEmpty) return n;
      }
    }
    return null;
  }

  static ({String? full, String? last4})? _findNumber(String? type, String text, List<String> ls) {
    final up = text.toUpperCase();
    RegExpMatch? m;
    switch (type) {
      case 'aadhaar':
      // Ankon ke tukde (beech me ek space chalega). 12 digit = Aadhaar; 16 digit = VID (chhodo)
        for (final run in RegExp(r'\d(?:\d| (?=\d))+').allMatches(text)) {
          final dg = run.group(0)!.replaceAll(RegExp(r'\D'), '');
          if (dg.length == 12) return (full: dg, last4: dg.substring(8));
        }
        return null;
      case 'pan':
        m = RegExp(r'\b([A-Z]{5}\d{4}[A-Z])\b').firstMatch(up);
        return m == null ? null : (full: m.group(1), last4: null);
      case 'voter':
        m = RegExp(r'\b([A-Z]{3}\d{7})\b').firstMatch(up);
        return m == null ? null : (full: m.group(1), last4: null);
      case 'driving':
        m = RegExp(r'\b([A-Z]{2})[\s\-]?(\d{2})[\s\-]?(\d{4})[\s\-]?(\d{7})\b').firstMatch(up);
        if (m != null) return (full: '${m.group(1)}${m.group(2)}${m.group(3)}${m.group(4)}', last4: null);
        final lv = _labelValue(ls, RegExp(r'\b(dl\s*no|licen[cs]e\s*no)\b\.?', caseSensitive: false),
            accept: (v) => RegExp(r'[A-Z]{2}.*\d{5,}', caseSensitive: false).hasMatch(v));
        return lv == null ? null : (full: lv.value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), ''), last4: null);
      case 'passport':
        m = RegExp(r'\b([A-Z]\d{7})\b').firstMatch(up);
        return m == null ? null : (full: m.group(1), last4: null);
    }
    return null;
  }

  /// OCR text se details. [hintType]: staff ne form me jo ID type chuna (optional)
  static IdDetails parseText(String text, {String? hintType}) {
    final ls = lines(text);
    final all = ls.join('\n');
    final mrz = parseMrz(ls);
    if (mrz != null) return mrz;
    final type = detectType(all, ls) ?? ((hintType ?? '').isEmpty ? null : hintType);
    final num = _findNumber(type, all, ls);
    final dob = _findDob(ls, all);
    final address = _findAddress(ls);
    final name = _findName(ls, type, dob?.index ?? -1);
    return IdDetails(
      idType: type,
      idNumber: num?.full,
      idLast4: type == 'aadhaar' ? num?.last4 : null,
      name: name,
      dob: dob?.dob,
      yob: dob?.yob,
      gender: _findGender(all),
      address: address,
      pincode: _pincode(address),
      city: cityFromAddress(address),
      nationality: (type != null && type != 'passport') ? 'Indian' : null,
      source: 'ocr',
    );
  }

  /// Aadhaar QR (naya ya purana) ka data
  static IdDetails fromQr(AadhaarQrData q) {
    final name = (q.name ?? '').trim();
    final city = (q.district ?? q.vtc ?? '').trim();
    final yob = q.yob ?? (RegExp(r'^\d{4}$').hasMatch((q.dob ?? '').trim()) ? q.dob!.trim() : null);
    final uid = (q.uid ?? '').replaceAll(RegExp(r'\D'), '');
    return IdDetails(
      idType: 'aadhaar',
      idNumber: uid.length == 12 ? uid : null, // sirf purane QR me poora number hota hai
      idLast4: q.last4,
      name: name.isEmpty ? null : titleCase(name),
      dob: q.dobIso,
      yob: yob,
      gender: q.genderCode,
      address: q.address.isEmpty ? null : q.address,
      pincode: (q.pincode ?? '').trim().isEmpty ? null : q.pincode!.trim(),
      city: city.isEmpty ? null : titleCase(city),
      nationality: 'Indian',
      source: 'qr',
    );
  }
}