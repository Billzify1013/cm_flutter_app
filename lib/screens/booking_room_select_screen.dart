import 'package:flutter/material.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';
import 'booking_detail_screen.dart';

// ─────────────────────────────────────────────
// GST helper
// ─────────────────────────────────────────────
Map<String, double> calcGst(double settle, int qty, int nights) {
  if (settle <= 0 || qty <= 0 || nights <= 0) return {'base': 0, 'gst': 0};
  final pnr = settle / (qty * nights);
  double base, gst;
  if (pnr <= 7500) {
    base = settle / 1.05; gst = settle - base;
  } else if (pnr <= 8850) {
    final p5 = 7500.0 * qty * nights;
    final p5gst = p5 * 0.05;
    final rem = settle - (p5 + p5gst);
    final b18 = rem / 1.18; final g18 = rem - b18;
    base = p5 + b18; gst = p5gst + g18;
  } else {
    base = settle / 1.18; gst = settle - base;
  }
  return {'base': base, 'gst': gst};
}

// ─────────────────────────────────────────────
// Callback — includes rooms payload
// ─────────────────────────────────────────────
typedef TotalsCallback = void Function(
    int catId,
    double settle,
    double base,
    double gst,
    int guests,
    List<Map<String, dynamic>> roomsData);

// ─────────────────────────────────────────────
// Non-occupancy card
// ─────────────────────────────────────────────
class _NonOccCard extends StatefulWidget {
  final int catId;
  final String catName;
  final int avail;
  final double sysPrice;
  final int nights;
  final String? planName;
  final TotalsCallback onChanged;
  const _NonOccCard({
    super.key,
    required this.catId,
    required this.catName,
    required this.avail,
    required this.sysPrice,
    required this.nights,
    required this.planName,
    required this.onChanged,
  });
  @override
  State<_NonOccCard> createState() => _NonOccCardState();
}

class _NonOccCardState extends State<_NonOccCard> {
  int qty = 0;
  double settle = 0, base = 0, gst = 0, lastSys = 0;
  bool edited = false;
  late final TextEditingController ctrl;

