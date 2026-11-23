// Guest Registration form ke andar "ID Photos" (Front / Back).
//
//   final _idCtrl = GuestIdController();
//   GuestIdSection(
//     bookingId: 123,
//     phoneController: _phoneC,
//     readForm: () => GuestFormData(name: ..., phone: ..., idType: ..., idNumber: ...),
//     onPrefill: (p) { ... form ke KHAALI fields bhar do ... },
//     controller: _idCtrl,
//   )
//
// - Add-on OFF ho, ya terms accept nahi hue aur login owner ka nahi: kuch nahi dikhta.
// - Chhote Front / Back tile: ek tap = apna full-screen camera (card frame + Gallery button).
// - Koi popup nahi. Photo phone pe hi 78 KB ke andar banti hai aur PHONE me hi rukti hai.
// - S3 pe tabhi jaati hai jab form ka "Save" dabe (controller.saveAll()). Kitni bhi baar retake karo,
//   ✕ se form band karo: S3 pe kuch nahi jaata, koi kharcha nahi.
// - Aadhaar number tabhi chhupta hai jab "Hide Aadhaar no." ON ho (hotel ki marzi).
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'guestdocs_api.dart';
import 'id_camera.dart';
import 'id_parser.dart';
import 'id_scan_button.dart';
import 'image_gate.dart';

class GuestFormData {
  GuestFormData({required this.name, required this.phone, required this.idType, required this.idNumber});
  final String name, phone, idType, idNumber;
}

/// Purane guest ke record se form bharne ke liye. Sirf KHAALI fields bharna.
class GuestPrefill {
  GuestPrefill({this.name, this.idType, this.idNumber, this.address});
  final String? name, idType, idNumber, address;
}

/// Scan button se aayi photo ko ID section me daalne ke liye.
class GuestIdController {
  _GuestIdSectionState? _state;

  /// Add-on ON hai aur terms accept ho chuke hain
  bool get isActive => _state?._active == true;

  /// Koi photo li hui hai jo abhi save nahi hui
  bool get hasUnsaved => _state?._ready.isNotEmpty == true;

  /// Scan ki photo ko Front/Back me rakho (sirf phone me). Turant lautta hai, scan button atakta nahi.
  Future<void> attachScan(IdScanOutcome r) async {
    final s = _state;
    if (s == null || !s._active || !r.sameCard) return;
    final bytes = await r.file.readAsBytes();
    s._track(s._prepare(r.back ? 'id_back' : 'id_front', bytes, read: r.read, details: r.all));
  }

  /// Form ke Save pe: rakhi hui photos S3 pe bhejo. null = sab theek, warna error message.
  Future<String?> saveAll() async => _state?._saveAll();
}

const _accent = Color(0xFF6C5CE7);
const _muted = Color(0xFF94A3B8);
const _border = Color(0xFFE2E8F0);
const _ok = Color(0xFF059669);
const _okSoft = Color(0xFFECFDF5);
const _err = Color(0xFFDC2626);

class _Slot {
  String text = '';
  bool ok = false;
  bool staged = false; // photo li hai, Save pe jayegi
  bool busy = false;
  bool error = false;
  int? docId;
  Uint8List? preview;
}

class _Ready {
  _Ready(this.image, this.masked, this.idType, this.details);
  final PreparedImage image;
  final bool masked;
  final String idType;
  final IdDetails? details;
}

class GuestIdSection extends StatefulWidget {
  const GuestIdSection({
    super.key,
    required this.bookingId,
    required this.phoneController,
    required this.readForm,
    this.onPrefill,
    this.controller,
  });

  final int bookingId;
  final TextEditingController phoneController;
  final GuestFormData Function() readForm;
  final void Function(GuestPrefill data)? onPrefill;
  final GuestIdController? controller;

  @override
  State<GuestIdSection> createState() => _GuestIdSectionState();
}

class _GuestIdSectionState extends State<GuestIdSection> {
  final _api = GuestDocsApi.instance;
  final _slots = <String, _Slot>{'id_front': _Slot(), 'id_back': _Slot()};
  final _ready = <String, _Ready>{}; // li hui photos, Save ka intezaar (sirf phone me)
  final _jobs = <Future<void>>{}; // photo abhi tayyar ho rahi hai
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _found;
  int? _guestId;
  Future<int>? _guestFuture; // Front aur Back ek saath aayen to guest ek hi baar bane
  Timer? _debounce;
  String _lookedUp = '';
  bool _termsTicked = false;
  bool _termsBusy = false;
  bool _maskAadhaar = false; // "Hide Aadhaar no." (default OFF)

