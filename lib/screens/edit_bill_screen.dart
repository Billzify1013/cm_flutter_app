import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';

class EditBillScreen extends StatefulWidget {
  final Map<String, dynamic> booking;
  final List<dynamic> rooms;
  final List<dynamic> posItems;

  const EditBillScreen({
    super.key,
    required this.booking,
    required this.rooms,
    required this.posItems,
  });

  @override
  State<EditBillScreen> createState() => _EditBillScreenState();
}

class _EditBillScreenState extends State<EditBillScreen> {
  // Room: id → controller for TOTAL per night (including GST)
  late final Map<int, TextEditingController> _roomCtrl;
  late List<_PosRow> _posRows;
  bool _saving = false;

  int get _nights => (widget.booking['nights'] as num?)?.toInt() ?? 1;

  @override
  void initState() {
    super.initState();

    _roomCtrl = {};
    for (final r in widget.rooms) {
      final id      = r['id'] as int;
      final base    = (r['sell_rate'] as num?)?.toDouble() ?? 0;
      // sell_rate is base per night — show total per night (with GST)
      final gst     = base > 7500 ? 0.18 : 0.05;
      final total   = base * (1 + gst);
      _roomCtrl[id] = TextEditingController(
          text: total.toStringAsFixed(2));
    }

    _posRows = widget.posItems.map((p) => _PosRow.fromMap(p)).toList();
  }