  @override
  void initState() {
    super.initState();
    ctrl = TextEditingController(text: '0.00');
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  String f(double v) => v.toStringAsFixed(2);

  void _push() {
    final payload = <Map<String, dynamic>>[];
    if (qty > 0 && settle > 0) {
      payload.add({
        'cat_id': widget.catId,
        'qty': qty,
        'settle_total': f(settle),
        'base': f(base),
        'gst': f(gst),
        'rate_plan': widget.planName ?? '',
      });
    }
    widget.onChanged(widget.catId, settle, base, gst, qty, payload);
  }

  void _recalc() {
    if (qty <= 0) {
      settle = 0; base = 0; gst = 0;
      _push(); return;
    }
    final sys = widget.sysPrice * qty * widget.nights;
    if (!edited) { settle = sys; lastSys = sys; ctrl.text = f(sys); }
    final g = calcGst(settle, qty, widget.nights);
    base = g['base']!; gst = g['gst']!;
    _push();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _deco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.catName,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            Text('Available: ${widget.avail}  •  ₹${f(widget.sysPrice)}/night',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ])),
          _qtyDrop(qty, widget.avail, (v) => setState(() {
            qty = v ?? 0; edited = false; _recalc();
          })),
        ]),
        if (qty > 0) ...[
          const SizedBox(height: 10),
          _settleField(ctrl, (val) {
            final sv = double.tryParse(val) ?? 0;
            settle = sv; edited = sv != lastSys;
            final g = calcGst(sv, qty, widget.nights);
            setState(() { base = g['base']!; gst = g['gst']!; });
            _push();
          }),
          const SizedBox(height: 8),
          Row(children: [
            _pill('Base ₹${f(base)}', AppColors.successSoft, AppColors.success),
            const SizedBox(width: 8),
            _pill('GST ₹${f(gst)}', AppColors.warningSoft, AppColors.warning),
          ]),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// Occupancy card
// ─────────────────────────────────────────────
class _OccCard extends StatefulWidget {
  final int catId;
  final String catName;
  final int avail;
  final double sysPrice;
  final int nights;
  final Map<String, List<Map<String, dynamic>>> plans;
  final TotalsCallback onChanged;
  const _OccCard({
    super.key,
    required this.catId,
    required this.catName,
    required this.avail,
    required this.sysPrice,
    required this.nights,
    required this.plans,
    required this.onChanged,
  });
  @override
  State<_OccCard> createState() => _OccCardState();
}

class _OccRoom {
  String? plan;
  int? persons;
  double settle = 0, pn = 0, base = 0, gst = 0, lastSys = 0;
  bool edited = false;
  late final TextEditingController ctrl;
  _OccRoom() { ctrl = TextEditingController(text: '0.00'); }
}

class _OccCardState extends State<_OccCard> {
  int qty = 0;
  final List<_OccRoom> rooms = [];

  @override
  void dispose() {
    for (final r in rooms) r.ctrl.dispose();
    super.dispose();
  }

  String f(double v) => v.toStringAsFixed(2);

  double _planPrice(String plan, int persons) {
    final tiers = widget.plans[plan];
    if (tiers == null || tiers.isEmpty) return 0;
    Map<String, dynamic>? exact, lower;
    for (final t in tiers) {
      final mp = (t['max_persons'] as num).toInt();
      if (mp == persons) { exact = t; break; }
      if (mp <= persons) lower = t;
    }
    if (exact != null) return (exact['base_price'] as num).toDouble();
    if (lower != null) {
      final ex = persons - (lower['max_persons'] as num).toInt();
      return (lower['base_price'] as num).toDouble() +
          (ex * ((lower['extra_per_person'] as num?)?.toDouble() ?? 0));
    }
    return (tiers.first['base_price'] as num).toDouble();
  }

  List<int> _persons(String plan) {
    final t = widget.plans[plan];
    if (t == null) return [1];
    return t.map((x) => (x['max_persons'] as num).toInt()).toList();
  }

  void _setQty(int q) {
    if (q > qty) {
      for (int i = qty; i < q; i++) rooms.add(_OccRoom());
    } else {
      for (int i = qty; i > q; i--) {
        rooms.last.ctrl.dispose();
        rooms.removeLast();
      }
    }
    qty = q;
  }

  void _recalcRoom(int idx) {
    final r = rooms[idx];
    if (r.plan == null || r.persons == null) {
      r.settle = 0; r.base = 0; r.gst = 0; r.pn = 0;
      _push(); return;
    }
    final pb = _planPrice(r.plan!, r.persons!);
    r.pn = widget.sysPrice + pb;
    final sys = r.pn * widget.nights;
    if (!r.edited) { r.settle = sys; r.lastSys = sys; r.ctrl.text = f(sys); }
    final g = calcGst(r.settle, 1, widget.nights);
    r.base = g['base']!; r.gst = g['gst']!;
    _push();
  }

  void _push() {
    double ts = 0, tb = 0, tg = 0; int tq = 0;
    final payload = <Map<String, dynamic>>[];
    for (final r in rooms) {
      ts += r.settle; tb += r.base; tg += r.gst;
      if (r.persons != null) tq += r.persons!;
      if (r.settle > 0) {
        payload.add({
          'cat_id': widget.catId,
          'rate_plan': r.plan ?? '',
          'guests': r.persons ?? 1,
          'settle_total': f(r.settle),
          'base': f(r.base),
          'gst': f(r.gst),
          'per_night': f(r.pn),
        });
      }
    }
    widget.onChanged(widget.catId, ts, tb, tg, tq, payload);
  }

  @override
  Widget build(BuildContext context) {
    final planNames = widget.plans.keys.toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _deco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.catName,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            Text('Available: ${widget.avail}  •  ₹${f(widget.sysPrice)}/night',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ])),
          _qtyDrop(qty, widget.avail, (v) => setState(() { _setQty(v ?? 0); })),
        ]),
        ...List.generate(qty, (i) {
          final r = rooms[i];
          final persons = r.plan != null ? _persons(r.plan!) : <int>[];
          return Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Room ${i + 1}', style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _miniDrop('Rate plan', r.plan, planNames,
                        (v) => setState(() {
                      r.plan = v; r.persons = null; r.edited = false; _recalcRoom(i);
                    }))),
                const SizedBox(width: 8),
                Expanded(child: _miniDrop(
                    'Guests',
                    r.persons?.toString(),
                    persons.map((p) => p.toString()).toList(),
                        (v) => setState(() {
                      r.persons = int.tryParse(v ?? ''); r.edited = false; _recalcRoom(i);
                    }))),
              ]),
              if (r.plan != null && r.persons != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  _pill('₹${f(r.pn)}/night', AppColors.accentSoft, AppColors.primary),
                ]),
                const SizedBox(height: 8),
                _settleField(r.ctrl, (val) {
                  final sv = double.tryParse(val) ?? 0;
                  r.settle = sv; r.edited = sv != r.lastSys;
                  final g = calcGst(sv, 1, widget.nights);
                  setState(() { r.base = g['base']!; r.gst = g['gst']!; });
                  _push();
                }),
                const SizedBox(height: 6),
                Row(children: [
                  _pill('Base ₹${f(r.base)}', AppColors.successSoft, AppColors.success),
                  const SizedBox(width: 8),
                  _pill('GST ₹${f(r.gst)}', AppColors.warningSoft, AppColors.warning),
                ]),
              ],
            ]),
          );
        }),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// Shared widget helpers (top-level)
