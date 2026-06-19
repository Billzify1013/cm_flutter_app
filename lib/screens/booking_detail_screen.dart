import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'pos_screen.dart';
import 'package:shimmer/shimmer.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';
import 'invoice_screen.dart';
import 'edit_bill_screen.dart';

class BookingDetailScreen extends StatefulWidget {
  final Map<String, dynamic> booking;
  const BookingDetailScreen({super.key, required this.booking});
  @override
  State<BookingDetailScreen> createState() => _S();
}

class _S extends State<BookingDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  bool _logsExpanded = false;

  static const _mo = ['Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final id = widget.booking['id']?.toString() ?? '';
      if (id.isEmpty || id == 'null')
        throw Exception('Invalid booking ID');
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(
        '${AppConfig.bookingDetail}$id/',
        {'user_id': uid},
      );
      if (!mounted) return;
      setState(() { _data = Map<String, dynamic>.from(res.data); _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Map get _b => (_data?['booking'] as Map?) ?? widget.booking;

  bool get _isInvoiceCreated => _data?['has_invoice'] == true;

  bool get _hasPhone {
    final p = _b['phone']?.toString() ?? '';
    final c = p.replaceAll(RegExp(r'[^0-9+]'), '');
    return c.isNotEmpty && c.replaceAll(RegExp(r'[0+]'), '').isNotEmpty;
  }

  Future<void> _call() async {
    final p = _b['phone']?.toString() ?? '';
    final c = p.replaceAll(RegExp(r'[^0-9+]'), '');
    try { await launchUrl(Uri(scheme: 'tel', path: c)); } catch (_) {}
  }

  String _pd(String? s) {
    if (s == null || s.isEmpty) return '-';
    try {
      final p = s.split('T')[0].split('-');
      return '${p[2].padLeft(2,'0')} ${_mo[int.parse(p[1])-1]} ${p[0]}';
    } catch (_) { return s; }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(
    content: Text(m),
    duration: const Duration(seconds: 1),
  ));

  // ── Bottom sheet opener ──
  void _sheet(Widget child, {double? height}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 12),
              // Drag handle
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
              // Close
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(20)),
                      child: const Icon(Icons.close, size: 16,
                          color: AppColors.textSecondary)),
                  onPressed: () => Navigator.pop(sheetCtx),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(sheetCtx).size.height * 0.7),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: child,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Action handlers ──


  void _editPaymentSheet(Map<String, dynamic> p) {
    final amtCtrl = TextEditingController(
        text: (p['amount'] as num?)?.toStringAsFixed(2) ?? '');
    final txCtrl = TextEditingController(
        text: p['transaction_id']?.toString() ?? '');
    final commentCtrl = TextEditingController(
        text: p['description']?.toString() ?? '');
    final modes = ['Cash', 'UPI', 'Card', 'Bank Transfer', 'Cheque'];
    String mode = p['mode']?.toString() ?? 'Cash';
    if (!modes.contains(mode)) mode = 'Cash';

    _sheet(StatefulBuilder(builder: (ctx, set) => Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      _shTitle('Edit payment'),
      _shField(amtCtrl, 'Amount ₹', TextInputType.number),
      const SizedBox(height: 12),
      _shDropdown('Payment mode', mode, modes,
              (v) => set(() => mode = v ?? 'Cash')),
      const SizedBox(height: 12),
      _shField(txCtrl, 'Reference / UTR', TextInputType.text),
      const SizedBox(height: 12),
      _shField(commentCtrl, 'Comment', TextInputType.text),
      const SizedBox(height: 20),
      _shBtn('Update payment', () async {
        final amt = amtCtrl.text.trim();
        if (amt.isEmpty) { _snack('Enter amount'); return; }
        Navigator.pop(ctx);
        try {
          final uid = await ApiService.instance.getUserId();
          final res = await ApiService.instance.postData(
            AppConfig.editPayment,
            {
              'user_id': uid,
              'payment_id': p['id']?.toString(),
              'amount': amt,
              'payment_mode': mode,
              'transaction_id': txCtrl.text.trim(),
              'comment': commentCtrl.text.trim(),
            },
          );
          _snack(res.data['message'] ?? 'Payment updated');
          _load();
        } catch (e) {
          if (e is DioException) {
            final msg = e.response?.data?['error']
                ?? e.response?.data?['message']
                ?? friendlyError(e);
            _snack(msg.toString());
          } else {
            _snack(friendlyError(e));
          }
        }
      }),
    ])));
  }

  void _addPayment() {
    final rem = (_b['remaining_amount'] as num?)?.toDouble() ?? 0;
    final amtCtrl = TextEditingController(
        text: rem > 0 ? rem.toStringAsFixed(2) : '');
    String mode = 'Cash';
    final txCtrl = TextEditingController();
    _sheet(StatefulBuilder(builder: (ctx, set) => Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      _shTitle('Add payment'),
      _shField(amtCtrl, 'Amount ₹', TextInputType.number),
      const SizedBox(height: 12),
      _shDropdown('Payment mode', mode,
          ['Cash','UPI','Card','Bank Transfer','Cheque'],
              (v) => set(() => mode = v ?? 'Cash')),
      const SizedBox(height: 12),
      _shField(txCtrl, 'Reference / UTR (optional)', TextInputType.text),
      const SizedBox(height: 20),
      _shBtn('Save payment', () async {
        final amt = amtCtrl.text.trim();
        if (amt.isEmpty) { _snack('Enter amount'); return; }
        Navigator.pop(context);
        try {
          final uid = await ApiService.instance.getUserId();
          final res = await ApiService.instance.postData(
            AppConfig.addPayment,
            {
              'user_id': uid,
              'booking_id': _b['id']?.toString(),
              'amount': amt,
              'payment_mode': mode,
              'transaction_id': txCtrl.text.trim(),
            },
          );
          _snack(res.data['message'] ?? 'Payment added');
          final d = res.data;
          setState(() {
            (_data?['payments'] as List?)?.insert(0, {
              'id': d['payment_id'] ?? 0,
              'amount': double.tryParse(amt) ?? 0,
              'date': 'Just now',
              'mode': mode,
              'transaction_id': txCtrl.text.trim(),
              'description': '',
            });
            _data?['booking']?['advance_amount'] = d['new_advance'] ?? 0;
            _data?['booking']?['remaining_amount'] = d['new_remaining'] ?? 0;
            _data?['booking']?['payment_type'] = d['payment_type'] ?? '';
          });
        } catch (e) { _snack(friendlyError(e)); }
      }),
    ])));
  }

  void _editGuest() {
    final nameCtrl = TextEditingController(text: _b['guest_name']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: _b['phone']?.toString() ?? '');
    final reqCtrl = TextEditingController(text: _b['special_request']?.toString() ?? '');
    _sheet(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _shTitle('Edit guest details'),
      _shField(nameCtrl, 'Guest name', TextInputType.name),
      const SizedBox(height: 12),
      _shField(phoneCtrl, 'Phone', TextInputType.phone),
      const SizedBox(height: 12),
      _shField(reqCtrl, 'Special request', TextInputType.text),
      const SizedBox(height: 20),
      _shBtn('Save changes', () async {
        final name = nameCtrl.text.trim();
        if (name.isEmpty) { _snack('Enter guest name'); return; }
        Navigator.pop(context);
        try {
          final uid = await ApiService.instance.getUserId();
          final res = await ApiService.instance.postData(AppConfig.editGuest, {
            'user_id': uid,
            'booking_id': _b['id']?.toString(),
            'guest_name': name,
            'phone': phoneCtrl.text.trim(),
            'special_request': reqCtrl.text.trim(),
          });
          _snack(res.data['message'] ?? 'Updated');
          setState(() {
            _data?['booking']?['guest_name'] = name;
            _data?['booking']?['phone'] = phoneCtrl.text.trim();
            _data?['booking']?['special_request'] = reqCtrl.text.trim();
          });
        } catch (e) {
          if (e is DioException) {
            _snack(e.response?.data?['error']?.toString() ?? friendlyError(e));
          } else { _snack(friendlyError(e)); }
        }
      }),
    ]));
  }

  void _editDates() {
    DateTime? ci, co;
    try { ci = DateTime.parse(_b['checkin_date']?.toString() ?? ''); } catch (_) {}
    try { co = DateTime.parse(_b['checkout_date']?.toString() ?? ''); } catch (_) {}
    _sheet(StatefulBuilder(builder: (ctx, set) => Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      _shTitle('Edit dates'),
      Row(children: [
        Expanded(child: _dateTile('Check-in', ci, () async {
          final p = await showDatePicker(context: ctx,
              initialDate: ci ?? DateTime.now(),
              firstDate: DateTime(2020), lastDate: DateTime(2030));
          if (p != null) set(() => ci = p);
        })),
        const SizedBox(width: 10),
        Expanded(child: _dateTile('Check-out', co, () async {
          final p = await showDatePicker(context: ctx,
              initialDate: co ?? DateTime.now(),
              firstDate: DateTime(2020), lastDate: DateTime(2030));
          if (p != null) set(() => co = p);
        })),
      ]),
      if (ci != null && co != null && co!.isAfter(ci!)) ...[
        const SizedBox(height: 8),
        Center(child: _badge(
            '${co!.difference(ci!).inDays} night(s)',
            AppColors.accentSoft, AppColors.primary)),
      ],
      const SizedBox(height: 20),
      _shBtn('Update dates', () async {
        if (ci == null || co == null) { _snack('Select both dates'); return; }
        if (!co!.isAfter(ci!)) { _snack('Checkout must be after checkin'); return; }
        Navigator.pop(context);
        try {
          final uid = await ApiService.instance.getUserId();
          final res = await ApiService.instance.postData(AppConfig.editDates, {
            'user_id': uid,
            'booking_id': _b['id']?.toString(),
            'checkin_date': '${ci!.year}-${ci!.month.toString().padLeft(2,'0')}-${ci!.day.toString().padLeft(2,'0')}',
            'checkout_date': '${co!.year}-${co!.month.toString().padLeft(2,'0')}-${co!.day.toString().padLeft(2,'0')}',
          });
          final data = res.data;
          if (data['status'] == 'success') {
            _snack(data['message'] ?? 'Dates updated');
            _load();
          } else if (data['sold_out_dates'] != null) {
            final dates = (data['sold_out_dates'] as List).join('\n');
            _snack('Sold out:\n$dates');
          } else {
            _snack(data['message'] ?? 'Failed');
          }
        } catch (e) {
          if (e is DioException) {
            final d = e.response?.data;
            if (d?['sold_out_dates'] != null) {
              final dates = (d['sold_out_dates'] as List).join('\n');
              _snack('Sold out:\n$dates');
            } else {
              _snack(d?['error']?.toString() ?? d?['message']?.toString() ?? friendlyError(e));
            }
          } else { _snack(friendlyError(e)); }
        }
      }),
    ])));
  }



  void _editCommission() {
    final rooms = (_data?['rooms'] as List?) ?? [];
    final comm = (_data?['commission'] as Map?) ?? {};
    final commCtrl = TextEditingController(
        text: (comm['commission'] as num?)?.toStringAsFixed(2) ?? '0');
    final tdsCtrl = TextEditingController(
        text: (comm['tds'] as num?)?.toStringAsFixed(2) ?? '0');
    final tcsCtrl = TextEditingController(
        text: (comm['tcs'] as num?)?.toStringAsFixed(2) ?? '0');
    _sheet(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _shTitle('Commission & TDS/TCS'),
      Row(children: [
        Expanded(child: _shField(commCtrl, 'Commission ₹', TextInputType.number)),
        const SizedBox(width: 10),
        Expanded(child: _shField(tdsCtrl, 'TDS ₹', TextInputType.number)),
        const SizedBox(width: 10),
        Expanded(child: _shField(tcsCtrl, 'TCS ₹', TextInputType.number)),
      ]),
      const SizedBox(height: 20),
      const SizedBox(height: 20),
      _shBtn('Save', () async {
        Navigator.pop(context);
        try {
          final uid = await ApiService.instance.getUserId();
          final res = await ApiService.instance.postData(
              AppConfig.editCommission, {
            'user_id': uid,
            'booking_id': _b['id']?.toString(),
            'commission': commCtrl.text.trim().isEmpty ? '0' : commCtrl.text.trim(),
            'tds': tdsCtrl.text.trim().isEmpty ? '0' : tdsCtrl.text.trim(),
            'tcs': tcsCtrl.text.trim().isEmpty ? '0' : tcsCtrl.text.trim(),
          });
          _snack(res.data['message'] ?? 'Saved');
          setState(() {
            _data?['commission']?['commission'] =
                double.tryParse(commCtrl.text) ?? 0;
            _data?['commission']?['tds'] =
                double.tryParse(tdsCtrl.text) ?? 0;
            _data?['commission']?['tcs'] =
                double.tryParse(tcsCtrl.text) ?? 0;
          });
        } catch (e) {
          if (e is DioException) {
            _snack(e.response?.data?['error']?.toString() ?? friendlyError(e));
          } else { _snack(friendlyError(e)); }
        }
      }),
    ]));
  }

  void _changeCategorySheet() async {
    final rooms = (_data?['rooms'] as List?) ?? [];
    if (rooms.isEmpty) { _snack('No rooms in this booking'); return; }

    // Load categories
    List<Map<String, dynamic>> cats = [];
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(
          AppConfig.roomCategories, {'user_id': uid});
      cats = List<Map<String, dynamic>>.from(
          (res.data['categories'] as List).map((c) => Map<String, dynamic>.from(c)));
    } catch (e) { _snack('Could not load categories'); return; }

    if (!mounted) return;

    // Per room selected category
    final Map<String, int?> selected = {
      for (final r in rooms) r['id'].toString(): null
    };

    _sheet(StatefulBuilder(builder: (ctx, set) => Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      _shTitle('Change room category'),
      ...rooms.map((r) {
        final rId = r['id'].toString();
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['room_category']?.toString() ?? '-',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border)),
              child: DropdownButtonHideUnderline(child: DropdownButton<int>(
                value: selected[rId],
                isExpanded: true,
                hint: const Text('Select new category',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                items: cats.map((c) => DropdownMenuItem<int>(
                  value: c['id'] as int,
                  child: Text(c['category_name'].toString()),
                )).toList(),
                onChanged: (v) => set(() => selected[rId] = v),
              )),
            ),
          ]),
        );
      }).toList(),
      const SizedBox(height: 8),
      _shBtn('Save changes', () async {
        final changes = selected.entries
            .where((e) => e.value != null)
            .map((e) => {'room_book_id': int.parse(e.key), 'new_category_id': e.value})
            .toList();
        if (changes.isEmpty) { _snack('Select at least one new category'); return; }
        Navigator.pop(ctx);
        try {
          final uid = await ApiService.instance.getUserId();
          final res = await ApiService.instance.postData(
              AppConfig.changeCategory, {
            'user_id': uid,
            'booking_id': _b['id']?.toString(),
            'room_changes': changes,
          });
          _snack(res.data['message'] ?? 'Category changed');
          _load();
        } catch (e) {
          if (e is DioException) {
            _snack(e.response?.data?['error']?.toString() ?? friendlyError(e));
          } else { _snack(friendlyError(e)); }
        }
      }),
    ])));
  }

  void _revokeBooking() {
    _sheet(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _shTitle('Revoke booking'),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(12)),
        child: const Row(children: [
          Icon(Icons.info_outline, color: AppColors.primary, size: 20),
          SizedBox(width: 10),
          Expanded(child: Text(
              'This will restore the cancelled booking and re-block inventory.',
              style: TextStyle(fontSize: 13, color: AppColors.primary))),
        ]),
      ),
      const SizedBox(height: 20),
      _shBtn('Revoke booking', () async {
        Navigator.pop(context);
        try {
          final uid = await ApiService.instance.getUserId();
          final res = await ApiService.instance.postData(
            AppConfig.revokeBooking,
            {'user_id': uid, 'booking_id': _b['id']?.toString()},
          );
          _snack(res.data['message'] ?? 'Revoked');
          _load();
        } catch (e) {
          if (e is DioException) {
            final d = e.response?.data;
            if (d?['sold_out_dates'] != null) {
              final dates = (d['sold_out_dates'] as List).join('\n');
              _snack('Not available:\n$dates');
            } else {
              _snack(d?['error']?.toString() ?? friendlyError(e));
            }
          } else { _snack(friendlyError(e)); }
        }
      }),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity,
          child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep cancelled'))),
    ]));
  }



  void _editBill() async {
    final result = await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EditBillScreen(
          booking: Map<String, dynamic>.from(_b as Map),
          rooms: (_data?['rooms'] as List?) ?? [],
          posItems: (_data?['pos_items'] as List?) ?? [],
        )));
    if (result == true) _load();
  }

  void _guestGst() {
    final gstCtrl  = TextEditingController(text: _data?['guest_gst']?['gstnumber'] ?? '');
    final coCtrl   = TextEditingController(text: _data?['guest_gst']?['company'] ?? '');
    final addrCtrl = TextEditingController(text: _data?['guest_gst']?['address'] ?? '');
    String state   = _data?['guest_gst']?['state'] ?? '';

    final states = [
      '01|Jammu & Kashmir','02|Himachal Pradesh','03|Punjab','04|Chandigarh',
      '05|Uttarakhand','06|Haryana','07|Delhi','08|Rajasthan','09|Uttar Pradesh',
      '10|Bihar','11|Sikkim','12|Arunachal Pradesh','13|Nagaland','14|Manipur',
      '15|Mizoram','16|Tripura','17|Meghalaya','18|Assam','19|West Bengal',
      '20|Jharkhand','21|Odisha','22|Chhattisgarh','23|Madhya Pradesh','24|Gujarat',
      '25|Daman & Diu','26|Dadra & Nagar Haveli','27|Maharashtra','28|Andhra Pradesh',
      '29|Karnataka','30|Goa','31|Lakshadweep','32|Kerala','33|Tamil Nadu',
      '34|Puducherry','35|Andaman & Nicobar Islands','36|Telangana','37|Andhra Pradesh (New)',
    ];

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) => StatefulBuilder(builder: (ctx, set) =>
            Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
              child: Container(
                decoration: const BoxDecoration(color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(height: 12),
                  Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: AppColors.border,
                          borderRadius: BorderRadius.circular(2))),
                  Align(alignment: Alignment.centerRight,
                      child: IconButton(
                          icon: Container(width: 30, height: 30,
                              decoration: BoxDecoration(color: AppColors.background,
                                  borderRadius: BorderRadius.circular(20)),
                              child: const Icon(Icons.close, size: 16,
                                  color: AppColors.textSecondary)),
                          onPressed: () => Navigator.pop(ctx))),
                  Flexible(child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _shTitle('Guest GST Details'),
                      if (_isInvoiceCreated) ...[
                        Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: AppColors.accentSoft,
                                borderRadius: BorderRadius.circular(10)),
                            child: const Text(
                                'Invoice is created — these details are saved in the invoice. '
                                    'Editing will update the invoice.',
                                style: TextStyle(fontSize: 12, color: AppColors.primary))),
                        const SizedBox(height: 12),
                      ],
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('GST Number', style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: gstCtrl,
                          keyboardType: TextInputType.text,
                          decoration: const InputDecoration(isDense: true),
                          onChanged: (v) {
                            if (v.length >= 2) {
                              final code = v.substring(0, 2);
                              final match = states.firstWhere(
                                      (s) => s.startsWith('$code|'), orElse: () => '');
                              if (match.isNotEmpty) set(() => state = match);
                            }
                          },
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('State', style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                        const SizedBox(height: 6),
                        Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(color: AppColors.background,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.border)),
                            child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                              value: state.isEmpty ? null : state,
                              isExpanded: true,
                              hint: const Text('Select state',
                                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                              items: states.map((s) => DropdownMenuItem(
                                  value: s, child: Text(s.split('|').last))).toList(),
                              onChanged: (v) => set(() => state = v ?? ''),
                            ))),
                      ]),
                      const SizedBox(height: 12),
                      _shField(coCtrl, 'Company name', TextInputType.text),
                      const SizedBox(height: 12),
                      _shField(addrCtrl, 'Address', TextInputType.text),
                      const SizedBox(height: 8),
                    ]),
                  )),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: _shBtn('Save GST details', () async {
                      if (gstCtrl.text.trim().isEmpty) { _snack('Enter GST number'); return; }
                      if (coCtrl.text.trim().isEmpty) { _snack('Enter company name'); return; }
                      Navigator.pop(ctx);
                      try {
                        final uid = await ApiService.instance.getUserId();
                        final res = await ApiService.instance.postData(
                            AppConfig.saveGuestGst, {
                          'user_id': uid,
                          'booking_id': _b['id']?.toString(),
                          'gstnumber': gstCtrl.text.trim(),
                          'company': coCtrl.text.trim(),
                          'address': addrCtrl.text.trim(),
                          'state': state,
                        });
                        _snack(res.data['message'] ?? 'GST details saved');
                        _load();
                      } catch (e) {
                        if (e is DioException) {
                          _snack(e.response?.data?['error']?.toString() ?? friendlyError(e));
                        } else { _snack(friendlyError(e)); }
                      }
                    }),
                  ),
                ])),
              ),
            )));
  }

  void _invoiceGst() {
    // After invoice — cm_invoice direct update
    final invData  = (_data?['invoice'] as Map?)?.map((k,v) => MapEntry(k.toString(), v)) ?? {};
    final gstCtrl  = TextEditingController(text: invData['gstnumber']?.toString() ?? '');
    final coCtrl   = TextEditingController(text: invData['company']?.toString() ?? '');
    final addrCtrl = TextEditingController(text: invData['address']?.toString() ?? '');
    String state   = invData['state']?.toString() ?? '';
    bool isB2B     = (invData['gstnumber']?.toString() ?? '').isNotEmpty;

    final states = [
      '01|Jammu & Kashmir','02|Himachal Pradesh','03|Punjab','04|Chandigarh',
      '05|Uttarakhand','06|Haryana','07|Delhi','08|Rajasthan','09|Uttar Pradesh',
      '10|Bihar','11|Sikkim','12|Arunachal Pradesh','13|Nagaland','14|Manipur',
      '15|Mizoram','16|Tripura','17|Meghalaya','18|Assam','19|West Bengal',
      '20|Jharkhand','21|Odisha','22|Chhattisgarh','23|Madhya Pradesh','24|Gujarat',
      '25|Daman & Diu','26|Dadra & Nagar Haveli','27|Maharashtra','28|Andhra Pradesh',
      '29|Karnataka','30|Goa','31|Lakshadweep','32|Kerala','33|Tamil Nadu',
      '34|Puducherry','35|Andaman & Nicobar Islands','36|Telangana','37|Andhra Pradesh (New)',
    ];

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) => StatefulBuilder(builder: (ctx, set) =>
            Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
              child: Container(
                decoration: const BoxDecoration(color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(height: 12),
                  Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: AppColors.border,
                          borderRadius: BorderRadius.circular(2))),
                  Align(alignment: Alignment.centerRight,
                      child: IconButton(
                          icon: Container(width: 30, height: 30,
                              decoration: BoxDecoration(color: AppColors.background,
                                  borderRadius: BorderRadius.circular(20)),
                              child: const Icon(Icons.close, size: 16,
                                  color: AppColors.textSecondary)),
                          onPressed: () => Navigator.pop(ctx))),

                  Flexible(child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _shTitle('Invoice GST Details'),

                        // B2B / B2C toggle
                        Row(children: [
                          Expanded(child: GestureDetector(
                            onTap: () => set(() => isB2B = true),
                            child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                    color: isB2B ? AppColors.primary : AppColors.background,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: isB2B ? AppColors.primary : AppColors.border)),
                                child: Center(child: Text('B2B',
                                    style: TextStyle(fontWeight: FontWeight.w700,
                                        color: isB2B ? Colors.white : AppColors.textSecondary)))),
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: GestureDetector(
                            onTap: () => set(() { isB2B = false; gstCtrl.clear(); }),
                            child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                    color: !isB2B ? AppColors.primary : AppColors.background,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: !isB2B ? AppColors.primary : AppColors.border)),
                                child: Center(child: Text('B2C',
                                    style: TextStyle(fontWeight: FontWeight.w700,
                                        color: !isB2B ? Colors.white : AppColors.textSecondary)))),
                          )),
                        ]),
                        const SizedBox(height: 16),

                        if (isB2B) ...[
                          // GST number with auto state
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('GST Number', style: TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                            const SizedBox(height: 4),
                            TextField(
                              controller: gstCtrl,
                              keyboardType: TextInputType.text,
                              decoration: const InputDecoration(isDense: true),
                              onChanged: (v) {
                                if (v.length >= 2) {
                                  final code = v.substring(0, 2);
                                  final match = states.firstWhere(
                                          (s) => s.startsWith('$code|'), orElse: () => '');
                                  if (match.isNotEmpty) set(() => state = match);
                                }
                              },
                            ),
                          ]),
                          const SizedBox(height: 12),
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('State', style: TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                            const SizedBox(height: 4),
                            Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(color: AppColors.background,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: AppColors.border)),
                                child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                                  value: state.isEmpty ? null : state,
                                  isExpanded: true,
                                  hint: const Text('Select state',
                                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                                  items: states.map((s) => DropdownMenuItem(
                                      value: s, child: Text(s.split('|').last))).toList(),
                                  onChanged: (v) => set(() => state = v ?? ''),
                                ))),
                          ]),
                          const SizedBox(height: 12),
                          _shField(coCtrl, 'Company name', TextInputType.text),
                          const SizedBox(height: 12),
                          _shField(addrCtrl, 'Address', TextInputType.text),
                          const SizedBox(height: 12),
                        ] else ...[
                          Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: AppColors.accentSoft,
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Text(
                                  'B2C selected — B2C selected — GST details will be removed and invoice will be marked as B2C.',
                                  style: TextStyle(fontSize: 12, color: AppColors.primary))),
                          const SizedBox(height: 12),
                        ],
                      ])),
                  ),

                  // Fixed save button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: _shBtn('Update invoice', () async {
                      if (isB2B && gstCtrl.text.trim().isEmpty) {
                        _snack('Enter GST number'); return;
                      }
                      Navigator.pop(ctx);
                      try {
                        final uid = await ApiService.instance.getUserId();
                        final res = await ApiService.instance.postData(
                            AppConfig.updateInvoiceGst, {
                          'user_id': uid,
                          'booking_id': _b['id']?.toString(),
                          'gstnumber': isB2B ? gstCtrl.text.trim() : '',
                          'company':   isB2B ? coCtrl.text.trim()  : '',
                          'address':   isB2B ? addrCtrl.text.trim(): '',
                          'state':     isB2B ? state               : '',
                        });
                        _snack(res.data['message'] ?? 'Updated');
                        _load();
                      } catch (e) {
                        if (e is DioException) {
                          _snack(e.response?.data?['error']?.toString() ?? friendlyError(e));
                        } else { _snack(friendlyError(e)); }
                      }
                    }),
                  ),
                ])),
              ),
            )));
  }

  void _cancelBooking() {
    _sheet(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _shTitle('Cancel booking'),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFFFDE7E7),
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFC0392B), size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(
              'Cancel booking for ${_b['guest_name'] ?? 'this guest'}?\n'
                  'This action cannot be undone.',
              style: const TextStyle(fontSize: 13, color: Color(0xFFC0392B)))),
        ]),
      ),
      const SizedBox(height: 20),
      _shBtn('Cancel booking', () async {
        Navigator.pop(context);
        try {
          final uid = await ApiService.instance.getUserId();
          final res = await ApiService.instance.postData(
            AppConfig.cancelBooking,
            {'user_id': uid, 'booking_id': _b['id']?.toString()},
          );
          _snack(res.data['message'] ?? 'Cancelled');
          _load();
        } catch (e) {
          if (e is DioException) {
            _snack(e.response?.data?['error']?.toString() ?? friendlyError(e));
          } else { _snack(friendlyError(e)); }
        }
      }, danger: true),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity,
          child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep booking'))),
    ]));
  }

  void _createInvoice() async {
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(
        AppConfig.createInvoice,
        {'user_id': uid, 'booking_id': _b['id']?.toString()},
      );
      _snack(res.data['message'] ?? 'Invoice created');
      _load();
    } catch (e) {
      if (e is DioException) {
        _snack(e.response?.data?['error']?.toString() ?? friendlyError(e));
      } else { _snack(friendlyError(e)); }
    }
  }

  void _cancelInvoice() {
    _sheet(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _shTitle('Cancel invoice'),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFFFDE7E7),
            borderRadius: BorderRadius.circular(12)),
        child: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFC0392B), size: 20),
          SizedBox(width: 10),
          Expanded(child: Text(
              'After cancelling the invoice, booking will revert to proforma.',
              style: TextStyle(fontSize: 13, color: Color(0xFFC0392B)))),
        ]),
      ),
      const SizedBox(height: 20),
      _shBtn('Cancel invoice', () async {
        Navigator.pop(context);
        try {
          final uid = await ApiService.instance.getUserId();
          final res = await ApiService.instance.postData(
            AppConfig.cancelInvoice,
            {'user_id': uid, 'booking_id': _b['id']?.toString()},
          );
          _snack(res.data['message'] ?? 'Invoice cancelled');
          _load();
        } catch (e) {
          if (e is DioException) {
            _snack(e.response?.data?['error']?.toString() ?? friendlyError(e));
          } else { _snack(friendlyError(e)); }
        }
      }, danger: true),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity,
          child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep invoice'))),
    ]));
  }

  void _invoice() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => InvoiceScreen(
          bookingId: _b['id']?.toString() ?? '',
          guestName: _b['guest_name']?.toString() ?? '',
        )));
  }

  void _voucher() {
    final bookingId = _b['id']?.toString() ?? '';
    final guestName = _b['guest_name']?.toString() ?? 'Guest';
    final phone     = _b['phone']?.toString() ?? '';
    final url       = 'https://live.billzify.com/receipt/?cd=$bookingId';

    // Phone clean karo
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final hasPhone   = cleanPhone.isNotEmpty &&
        cleanPhone.replaceAll('0', '').isNotEmpty;

    // WhatsApp message
    final msg = Uri.encodeComponent(
        'Dear $guestName,\n\nPlease find your booking voucher below:\n$url\n\nThank you!');
    final waUrl = 'https://wa.me/91$cleanPhone?text=$msg';

    _sheet(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _shTitle('Voucher'),

      // Link preview
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border)),
        child: Row(children: [
          const Icon(Icons.link, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(url,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
      ),
      const SizedBox(height: 16),

      // WhatsApp button — sirf tab dikhao jab phone ho
      if (hasPhone) ...[
        SizedBox(width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await launchUrl(
                    Uri.parse(waUrl),
                    mode: LaunchMode.externalApplication,
                  );
                } catch (e) {
                  _snack('Could not open WhatsApp');
                }
              },
              icon: const Icon(Icons.message, color: Colors.white, size: 18),
              label: const Text('Send on WhatsApp',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
            )),
        const SizedBox(height: 10),
      ],

      // Share button
      _shBtn('Share via other apps', () async {
        Navigator.pop(context);
        await Share.share(
            'Dear $guestName,\n\nYour booking voucher:\n$url',
            subject: 'Booking Voucher');
      }),
      const SizedBox(height: 10),

      // Copy link
      SizedBox(width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(context);
              _snack('Link copied!');
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy link'),
          )),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        title: Text(_b['guest_name']?.toString() ?? 'Booking detail',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
        actions: [
          if (_hasPhone)
            IconButton(
                icon: Container(width: 36, height: 36,
                    decoration: const BoxDecoration(
                        color: AppColors.accentSoft, shape: BoxShape.circle),
                    child: const Icon(Icons.call,
                        color: AppColors.primary, size: 18)),
                onPressed: _call),
          if (!_loading && _data != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              onSelected: (v) async {
                switch (v) {
                  case 'pay': _addPayment(); break;
                  case 'guest': _editGuest(); break;
                  case 'dates': _editDates(); break;
                  case 'comm': _editCommission(); break;
                  case 'category': _changeCategorySheet(); break;  // ✅ ADD YEH
                  case 'invoice': _invoice(); break;
                  case 'create_invoice': _createInvoice(); break;
                  case 'cancel_invoice': _cancelInvoice(); break;
                  case 'voucher': _voucher(); break;
                  case 'product': /* ... */ break;
                  case 'bill': _editBill(); break;
                  case 'gst': _isInvoiceCreated ? _invoiceGst() : _guestGst(); break;
                  case 'cancel': _cancelBooking(); break;
                  case 'revoke': _revokeBooking(); break;
                }
              },
              itemBuilder: (_) => [
                _mi('pay', Icons.payments_outlined, 'Add payment'),
                _mi('guest', Icons.person_outline, 'Edit guest'),
                _mi('dates', Icons.calendar_today_outlined, 'Edit dates'),
                // _mi('amounts', Icons.edit_outlined, 'Edit amounts'),
                _mi('comm', Icons.percent_outlined, 'Commission / TDS'),
                const PopupMenuDivider(),
                if (_data?['has_invoice'] == true) ...[
                  _mi('invoice', Icons.receipt_long_outlined, 'View invoice'),
                  _mi('cancel_invoice', Icons.cancel_outlined, 'Cancel invoice'),
                ] else ...[
                  _mi('invoice', Icons.receipt_long_outlined, 'View proforma'),
                  _mi('create_invoice', Icons.add_outlined, 'Create invoice'),
                ],
                _mi('voucher', Icons.confirmation_number_outlined, 'Voucher'),
                _mi('product', Icons.receipt_outlined, 'Add product bill'),
                _mi('category', Icons.swap_horiz_outlined, 'Change category'),
                _mi('bill', Icons.edit_note_outlined, 'Edit bill'),
                _mi('gst', Icons.receipt_outlined,
                    _isInvoiceCreated ? 'Update Invoice GST' : 'Guest GST'),
                const PopupMenuDivider(),
                if ((_b['status']?.toString() ?? '').toLowerCase() != 'cancel')
                  _mi('cancel', Icons.cancel_outlined,
                      'Cancel booking', color: const Color(0xFFC0392B)),
                if ((_b['status']?.toString() ?? '').toLowerCase() == 'cancel')
                  _mi('revoke', Icons.undo_outlined, 'Revoke booking'),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? _skeleton()
          : _error != null
          ? Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ])))
          : RefreshIndicator(
          onRefresh: _load,
          color: AppColors.primary,
          child: _body()),
    );
  }

  Widget _skeleton() {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE8E8E8),
      highlightColor: const Color(0xFFF5F5F5),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Badges row
          Row(children: [
            _skBox(80, 24, radius: 20),
            const SizedBox(width: 8),
            _skBox(70, 24, radius: 20),
            const SizedBox(width: 8),
            _skBox(60, 24, radius: 20),
          ]),
          const SizedBox(height: 14),

          // Booking info card
          _skCard(children: [
            _skRow(), const SizedBox(height: 12),
            _skRow(), const SizedBox(height: 12),
            _skRow(), const SizedBox(height: 12),
            _skRow(short: true),
          ]),
          const SizedBox(height: 14),

          // Rooms
          _skBox(100, 14, radius: 4),
          const SizedBox(height: 8),
          _skCard(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _skBox(120, 14, radius: 4),
              _skBox(80, 14, radius: 4),
            ]),
            const SizedBox(height: 8),
            _skBox(160, 12, radius: 4),
          ]),
          const SizedBox(height: 14),

          // Billing card
          _skBox(60, 14, radius: 4),
          const SizedBox(height: 8),
          _skCard(children: [
            _skRow(), const SizedBox(height: 10),
            _skRow(), const SizedBox(height: 10),
            _skRow(short: true), const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _skBox(double.infinity, 56, radius: 10)),
              const SizedBox(width: 8),
              Expanded(child: _skBox(double.infinity, 56, radius: 10)),
            ]),
          ]),
          const SizedBox(height: 14),

          // Payments
          _skBox(100, 14, radius: 4),
          const SizedBox(height: 8),
          _skCard(children: [
            _skRow(), const SizedBox(height: 10),
            _skRow(short: true),
          ]),
        ],
      ),
    );
  }

  Widget _skCard({required List<Widget> children}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children));

  Widget _skBox(double w, double h, {double radius = 8}) => Container(
      width: w == double.infinity ? null : w,
      height: h,
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius)));

  Widget _skRow({bool short = false}) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _skBox(short ? 80 : 120, 12, radius: 4),
        _skBox(short ? 60 : 80, 12, radius: 4),
      ]);

  Widget _body() {
    final rooms = (_data?['rooms'] as List?) ?? [];
    final payments = (_data?['payments'] as List?) ?? [];
    final logs = (_data?['logs'] as List?) ?? [];
    final comm = (_data?['commission'] as Map?) ?? {};
    final hasInvoice = _data?['has_invoice'] == true;
    final b = _b;

    final grand = (b['grand_total'] as num?)?.toDouble() ?? 0;
    final base = (b['base_amount'] as num?)?.toDouble() ?? 0;
    final tax = (b['tax_amount'] as num?)?.toDouble() ?? 0;
    final adv = (b['advance_amount'] as num?)?.toDouble() ?? 0;
    final rem = (b['remaining_amount'] as num?)?.toDouble() ?? 0;
    final commission = (comm['commission'] as num?)?.toDouble() ?? 0;
    final tds = (comm['tds'] as num?)?.toDouble() ?? 0;
    final tcs = (comm['tcs'] as num?)?.toDouble() ?? 0;
    final net = base - (commission + tds + tcs);
    final cancelled = (b['status']?.toString() ?? '').toLowerCase() == 'cancel';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        // ── Badges ──
        Wrap(spacing: 8, runSpacing: 6, children: [
          if ((b['booking_id'] ?? '').toString().isNotEmpty)
            _badge('Ref: ${b['booking_id']}',
                AppColors.accentSoft, AppColors.primary),
          _payBadge(b['payment_type']?.toString() ?? ''),
          if (cancelled)
            _badge('Cancelled', const Color(0xFFFDE7E7), const Color(0xFFC0392B))
          else
            _badge(b['status']?.toString() ?? 'Book',
                AppColors.accentSoft, AppColors.primary),
        ]),
        const SizedBox(height: 14),

        // ── Booking info ──
        _sec('Booking info'),
        _card(Column(children: [
          _r2('Guest', b['guest_name']?.toString() ?? '-',
              'Phone', _sp(b['phone']?.toString())),
          _r2('Check-in', _pd(b['checkin_date']?.toString()),
              'Check-out', _pd(b['checkout_date']?.toString())),
          _r2('Nights', '${b['nights'] ?? 0}',
              'Rooms', '${b['total_rooms'] ?? 0}'),
          _r2('Channel', b['channel']?.toString() ?? '-',
              'Booked on', b['booking_created']?.toString() ?? '-'),
          if ((b['special_request'] ?? '').toString().isNotEmpty &&
              b['special_request'].toString() != 'null') ...[
            const Divider(height: 14),
            _r1('Special request', b['special_request'].toString()),
          ],
        ])),
        const SizedBox(height: 14),

        // ── Rooms ──
        if (rooms.isNotEmpty) ...[
          _sec('Rooms (${rooms.length})'),
          ...rooms.map(_roomCard),
          const SizedBox(height: 14),
        ],

        // ── Room Status ──
        if ((_data?['room_status'] as List? ?? []).where((rs) =>
        (rs['status'] ?? '') != 'booked').isNotEmpty) ...[
          _sec('Room Status'),
          _card(Column(children: (_data!['room_status'] as List)
              .where((rs) => (rs['status'] ?? '') != 'booked')
              .toList()
              .asMap().entries.map((e) {
            final rs = e.value as Map;
            final st = (rs['status'] ?? 'booked').toString();
            final roomNum = rs['assigned_room'];
            final cat = (rs['room_category'] ?? '').toString();
            Color bg; String label;
            if (st == 'checkin') { bg = const Color(0xFFFEE2E2); label = 'Checked In'; }
            else if (st == 'checkout') { bg = const Color(0xFFD1FAE5); label = 'Checked Out'; }
            else { bg = const Color(0xFFEDE9FF); label = 'Booked'; }
            return Column(children: [
              if (e.key > 0) const Divider(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(roomNum != null ? 'Room $roomNum' : 'Room TBD',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  if (cat.isNotEmpty)
                    Text(cat, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  _badge(label, bg, st == 'checkin' ? const Color(0xFFB91C1C)
                      : st == 'checkout' ? const Color(0xFF065F46) : AppColors.primary),
                  if ((rs['checkin_datetime'] ?? '').toString().isNotEmpty)
                    Text(rs['checkin_datetime'].toString(),
                        style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
                  if ((rs['checkout_datetime'] ?? '').toString().isNotEmpty)
                    Text(rs['checkout_datetime'].toString(),
                        style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
                ]),
              ]),
            ]);
          }).toList())),
          const SizedBox(height: 14),
        ],

// ── POS Items ──
    if ((_data?['pos_items'] as List? ?? []).isNotEmpty) ...[
    _sec('Product bills (${(_data!['pos_items'] as List).length})'),
    _card(Column(children: (_data!['pos_items'] as List)
        .asMap().entries.map((e) {
    final p = e.value as Map;
    return Column(children: [
    if (e.key > 0) const Divider(height: 12),
    Row(children: [
    Expanded(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(p['product_name']?.toString() ?? '-',
    style: const TextStyle(
    fontSize: 13, fontWeight: FontWeight.w600)),
    Text('Qty: ${p['quantity']}  •  '
    'GST: ${(p['gst_rate'] as num?)?.toStringAsFixed(0)}%',
    style: const TextStyle(
    fontSize: 11, color: AppColors.textSecondary)),
    if ((p['note'] ?? '').toString().isNotEmpty)
    Text('📝 ${p['note']}',
    style: const TextStyle(
    fontSize: 11, color: AppColors.textSecondary)),
    ])),
    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
    Text('₹${(p['total_amount'] as num?)?.toStringAsFixed(2)}',
    style: const TextStyle(
    fontSize: 14, fontWeight: FontWeight.w700,
    color: AppColors.primary)),
    Text('Base ₹${(p['base_amount'] as num?)?.toStringAsFixed(0)}  '
    '+  GST ₹${((p['sgst_amount'] as num? ?? 0) + (p['cgst_amount'] as num? ?? 0)).toStringAsFixed(0)}',
    style: const TextStyle(
    fontSize: 10, color: AppColors.textSecondary)),
    ]),
    ]),
    ]);
    }).toList())),
    const SizedBox(height: 14),
    ],




        // ── Billing ──
        _sec('Billing'),
        _card(Column(children: [
          _br('Base amount', base),
          _br('Tax (GST)', tax),
          const Divider(height: 14),
          _br('Grand total', grand, bold: true, large: true),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _pill2('✓ Advance', adv,
                const Color(0xFFD1FAE5), const Color(0xFF065F46))),
            const SizedBox(width: 8),
            Expanded(child: _pill2('⚠ Remaining', rem,
                rem > 0
                    ? const Color(0xFFFEE2E2)
                    : const Color(0xFFD1FAE5),
                rem > 0
                    ? const Color(0xFFB91C1C)
                    : const Color(0xFF065F46))),
          ]),
          if (commission > 0 || tds > 0 || tcs > 0) ...[
            const Divider(height: 14),
            if (commission > 0) _br('Commission', commission),
            if (tds > 0) _br('TDS', tds),
            if (tcs > 0) _br('TCS', tcs),
            const Divider(height: 8),
            _br('Net profit', net, bold: true,
                color: net >= 0 ? AppColors.success : const Color(0xFFC0392B)),
          ],
        ])),
        const SizedBox(height: 14),

        // ── Payments ──
        if (payments.isNotEmpty) ...[
          _sec('Payments (${payments.length})'),
          _card(Column(children: (payments as List)
              .asMap().entries.map((e) {
            final p = e.value as Map;
            return Column(children: [
                if (e.key > 0) const Divider(height: 12),
            Material(
            color: Colors.transparent,
            child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _editPaymentSheet(Map<String, dynamic>.from(p as Map)),
                child: Row(children: [
                  Container(width: 36, height: 36,
                      decoration: BoxDecoration(
                          color: AppColors.successSoft,
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.check_circle_outline,
                          color: AppColors.success, size: 18)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p['mode']?.toString() ?? '-',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(p['date']?.toString() ?? '',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                    if ((p['transaction_id'] ?? '').toString().isNotEmpty)
                      Text('Ref: ${p['transaction_id']}',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                  ])),
                  Row(children: [
                    Text('₹${(p['amount'] as num?)?.toStringAsFixed(2) ?? '0'}',
                        style: const TextStyle(fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.success)),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit_outlined,
                        size: 14, color: AppColors.textSecondary),
                  ]),
                ]),
            ),
            ),
            ]);
          }).toList())),
          const SizedBox(height: 14),
        ],

        // ── Activity log ──
        if (logs.isNotEmpty) ...[
          GestureDetector(
            onTap: () => setState(() => _logsExpanded = !_logsExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
                boxShadow: const [BoxShadow(
                    color: Color(0x06000000), blurRadius: 10, offset: Offset(0,4))],
              ),
              child: Row(children: [
                const Icon(Icons.history, color: AppColors.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text('Activity log (${logs.length})',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary))),
                AnimatedRotation(
                    turns: _logsExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down,
                        color: AppColors.textSecondary)),
              ]),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(children: (logs as List)
                  .asMap().entries.map((e) {
                final log = e.value as Map;
                return Column(children: [
                  if (e.key > 0) const Divider(height: 10),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_li(log['action']?.toString() ?? ''),
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_ll(log['action']?.toString() ?? ''),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      if ((log['description'] ?? '').toString().isNotEmpty)
                        Text(log['description'].toString(),
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                      Text('${log['timestamp']}  •  by ${log['by']}',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                    ])),
                  ]),
                ]);
              }).toList()),
            ),
            crossFadeState: _logsExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Room card ──
  Widget _roomCard(dynamic r) {
    final m = r as Map;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(
            color: Color(0x06000000), blurRadius: 8, offset: Offset(0,3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(m['room_category']?.toString() ?? '-',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14))),
          Text('₹${(m['sell_rate'] as num?)?.toStringAsFixed(2) ?? '0'}/night',
              style: const TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w600, color: AppColors.primary)),
        ]),
        const SizedBox(height: 4),
        Text('${m['rate_plan'] ?? '-'}  •  '
            'Adults: ${m['adults'] ?? 0}  •  '
            'Children: ${m['children'] ?? 0}',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
      ]),
    );
  }

  // ── Action chip ──
  Widget _actionChip(IconData icon, String label, VoidCallback onTap,
      {bool danger = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: danger
                ? const Color(0xFFFDE7E7)
                : AppColors.background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: danger
                    ? const Color(0xFFFCA5A5)
                    : AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15,
                color: danger
                    ? const Color(0xFFC0392B)
                    : AppColors.primary),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: danger
                    ? const Color(0xFFC0392B)
                    : AppColors.textPrimary)),
          ]),
        ),
      );

  // ── Sheet helpers ──
  Widget _shTitle(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(t, style: const TextStyle(
          fontSize: 17, fontWeight: FontWeight.w700)));

  Widget _shField(TextEditingController c, String label, TextInputType type) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(
            fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(controller: c, keyboardType: type,
            decoration: const InputDecoration(isDense: true)),
      ]);

  Widget _shDropdown(String label, String val, List<String> items,
      ValueChanged<String?> cb) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(
            fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border)),
            child: DropdownButtonHideUnderline(child: DropdownButton<String>(
              value: val, isExpanded: true,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              items: items.map((e) =>
                  DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: cb,
            ))),
      ]);

  Widget _shBtn(String label, VoidCallback onTap, {bool danger = false}) =>
      SizedBox(width: double.infinity,
          child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                  backgroundColor: danger
                      ? const Color(0xFFC0392B) : AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700))));

  Widget _dateTile(String label, DateTime? val, VoidCallback onTap) =>
      GestureDetector(onTap: onTap,
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: val != null ? AppColors.primary : AppColors.border,
                      width: val != null ? 1.5 : 1)),
              child: Row(children: [
                Icon(Icons.calendar_today_outlined, size: 14,
                    color: val != null ? AppColors.primary : AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(val == null ? label : _pd(val.toIso8601String()),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: val != null ? AppColors.primary : AppColors.textSecondary)),
              ])));

  // ── UI helpers ──
  PopupMenuItem<String> _mi(String val, IconData icon, String label,
      {Color? color}) =>
      PopupMenuItem(value: val,
          child: Row(children: [
            Icon(icon, size: 17, color: color ?? AppColors.textPrimary),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(
                fontSize: 13, color: color ?? AppColors.textPrimary)),
          ]));

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
            color: Color(0x06000000), blurRadius: 10, offset: Offset(0,4))],
      ), child: child);

  Widget _r2(String l1, String v1, String l2, String v2) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(child: _ic(l1, v1)),
            Expanded(child: _ic(l2, v2)),
          ]));

  Widget _r1(String l, String v) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 5),
          child: _ic(l, v));

  Widget _ic(String l, String v) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l, style: const TextStyle(
            fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Text(v, style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600)),
      ]);

  Widget _br(String l, double v,
      {bool bold=false, bool large=false, Color? color}) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(l, style: TextStyle(fontSize: bold?14:13,
                color: AppColors.textSecondary,
                fontWeight: bold?FontWeight.w700:FontWeight.w400)),
            Text('₹${v.toStringAsFixed(2)}', style: TextStyle(
                fontSize: large?16:13,
                fontWeight: bold?FontWeight.w700:FontWeight.w600,
                color: color ?? AppColors.textPrimary)),
          ]));

  Widget _pill2(String l, double v, Color bg, Color fg) =>
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: TextStyle(fontSize: 11, color: fg,
                fontWeight: FontWeight.w600)),
            Text('₹${v.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: fg)),
          ]));

  Widget _badge(String t, Color bg, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(t, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600, color: fg)));

  Widget _payBadge(String s) {
    final l = s.toLowerCase();
    if (l.contains('partial'))
      return _badge(s, const Color(0xFFE0F7F7), const Color(0xFF0E8A8A));
    if (l.contains('post'))
      return _badge(s, const Color(0xFFFEF6DC), const Color(0xFF9A7B0A));
    if (l.contains('pre') || l.contains('paid'))
      return _badge(s, AppColors.successSoft, AppColors.success);
    return _badge(s, AppColors.accentSoft, AppColors.primary);
  }

  String _sp(String? p) {
    if (p == null || p.isEmpty) return '-';
    final c = p.replaceAll(RegExp(r'[^0-9+]'), '');
    if (c.isEmpty || c.replaceAll(RegExp(r'[0+]'), '').isEmpty) return '-';
    return p;
  }

  String _li(String a) {
    switch (a.toLowerCase()) {
      case 'checkin': return '🟢';
      case 'checkout': return '🔵';
      case 'checkin_rollback': return '🟡';
      case 'checkout_rollback': return '🟠';
      case 'room_change': return '🔄';
      default: return '📋';
    }
  }

  String _ll(String a) {
    switch (a.toLowerCase()) {
      case 'checkin': return 'Check In';
      case 'checkout': return 'Check Out';
      case 'checkin_rollback': return 'Check In Undo';
      case 'checkout_rollback': return 'Check Out Undo';
      case 'room_change': return 'Room Change';
      case 'create booking': return 'Booking Created';
      default: return a;
    }
  }
}