  bool get _enabled => _status?['enabled'] == true;
  bool get _termsOk => _status?['terms_accepted'] == true;
  bool get _active => _enabled && _termsOk;
  bool get _canView => _status?['can_view'] == true;
  bool get _canManage => _status?['can_manage'] == true;
  Map<String, dynamic> get _terms => Map<String, dynamic>.from((_status?['terms'] as Map?) ?? const {});

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    widget.phoneController.addListener(_onPhone);
    _loadStatus();
  }

  @override
  void didUpdateWidget(covariant GuestIdSection old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._state == this) old.controller?._state = null;
      widget.controller?._state = this;
    }
    if (old.phoneController != widget.phoneController) {
      old.phoneController.removeListener(_onPhone);
      widget.phoneController.addListener(_onPhone);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.phoneController.removeListener(_onPhone);
    if (widget.controller?._state == this) widget.controller?._state = null;
    super.dispose();
  }

  // ------------------------------------------------------------ data
  Future<void> _loadStatus() async {
    try {
      final s = await _api.status(widget.bookingId);
      if (!mounted) return;
      setState(() => _status = s);
      _onPhone();
    } catch (_) {
      if (mounted) setState(() => _status = null); // add-on OFF / network: section nahi dikhega
    }
  }

  String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');
  void _onPhone() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _lookup);
  }

  void _track(Future<void> job) {
    _jobs.add(job);
    job.whenComplete(() => _jobs.remove(job));
  }

  /// Save dabne pe: pehle chal rahi photo taiyari khatam, phir upload
  Future<String?> _saveAll() async {
    if (!_active) return null;
    if (_jobs.isNotEmpty) await Future.wait(List<Future<void>>.from(_jobs));
    String? firstError;
    for (final kind in const ['id_front', 'id_back']) {
      final r = _ready[kind];
      if (r == null) continue;
      final ok = await _upload(kind, r);
      if (ok) {
        _ready.remove(kind);
      } else {
        firstError ??= _slots[kind]!.text;
      }
    }
    return firstError;
  }

  Future<void> _lookup() async {
    final phone = _digits(widget.phoneController.text);
    if (!_enabled || phone.length < 10 || phone == _lookedUp) return;
    _lookedUp = phone;
    try {
      final j = await _api.lookup(widget.bookingId, phone);
      if (!mounted) return;
      if (j['found'] != true) {
        setState(() {
          _found = null;
          _guestId = null;
          _guestFuture = null;
        });
        return;
      }
      final g = Map<String, dynamic>.from(j['guest'] as Map);
      setState(() {
        _found = j;
        _guestId = g['id'] as int?;
        _guestFuture = null;
        for (final d in (g['documents'] as List)) {
          final doc = Map<String, dynamic>.from(d as Map);
          final slot = _slots[doc['kind']];
          if (slot != null && !slot.ok && !slot.busy && !slot.staged) {
            slot
              ..ok = true
              ..error = false
              ..docId = doc['id'] as int?
              ..text = 'Saved earlier ${_fmtDate(doc['uploaded_at'] as String?)}';
          }
        }
      });
      widget.onPrefill?.call(GuestPrefill(
        name: g['name'] as String?,
        idType: g['id_type'] as String?,
        idNumber: g['id_number'] as String?,
        address: g['address'] as String?,
      ));
    } catch (_) {
      _lookedUp = '';
    }
  }

  String _fmtDate(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]}';
  }

  Future<void> _acceptTerms() async {
    setState(() => _termsBusy = true);
    try {
      await _api.acceptTerms(widget.bookingId);
      if (!mounted) return;
      setState(() => _status = {...?_status, 'terms_accepted': true});
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _termsBusy = false);
    }
  }

  Future<int> _ensureGuest(IdDetails? d) {
    final existing = _guestFuture;
    if (existing != null) return existing;
    final f = _createGuest(d);
    _guestFuture = f;
    f.catchError((Object _) {
      _guestFuture = null; // fail hua to agli baar dobara try
      return 0;
    });
    return f;
  }

  Future<int> _createGuest(IdDetails? d) async {
    final f = widget.readForm();
    final body = <String, dynamic>{
      'is_primary': true,
      'phone': f.phone,
      'name': f.name,
      'id_type': f.idType,
      'id_number': f.idNumber,
    };
    if (_guestId != null) body['guest_id'] = _guestId;
    if (d != null) {
      bool empty(String k) => (body[k] ?? '').toString().trim().isEmpty;
      if (empty('name') && d.name != null) body['name'] = d.name;
      if (empty('id_type') && d.idType != null) body['id_type'] = d.idType;
      if (d.gender != null) body['gender'] = d.gender;
      if (d.dob != null) body['dob'] = d.dob;
      if (d.address != null) body['address'] = d.address;
      if (d.nationality != null) body['nationality'] = d.nationality;
    }
    body.removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));
    final g = await _api.upsertGuest(widget.bookingId, body);
    _guestId = g['id'] as int;
    return _guestId!;
  }

  // ------------------------------------------------------------ capture (ek tap = camera)
  Future<void> _capture(String kind) async {
    if (!_termsOk) {
      _toast('Accept the Guest ID terms above to save ID photos.');
      return;
    }
    final shot = await IdCamera.open(context, label: kind == 'id_back' ? 'Back side' : 'Front side');
    if (shot == null || !mounted) return;
    File? normalized;
    File? framed;
    try {
      _setBusy(kind, 'Preparing…');
      normalized = await ImageGate.normalize(shot.path);
      final cr = shot.crop;
      framed = cr == null ? normalized : await ImageGate.cropFraction(normalized, cr.left, cr.top, cr.right, cr.bottom);
      // Card sirf tab padho jab Aadhaar number chhupana ho (warna seedha, tez)
      IdReadResult? read;
      if (_maskAadhaar) read = await IdReader.read(framed, hintType: widget.readForm().idType);
      final bytes = await framed.readAsBytes();
      final job = _prepare(kind, bytes, read: read, details: read?.details);
      _track(job);
      await job;
    } catch (e) {
      _setError(kind, e);
    } finally {
      await ImageGate.deleteQuietly(framed?.path);
      await ImageGate.deleteQuietly(normalized?.path);
      await ImageGate.deleteQuietly(shot.path);
    }
  }

  /// bytes (normalized JPEG) -> (mask) -> 78 KB -> phone me rakho (S3 nahi). Retake = purani hat jaati hai.
  Future<void> _prepare(String kind, Uint8List bytes, {IdReadResult? read, IdDetails? details}) async {
    try {
      _setBusy(kind, 'Preparing…');
      final formType = widget.readForm().idType;
      final type = details?.idType ?? read?.details.idType ?? (formType.isEmpty ? 'other' : formType);
      var rects = const <List<int>>[];
      var masked = false;
      if (_maskAadhaar && type == 'aadhaar') {
        if (read == null || !read.scan.numberFound || read.scan.maskRects.isEmpty) {
          throw Exception("Couldn't find the Aadhaar number to hide. Retake, or turn off Hide Aadhaar no.");
        }
        rects = read.scan.maskRects;
        masked = true;
      }
      final img = await ImageGate.finalize(bytes, rects);
      _ready[kind] = _Ready(img, masked, type, details);
      if (!mounted) return;
      setState(() => _slots[kind]!
        ..busy = false
        ..error = false
        ..staged = true
        ..preview = img.bytes
        ..text = 'Ready · saves with form${masked ? ' · hidden' : ''}');
    } catch (e) {
      _setError(kind, e);
    }
  }

  Future<bool> _upload(String kind, _Ready r) async {
    final slot = _slots[kind]!;
    try {
      _setBusy(kind, 'Saving…', preview: r.image.bytes);
      final guestId = await _ensureGuest(r.details);
      final doc = await _api.uploadImage(
        bookingId: widget.bookingId,
        guestId: guestId,
        kind: kind,
        idType: r.idType,
        bytes: r.image.bytes,
        contentType: r.image.contentType,
        isMasked: r.masked,
      );
      if (mounted) {
        setState(() => slot
          ..busy = false
          ..ok = true
          ..staged = false
          ..error = false
          ..docId = doc['id'] as int?
          ..preview = r.image.bytes
          ..text = 'Saved ✓${r.masked ? ' · hidden' : ''}');
        unawaited(_refreshUsage());
      }
      return true;
    } catch (e) {
      if (e is GuestDocsException && e.status == 409 && e.message.toLowerCase().contains('terms')) {
        if (mounted) setState(() => _status = {...?_status, 'terms_accepted': false});
      }
      _setError(kind, e);
      return false;
    }
  }

  Future<void> _refreshUsage() async {
    try {
      final s = await _api.status(widget.bookingId);
      if (mounted) setState(() => _status = {...?_status, 'usage_mb': s['usage_mb'], 'limit_mb': s['limit_mb']});
    } catch (_) {}
  }

  void _setBusy(String kind, String text, {Uint8List? preview}) {
    if (!mounted) return;
    setState(() {
      final s = _slots[kind]!
        ..busy = true
        ..error = false
        ..text = text;
      if (preview != null) s.preview = preview;
    });
  }

  void _setError(String kind, Object e) {
    if (!mounted) return;
    setState(() => _slots[kind]!
      ..busy = false
      ..error = true
      ..text = '$e'.replaceFirst('Exception: ', ''));
  }

  Future<void> _view(int docId) async {
    try {
      final url = await _api.viewUrl(docId);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (c) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            title: const Text('Guest ID', style: TextStyle(fontSize: 16)),
          ),
          body: Center(
            child: InteractiveViewer(
              maxScale: 5,
              child: Image.network(
                url,
                loadingBuilder: (_, child, prog) =>
                prog == null ? child : const CircularProgressIndicator(color: Colors.white),
                errorBuilder: (_, __, ___) => const Text("Couldn't load the image. Please open it again.",
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ),
      ));
    } catch (e) {
      _toast('$e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg.replaceFirst('Exception: ', ''))));
  }

  // ------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    // Add-on OFF, ya terms abhi accept nahi hue aur ye login owner/partner ka nahi: kuch mat dikhao
    if (!_enabled || (!_termsOk && !_canManage)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Text('ID Photos', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _muted)),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _maskAadhaar = !_maskAadhaar),
            behavior: HitTestBehavior.opaque,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: _maskAadhaar,
                  activeColor: _accent,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) => setState(() => _maskAadhaar = v ?? false),
                ),
              ),
              const SizedBox(width: 6),
              const Text('Hide Aadhaar no.', style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
            ]),
          ),
        ]),
        const SizedBox(height: 6),
        if (_found != null) _banner(),
        if (!_termsOk) _termsBox(),
        Row(children: [
          Expanded(child: _slotTile('id_front', 'Front')),
          const SizedBox(width: 8),
          Expanded(child: _slotTile('id_back', 'Back')),
        ]),
      ]),
    );
  }

  Widget _banner() {
    final j = _found!;
    final g = Map<String, dynamic>.from(j['guest'] as Map);
    final hasId = j['has_id'] == true;
    final docs = (g['documents'] as List)
        .map((d) => Map<String, dynamic>.from(d as Map))
        .where((d) => d['kind'] == 'id_front' || d['kind'] == 'id_back')
        .length;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: hasId ? _okSoft : const Color(0xFFFFFBEB),
        border: Border.all(color: hasId ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(hasId ? Icons.verified_user_rounded : Icons.history_rounded,
            size: 16, color: hasId ? _ok : const Color(0xFFB45309)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            hasId
                ? 'ID already on file · ${g['stays_count']} stay(s) · $docs photo(s)'
                : 'Returning guest · no ID saved yet',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: hasId ? const Color(0xFF065F46) : const Color(0xFF92400E)),
          ),
        ),
      ]),
    );
  }

  Widget _termsBox() {
    final points = ((_terms['points'] as List?) ?? const []).map((e) => '$e').toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC), border: Border.all(color: _border), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_terms['title'] ?? 'Terms'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        for (var i = 0; i < points.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${i + 1}. ${points[i]}', style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
          ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _termsTicked,
          onChanged: (v) => setState(() => _termsTicked = v ?? false),
          title: Text('${_terms['accept_label'] ?? ''}', style: const TextStyle(fontSize: 12)),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _accent),
          onPressed: _termsTicked && !_termsBusy ? _acceptTerms : null,
          child: const Text('Accept & continue'),
        ),
      ]),
    );
  }

  /// Chhota tile: tap = camera (andar Gallery bhi), saved ho to chhoti photo pe tap = View.
  Widget _slotTile(String kind, String label) {
    final s = _slots[kind]!;
    final color = s.error ? _err : (s.staged ? _accent : (s.ok ? _ok : _muted));
    final status = s.busy || s.error || s.text.isNotEmpty ? s.text : 'Tap for camera';
    final staged = s.staged && !s.busy && !s.error;
    return Material(
      color: s.ok && !staged ? _okSoft : (staged ? const Color(0xFFF5F3FF) : Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: staged
                ? const Color(0xFFC4B5FD)
                : (s.ok ? const Color(0xFFA7F3D0) : (s.error ? const Color(0xFFFECACA) : _border))),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: s.busy ? null : () => _capture(kind),
        child: SizedBox(
          height: 48,
          child: Row(children: [
            GestureDetector(
              onTap: (s.ok && s.docId != null && _canView && !s.busy) ? () => _view(s.docId!) : null,
              child: Container(
                width: 48,
                height: 48,
                color: const Color(0xFFF1F5F9),
                alignment: Alignment.center,
                child: s.busy
                    ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _accent))
                    : (s.preview != null
                    ? Image.memory(s.preview!, fit: BoxFit.cover, width: 48, height: 48, gaplessPlayback: true)
                    : Icon(s.ok ? Icons.badge_outlined : Icons.photo_camera_outlined,
                    color: s.ok ? _ok : _accent, size: 20)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
                Text(status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: color)),
              ]),
            ),
            if (s.ok && s.docId != null && _canView && !s.busy)
              IconButton(
                tooltip: 'View',
                visualDensity: VisualDensity.compact,
                onPressed: () => _view(s.docId!),
                icon: const Icon(Icons.visibility_outlined, size: 18, color: _accent),
              ),
          ]),
        ),
      ),
    );
  }
}