// ─────────────────────────────────────────────
BoxDecoration _deco() => BoxDecoration(
  color: AppColors.card,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: AppColors.border),
  boxShadow: const [
    BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 4))
  ],
);

Widget _pill(String t, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(t, style: TextStyle(
        fontSize: 11, fontWeight: FontWeight.w600, color: fg)));

Widget _qtyDrop(int val, int max, ValueChanged<int?> cb) =>
    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      const Text('Qty', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: DropdownButtonHideUnderline(child: DropdownButton<int>(
          value: val,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          items: List.generate(
              max + 1, (i) => DropdownMenuItem(value: i, child: Text('$i'))),
          onChanged: cb,
        )),
      ),
    ]);

Widget _settleField(TextEditingController ctrl, ValueChanged<String> onChange) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Settle total ₹',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      const SizedBox(height: 4),
      TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(isDense: true),
        onChanged: onChange,
      ),
    ]);

Widget _miniDrop(
    String label, String? val, List<String> items, ValueChanged<String?> cb) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: DropdownButtonHideUnderline(child: DropdownButton<String>(
          value: val,
          isExpanded: true,
          hint: const Text('Select',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          icon: const Icon(Icons.keyboard_arrow_down,
              color: AppColors.textSecondary, size: 18),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: cb,
        )),
      ),
    ]);

// ─────────────────────────────────────────────
// Main screen
// ─────────────────────────────────────────────
class BookingRoomSelectScreen extends StatefulWidget {
  final Map<String, dynamic> bookingData;
  final DateTime checkin, checkout;
  const BookingRoomSelectScreen({
    super.key,
    required this.bookingData,
    required this.checkin,
    required this.checkout,
  });
  @override
  State<BookingRoomSelectScreen> createState() => _ScreenState();
}

class _ScreenState extends State<BookingRoomSelectScreen> {
  // Totals collected via callbacks
  final Map<int, List<double>> _totals = {};
  final Map<int, List<Map<String, dynamic>>> _roomsPayload = {};
  int _totalGuests = 0;
  final Map<int, int> _guestsByCat = {};

  // Guest fields
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _requestCtrl = TextEditingController();
  final _guestsCtrl = TextEditingController(text: '1');

  // Payment
  String _payMode = 'Cash';
  final _advCtrl = TextEditingController(text: '0');
  bool _saving = false;

  // Booking data
  late final bool _isOcc;
  late final bool _stopSell;
  late final int _nights;
  late final List<Map<String, dynamic>> _rooms;
  late final Map<String, Map<String, List<Map<String, dynamic>>>> _ratePlans;
  late final List<String> _planNames;
  String? _selectedPlan;