  @override
  void dispose() {
    for (final c in _roomCtrl.values) c.dispose();
    for (final r in _posRows) r.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m),
      duration: const Duration(seconds: 2)));

  // Live grand total
  double get _calcTotal {
    double room = 0;
    for (final r in widget.rooms) {
      final id       = r['id'] as int;
      final totalNight = double.tryParse(_roomCtrl[id]?.text ?? '0') ?? 0;
      room += totalNight * _nights;
    }
    double pos = 0;
    for (final row in _posRows) {
      if (!row.deleted) {
        final q  = double.tryParse(row.qtyCtrl.text) ?? 0;
        final rt = double.tryParse(row.rateCtrl.text) ?? 0;
        pos += (q * rt) * (1 + row.gstRate / 100);
      }
    }
    return room + pos;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final uid = await ApiService.instance.getUserId();

      // Rooms: send total per night, Django will strip GST to get sell_rate
      final roomsPayload = widget.rooms.map((r) {
        final id         = r['id'] as int;
        final totalNight = double.tryParse(_roomCtrl[id]?.text ?? '0') ?? 0;
        return {
          'room_book_id': id,
          'total_per_night': totalNight, // Django will calculate base from this
        };
      }).toList();

      final posPayload = _posRows.map((row) => {
        'id':       row.id,
        'quantity': int.tryParse(row.qtyCtrl.text) ?? row.origQty,
        'rate':     double.tryParse(row.rateCtrl.text) ?? row.origRate,
        'note':     row.noteCtrl.text.trim(),
        'delete':   row.deleted,
      }).toList();

      final res = await ApiService.instance.postData(
        AppConfig.editBill,
        {
          'user_id':    uid,
          'booking_id': widget.booking['id']?.toString(),
          'rooms':      roomsPayload,
          'pos_items':  posPayload,
        },
      );

      if (!mounted) return;
      _snack(res.data['message'] ?? 'Bill updated');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      if (e is DioException) {
        _snack(e.response?.data?['error']?.toString() ?? friendlyError(e));
      } else {
        _snack(friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final adv = (widget.booking['advance_amount'] as num?)?.toDouble() ?? 0;
    final rem = _calcTotal - adv;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        title: const Text('Edit Bill',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary)),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Save',
                  style: TextStyle(fontWeight: FontWeight.w700,
                      fontSize: 15, color: AppColors.primary)),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── ROOMS ──────────────────────────────────────────
          _sec('Room Charges'),
          _card(Column(children: [
            // Header
            Row(children: [
              const Expanded(flex: 3,
                  child: Text('Room Type', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary))),
              const Expanded(flex: 2,
                  child: Text('Total/Night\n(incl. GST)', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary))),
              Expanded(flex: 2,
                  child: Text('$_nights Night Total',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary))),
            ]),
            const SizedBox(height: 6),
            const Divider(height: 1),
            ...widget.rooms.map((r) {
              final id = r['id'] as int;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  Expanded(flex: 3,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r['room_category']?.toString() ?? '-',
                                style: const TextStyle(fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            // Show base rate hint
                            ValueListenableBuilder(
                                valueListenable: _roomCtrl[id]!,
                                builder: (_, val, __) {
                                  final tot  = double.tryParse(val.text) ?? 0;
                                  final gst  = tot / (1 + (tot > 7500 * 1.05 ? 0.18 : 0.05));
                                  final base = tot - (tot - gst);
                                  // Simpler: base = tot / (1+gst%)
                                  final b2   = tot > 7500 * 1.18
                                      ? tot / 1.18 : tot / 1.05;
                                  return Text(
                                      'Base ₹${b2.toStringAsFixed(0)}/night',
                                      style: const TextStyle(fontSize: 10,
                                          color: AppColors.textSecondary));
                                }),
                          ])),
                  Expanded(flex: 2,
                      child: _editField(_roomCtrl[id]!, prefix: '₹',
                          onChanged: (_) => setState(() {}))),
                  Expanded(flex: 2,
                      child: ValueListenableBuilder(
                          valueListenable: _roomCtrl[id]!,
                          builder: (_, val, __) {
                            final tot = (double.tryParse(val.text) ?? 0) * _nights;
                            return Text('₹${tot.toStringAsFixed(0)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary));
                          })),
                ]),
              );
            }),
          ])),

          const SizedBox(height: 14),

          // ── POS ITEMS ──────────────────────────────────────
          if (_posRows.any((r) => !r.deleted)) ...[
            _sec('Product / Service Bills'),
            _card(Column(children: [
              Row(children: [
                const Expanded(flex: 3, child: Text('Item',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary))),
                const Expanded(flex: 1, child: Text('Qty',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary))),
                const Expanded(flex: 2, child: Text('Rate',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary))),
                const Expanded(flex: 2, child: Text('Total',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary))),
                const SizedBox(width: 32),
              ]),
              const SizedBox(height: 6),
              const Divider(height: 1),
              ..._posRows.asMap().entries.map((e) {
                final idx = e.key;
                final row = e.value;
                if (row.deleted) return const SizedBox.shrink();
                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3,
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(row.name, style: const TextStyle(fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                    Text('GST ${row.gstRate.toStringAsFixed(0)}%',
                                        style: const TextStyle(fontSize: 10,
                                            color: AppColors.textSecondary)),
                                  ])),
                          Expanded(flex: 1,
                              child: _editField(row.qtyCtrl, isInt: true,
                                  onChanged: (_) => setState(() {}))),
                          Expanded(flex: 2,
                              child: _editField(row.rateCtrl, prefix: '₹',
                                  onChanged: (_) => setState(() {}))),
                          Expanded(flex: 2,
                              child: Builder(builder: (_) {
                                final q  = double.tryParse(row.qtyCtrl.text) ?? 0;
                                final rt = double.tryParse(row.rateCtrl.text) ?? 0;
                                final tot = q * rt * (1 + row.gstRate / 100);
                                return Text('₹${tot.toStringAsFixed(0)}',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary));
                              })),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.delete_outline,
                                size: 18, color: Color(0xFFC0392B)),
                            onPressed: () => _confirmDelete(idx),
                          ),
                        ]),
                  ),
                  // Note field
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: row.noteCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Note (optional)',
                        hintStyle: const TextStyle(fontSize: 11,
                            color: AppColors.textSecondary),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: AppColors.border, width: 0.5)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: AppColors.border, width: 0.5)),
                      ),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  if (idx < _posRows.length - 1) const Divider(height: 1),
                ]);
              }),
            ])),
            const SizedBox(height: 14),
          ],

          // ── SUMMARY ────────────────────────────────────────
          _sec('Summary'),
          _card(Column(children: [
            _totRow('Grand Total', '₹${_calcTotal.toStringAsFixed(2)}',
                bold: true, large: true),
            const Divider(height: 12),
            _totRow('Advance Paid', '₹${adv.toStringAsFixed(2)}',
                color: const Color(0xFF16A34A)),
            _totRow(rem > 0 ? 'Balance Due' : 'Fully Paid',
                '₹${rem.abs().toStringAsFixed(2)}',
                bold: true,
                color: rem > 0
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF16A34A)),
          ])),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              child: _saving
                  ? const SizedBox(height: 18, width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : const Text('Save Bill',
                  style: TextStyle(fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _confirmDelete(int idx) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Remove "${_posRows[idx].name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC0392B)),
            onPressed: () {
              Navigator.pop(context);
              setState(() => _posRows[idx].deleted = true);
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _sec(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t, style: const TextStyle(fontSize: 13,
          fontWeight: FontWeight.w700, color: AppColors.textSecondary)));

  Widget _card(Widget child) => Container(
      width: double.infinity, padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(
            color: Color(0x06000000), blurRadius: 10, offset: Offset(0, 4))],
      ), child: child);

  Widget _editField(TextEditingController c,
      {String? prefix, bool isInt = false, ValueChanged<String>? onChanged}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextField(
          controller: c,
          keyboardType: isInt
              ? TextInputType.number
              : const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            isDense: true,
            prefixText: prefix,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 8),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                    color: AppColors.border, width: 0.8)),
          ),
          style: const TextStyle(fontSize: 12),
          onChanged: onChanged,
        ),
      );

  Widget _totRow(String l, String v,
      {bool bold = false, bool large = false, Color? color}) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l, style: TextStyle(
                    fontSize: bold ? 14 : 13,
                    color: AppColors.textSecondary,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
                Text(v, style: TextStyle(
                    fontSize: large ? 16 : bold ? 14 : 13,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                    color: color ?? AppColors.textPrimary)),
              ]));
}

class _PosRow {
  final int id;
  final String name;
  final double gstRate;
  final int origQty;
  final double origRate;
  bool deleted;
  final TextEditingController qtyCtrl;
  final TextEditingController rateCtrl;
  final TextEditingController noteCtrl;

  _PosRow({required this.id, required this.name, required this.gstRate,
    required this.origQty, required this.origRate, required this.deleted,
    required this.qtyCtrl, required this.rateCtrl, required this.noteCtrl});

  factory _PosRow.fromMap(Map p) => _PosRow(
    id:       p['id'] as int,
    name:     p['product_name']?.toString() ?? '-',
    gstRate:  (p['gst_rate'] as num?)?.toDouble() ?? 0,
    origQty:  (p['quantity'] as num?)?.toInt() ?? 1,
    origRate: (p['rate'] as num?)?.toDouble() ?? 0,
    deleted:  false,
    qtyCtrl:  TextEditingController(
        text: '${(p['quantity'] as num?)?.toInt() ?? 1}'),
    rateCtrl: TextEditingController(
        text: (p['rate'] as num?)?.toDouble().toStringAsFixed(2) ?? '0'),
    noteCtrl: TextEditingController(text: p['note']?.toString() ?? ''),
  );

  void dispose() {
    qtyCtrl.dispose(); rateCtrl.dispose(); noteCtrl.dispose();
  }
}