  static const _payModes = ['Cash', 'UPI', 'Card', 'Bank Transfer', 'Cheque'];
  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  @override
  void initState() {
    super.initState();
    final d = widget.bookingData;
    _isOcc = d['is_occupancy_based'] == true;
    _stopSell = d['stop_sell_warning'] == true;
    _nights = (d['nights'] as num?)?.toInt() ?? 1;
    _planNames = List<String>.from((d['plan_names'] as List?) ?? []);
    _rooms = List<Map<String, dynamic>>.from((d['rooms'] as List?) ?? []);

    _ratePlans = {};
    final rp = d['rate_plans'] as Map? ?? {};
    rp.forEach((catId, plans) {
      _ratePlans[catId.toString()] = {};
      (plans as Map).forEach((planName, tiers) {
        _ratePlans[catId.toString()]![planName.toString()] =
        List<Map<String, dynamic>>.from(
            (tiers as List).map((t) => Map<String, dynamic>.from(t as Map)));
      });
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _requestCtrl.dispose();
    _guestsCtrl.dispose();
    _advCtrl.dispose();
    super.dispose();
  }

  void _onRoomChanged(int catId, double settle, double base, double gst,
      int guests, List<Map<String, dynamic>> roomsData) {
    _totals[catId] = [settle, base, gst];
    _roomsPayload[catId] = roomsData;
    if (_isOcc) {
      _guestsByCat[catId] = guests;
      _totalGuests = _guestsByCat.values.fold(0, (a, b) => a + b);
    }
    setState(() {});
  }

  double get _grandTotal =>
      _totals.values.fold(0, (s, v) => s + v[0]);
  double get _totalBase =>
      _totals.values.fold(0, (s, v) => s + v[1]);
  double get _totalGst =>
      _totals.values.fold(0, (s, v) => s + v[2]);
  double get _advance => double.tryParse(_advCtrl.text) ?? 0;
  double get _remaining => _grandTotal - _advance;
  int get _roomCount =>
      _totals.values.where((v) => v[0] > 0).length;

  String _fmt(double v) => v.toStringAsFixed(2);

  String _apiDate(DateTime d) =>
      '${d.year}-'
          '${d.month.toString().padLeft(2,'0')}-'
          '${d.day.toString().padLeft(2,'0')}';

  String _prettyDate(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')} ${_months[d.month - 1]} ${d.year}';

  bool _isSplitSlab(double settle, int qty) {
    if (settle <= 0 || qty <= 0 || _nights <= 0) return false;
    final pnr = settle / (qty * _nights);
    return pnr > 7500 && pnr <= 8850;
  }

  Map<String, dynamic>? _buildExtraCharge(double settle, int qty) {
    if (settle <= 0 || qty <= 0 || _nights <= 0) return null;
    final pnr = settle / (qty * _nights);
    if (pnr <= 7500 || pnr > 8850) return null;
    return {
      'totalPricePerNight': pnr,
      'basePricePerNight': 7500.0,
      'extraPricePerNight': pnr - 7500.0,
    };
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty) { _msg('Enter guest name'); return; }
    if (phone.isEmpty) { _msg('Enter phone number'); return; }
    if (_grandTotal <= 0) { _msg('Select at least one room'); return; }

    setState(() => _saving = true);
    try {
      final uid = await ApiService.instance.getUserId();

      // Build rooms data + extra charges from payload
      final roomsData = <Map<String, dynamic>>[];
      final extraCharges = <String, dynamic>{};

      for (final entry in _roomsPayload.entries) {
        for (final room in entry.value) {
          roomsData.add(room);
          final settle = double.tryParse(
              room['settle_total']?.toString() ?? '0') ?? 0;
          final qty = int.tryParse(
              room['qty']?.toString() ?? '1') ?? 1;
          if (_isSplitSlab(settle, qty)) {
            final ec = _buildExtraCharge(settle, qty);
            if (ec != null) {
              final key = entry.key.toString();
              if (_isOcc) {
                if (!extraCharges.containsKey(key)) extraCharges[key] = [];
                (extraCharges[key] as List).add(ec);
              } else {
                extraCharges[key] = ec;
              }
            }
          }
        }
      }

      if (roomsData.isEmpty) { _msg('Select at least one room'); return; }

      final totalGuests = _isOcc
          ? _totalGuests
          : (int.tryParse(_guestsCtrl.text.trim()) ?? 1);

      final res = await ApiService.instance.postData(
        AppConfig.saveBooking,
        {
          'user_id': uid,
          'checkin': _apiDate(widget.checkin),
          'checkout': _apiDate(widget.checkout),
          'guest_name': name,
          'guest_contact': phone,
          'total_guests': totalGuests,
          'payment_mode': _payMode.toLowerCase(),
          'special_request': _requestCtrl.text.trim(),
          'advance_amount': _advCtrl.text.trim().isEmpty
              ? '0' : _advCtrl.text.trim(),
          'grand_total': _fmt(_grandTotal),
          'total_base': _fmt(_totalBase),
          'total_tax': _fmt(_totalGst),
          'remaining_amount': _fmt(_remaining),
          'is_occupancy_based': _isOcc,
          'rate_plan': _selectedPlan ?? '',
          'rooms_data': roomsData,
          'extra_charges': extraCharges,
        },
      );

      if (!mounted) return;
      final bookingId = res.data['booking_id'];
      // Booking detail ke liye full booking data build karo
      final bookingDetail = {
        'id': bookingId,
        'guest_name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'check_in_date': _apiDate(widget.checkin),
        'check_out_date': _apiDate(widget.checkout),
        'amount': _fmt(_grandTotal),
        'payment_status': _payMode,
        'channel_name': 'Walk-in',
        'special_requests': _requestCtrl.text.trim(),
        ...res.data,
      };
      // Dashboard tak pop karo phir detail screen push karo
      Navigator.of(context).popUntil((route) => route.isFirst);
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BookingDetailScreen(
            booking: Map<String, dynamic>.from(bookingDetail)),
      ));

    } catch (e) {
      if (!mounted) return;
      _msg(friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _msg(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create booking',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Date header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 15, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(
                '${_prettyDate(widget.checkin)}  →  ${_prettyDate(widget.checkout)}',
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w600, color: AppColors.primary),
              )),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('$_nights night${_nights > 1 ? 's' : ''}',
                    style: const TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ]),
          ),
          const SizedBox(height: 10),

          // Stop sell warning
          if (_stopSell)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD700)),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded,
                    color: Color(0xFF856404), size: 17),
                SizedBox(width: 8),
                Expanded(child: Text(
                  'Stop sell on some dates. Proceed at your own risk.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF856404)),
                )),
              ]),
            ),

          // Rate plan (non-occ)
          if (!_isOcc && _planNames.isNotEmpty) ...[
            _sec('Rate plan'),
            _dropCard('Rate plan', Icons.receipt_outlined,
                _selectedPlan, _planNames,
                    (v) => setState(() => _selectedPlan = v)),
            const SizedBox(height: 14),
          ],

          // Rooms
          _sec('Select rooms'),
          ..._rooms
              .where((r) => ((r['available'] as num?)?.toInt() ?? 0) > 0)
              .map((r) {
            final id = (r['id'] as num).toInt();
            return _isOcc
                ? _OccCard(
              key: ValueKey('occ_$id'),
              catId: id,
              catName: r['name'].toString(),
              avail: (r['available'] as num).toInt(),
              sysPrice: (r['price'] as num).toDouble(),
              nights: _nights,
              plans: _ratePlans[id.toString()] ?? {},
              onChanged: _onRoomChanged,
            )
                : _NonOccCard(
              key: ValueKey('noc_$id'),
              catId: id,
              catName: r['name'].toString(),
              avail: (r['available'] as num).toInt(),
              sysPrice: (r['price'] as num).toDouble(),
              nights: _nights,
              planName: _selectedPlan,
              onChanged: _onRoomChanged,
            );
          }),
          ..._rooms
              .where((r) => ((r['available'] as num?)?.toInt() ?? 0) == 0)
              .map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('• ${r['name']} — Sold out',
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFFC0392B))),
          )),
          const SizedBox(height: 14),

          // Payment
          _sec('Payment'),
          _cardWrap(Column(children: [
            // Total guests (non-occ manual, occ auto)
            if (!_isOcc) ...[
              _fieldWrap('Total guests', TextField(
                controller: _guestsCtrl,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.people_outline,
                      color: AppColors.textSecondary, size: 18),
                ),
              )),
              const SizedBox(height: 14),
            ],
            if (_isOcc && _totalGuests > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.people_outline,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text('Total guests: $_totalGuests',
                      style: const TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ]),
              ),
              const SizedBox(height: 14),
            ],
            _dropCard('Payment mode', Icons.payment_outlined,
                _payMode, _payModes,
                    (v) => setState(() => _payMode = v ?? 'Cash')),
            const SizedBox(height: 14),
            _fieldWrap('Advance amount ₹', TextField(
              controller: _advCtrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.currency_rupee,
                    color: AppColors.textSecondary, size: 18),
              ),
              onChanged: (_) => setState(() {}),
            )),
          ])),
          const SizedBox(height: 14),

          // Guest info
          _sec('Guest info'),
          _cardWrap(Column(children: [
            _textField(_nameCtrl, 'Guest name', 'Enter full name',
                Icons.person_outline, TextInputType.name),
            const SizedBox(height: 14),
            _textField(_phoneCtrl, 'Phone number', 'Enter phone number',
                Icons.phone_outlined, TextInputType.phone),
            const SizedBox(height: 14),
            _fieldWrap('Special request (optional)', TextField(
              controller: _requestCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Any special instructions...',
                isDense: true,
              ),
            )),
          ])),
          const SizedBox(height: 14),

          // Summary
          _sec('Summary'),
          _cardWrap(Column(children: [
            _srow('Rooms selected', '$_roomCount'),
            _srow('Nights', '$_nights'),
            const Divider(height: 14),
            _srow('Base amount', '₹${_fmt(_totalBase)}'),
            _srow('Total GST', '₹${_fmt(_totalGst)}'),
            const Divider(height: 14),
            _srow('Grand total (incl. GST)', '₹${_fmt(_grandTotal)}',
                bold: true),
            _srow('Advance paid', '₹${_fmt(_advance)}'),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Remaining',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              Text('₹${_fmt(_remaining)}',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _remaining < 0
                          ? const Color(0xFFC0392B)
                          : AppColors.textPrimary)),
            ]),
          ])),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                height: 22, width: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white))
                : const Text('Create booking'),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── UI helpers ──
  Widget _sec(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t, style: const TextStyle(fontSize: 13,
          fontWeight: FontWeight.w700, color: AppColors.textSecondary)));

  Widget _cardWrap(Widget child) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _deco(),
      child: child);

  Widget _srow(String l, String v, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l, style: TextStyle(fontSize: 13,
            color: AppColors.textSecondary,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
        Text(v, style: TextStyle(
            fontSize: bold ? 15 : 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: AppColors.textPrimary)),
      ]));

  Widget _textField(TextEditingController c, String label, String hint,
      IconData icon, TextInputType type) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(
            fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(controller: c, keyboardType: type,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(hintText: hint, isDense: true,
                prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 18))),
      ]);

  Widget _fieldWrap(String label, Widget field) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(
            fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        field,
      ]);

  Widget _dropCard(String label, IconData icon, String? val,
      List<String> items, ValueChanged<String?> cb) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(
            fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Icon(icon, color: AppColors.textSecondary, size: 18),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: val, isExpanded: true,
                hint: const Text('Select',
                    style: TextStyle(color: AppColors.textSecondary)),
                icon: const Icon(Icons.keyboard_arrow_down,
                    color: AppColors.textSecondary),
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14),
                items: items.map((e) =>
                    DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: cb,
              ),
            )),
          ]),
        ),
      ]);
}