import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';
import 'booking_detail_screen.dart';

class _ActionDef {
  final String id;
  final String labelEn;
  final IconData icon;
  final List<String> fields;
  const _ActionDef(this.id, this.labelEn, this.icon, this.fields);
}

final List<_ActionDef> kActions = [
  _ActionDef('today_arrivals', "Today's Arrivals", Icons.flight_land, ['date']),
  _ActionDef('today_departures', "Today's Departures", Icons.flight_takeoff, ['date']),
  _ActionDef('search_booking', 'Search Booking', Icons.search, ['search_term']),
  _ActionDef('inventory_check', 'Check Inventory', Icons.meeting_room_outlined, ['date']),
  _ActionDef('inventory_update', 'Update Rate/Inventory', Icons.tune, ['date', 'room_category_id', 'new_price', 'new_available']),
  _ActionDef('noshow_list', 'No-Show List', Icons.event_busy_outlined, []),
  _ActionDef('noshow_mark', 'Mark No-Show', Icons.person_off_outlined, ['search_term']),
  _ActionDef('sales_report', 'Sales Report', Icons.bar_chart, []),
  _ActionDef('ota_commission', 'OTA Commission', Icons.percent, []),
  _ActionDef('accounts_report', 'Accounts / GST', Icons.receipt_long_outlined, []),
  _ActionDef('rate_suggestion', 'Rate Suggestion', Icons.trending_up, ['date']),
  _ActionDef('rate_suggestion_range', 'Rate Suggestion (Range)', Icons.date_range, ['start_date', 'end_date']),
  _ActionDef('booking_cancel', 'Cancel Booking', Icons.cancel_outlined, ['search_term']),
  _ActionDef('invoice_generate', 'Generate Invoice', Icons.description_outlined, ['search_term']),
  _ActionDef('booking_create', 'New Booking', Icons.add_box_outlined, []),
  _ActionDef('booking_range_query', 'Bookings in a Date Range', Icons.calendar_month, ['start_date', 'end_date']),
];

class _ResultBlock {
  final String actionLabel;
  final String reply;
  final String? resultType;
  final dynamic data;
  final bool pdfAvailable;
  final String? pdfType;
  final String? pdfDate;
  bool actionDone;
  _ResultBlock({
    required this.actionLabel,
    required this.reply,
    this.resultType,
    this.data,
    this.pdfAvailable = false,
    this.pdfType,
    this.pdfDate,
    this.actionDone = false,
  });
}

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});
  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _askCtrl = TextEditingController();
  String _query = '';
  final List<_ResultBlock> _results = [];
  bool _running = false;
  bool _asking = false;

  List<_ActionDef> get _filteredActions {
    if (_query.trim().isEmpty) return kActions;
    final q = _query.trim().toLowerCase();
    return kActions.where((a) => a.labelEn.toLowerCase().contains(q) || a.id.contains(q)).toList();
  }

  Future<void> _runAction(_ActionDef action, Map<String, dynamic> params) async {
    setState(() => _running = true);
    try {
      final uid = await ApiService.instance.getUserId();
      final body = {'user_id': uid, 'action': action.id, ...params};
      final res = await ApiService.instance.postData(AppConfig.aiRunAction, body);
      if (action.id == 'booking_range_query') {
        final total = res.data['total_count'];
        final agg = res.data['aggregate_value'];
        setState(() {
          _results.insert(0, _ResultBlock(
            actionLabel: action.labelEn,
            reply: agg != null ? 'Total: $agg ($total bookings)' : 'Found $total booking(s).',
            resultType: 'booking_list',
            data: res.data['data'],
          ));
        });
      } else {
        setState(() {
          _results.insert(0, _ResultBlock(
            actionLabel: action.labelEn,
            reply: (res.data['reply'] ?? '').toString(),
            resultType: res.data['result_type']?.toString(),
            data: res.data['data'],
            pdfAvailable: res.data['pdf_available'] == true,
            pdfType: res.data['pdf_type']?.toString(),
            pdfDate: res.data['pdf_date']?.toString(),
          ));
        });
      }
    } catch (e) {
      setState(() {
        _results.insert(0, _ResultBlock(actionLabel: action.labelEn, reply: friendlyError(e)));
      });
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _onActionTap(_ActionDef action) async {
    if (action.id == 'booking_create') {
      setState(() {
        _results.insert(0, _ResultBlock(
          actionLabel: action.labelEn,
          reply: 'Opening new booking wizard…',
          resultType: 'open_booking_wizard',
        ));
      });
      return;
    }
    if (action.fields.isEmpty) {
      _runAction(action, {});
      return;
    }
    final params = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ActionFormSheet(action: action),
    );
    if (params != null) _runAction(action, params);
  }

  Future<void> _askAnything() async {
    final q = _askCtrl.text.trim();
    if (q.isEmpty || _asking) return;
    setState(() => _asking = true);
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(AppConfig.aiAskAnything, {'user_id': uid, 'question': q});
      setState(() {
        _results.insert(0, _ResultBlock(actionLabel: 'Ask: $q', reply: (res.data['reply'] ?? '').toString()));
        _askCtrl.clear();
      });
    } catch (e) {
      setState(() => _results.insert(0, _ResultBlock(actionLabel: 'Ask: $q', reply: friendlyError(e))));
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _askCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: AppColors.card,
          elevation: 0,
          title: const Text('AI Assistant', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
        ),
        body: SafeArea(
          child: Column(
            children: [
              _searchBar(),
              _actionGrid(),
              const Divider(height: 1, color: AppColors.border),
              Expanded(child: _resultsList()),
              _askAnythingBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Find an action…',
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
              ),
            ),
            if (_query.isNotEmpty)
              InkWell(
                onTap: () => setState(() { _searchCtrl.clear(); _query = ''; }),
                child: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _askAnythingBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(14, 8, 14, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _askCtrl,
              style: const TextStyle(fontSize: 13),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _askAnything(),
              decoration: const InputDecoration(
                hintText: 'Ask anything…',
                hintStyle: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _asking ? null : _askAnything,
            child: _asking
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                : const Icon(Icons.send_rounded, size: 20, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _actionGrid() {
    final actions = _filteredActions;
    if (actions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('No matching action.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 130),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: actions.map((a) {
            return InkWell(
              onTap: _running ? null : () => _onActionTap(a),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(a.icon, size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(a.labelEn, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.primary)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _resultsList() {
    if (_results.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Tap a button above to get started.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      itemCount: _results.length,
      itemBuilder: (ctx, i) => _resultCard(_results[i]),
    );
  }

  Widget _resultCard(_ResultBlock r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.actionLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(r.reply, style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textPrimary)),
          if (r.resultType == 'open_booking_wizard')
            Padding(padding: const EdgeInsets.only(top: 10), child: _BookingWizardCard()),
          if (r.data != null && _hasContent(r.data))
            Padding(padding: const EdgeInsets.only(top: 10), child: _dataCard(r)),
          if (r.pdfAvailable)
            Padding(padding: const EdgeInsets.only(top: 10), child: _PdfDownloadButton(pdfType: r.pdfType!, pdfDate: r.pdfDate ?? '')),
        ],
      ),
    );
  }

  bool _hasContent(dynamic data) {
    if (data is List) return data.isNotEmpty;
    if (data is Map) return data.isNotEmpty;
    return false;
  }

  Widget _dataCard(_ResultBlock r) {
    switch (r.resultType) {
      case 'booking_list':
        return _bookingListCard(List<dynamic>.from(r.data));
      case 'inventory_list':
        return _inventoryListCard(List<dynamic>.from(r.data));
      case 'noshow_list':
        return _noshowListCard(List<dynamic>.from(r.data));
      case 'sales_report':
        return _channelTableCard(List<dynamic>.from(r.data), valueKey: 'sales', valueLabel: 'Sales');
      case 'commission_report':
        return _channelTableCard(List<dynamic>.from(r.data), valueKey: 'commission', valueLabel: 'Commission');
      case 'accounts_report':
        return _receivablesCard(List<dynamic>.from(r.data));
      case 'rate_suggestion':
        return _rateSuggestionCard(Map<String, dynamic>.from(r.data as Map));
      case 'rate_suggestion_range':
        return _rateSuggestionRangeCard(List<dynamic>.from(r.data));
      case 'action_confirm':
        return _actionConfirmCard(r);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _bookingListCard(List<dynamic> items) {
    return Container(
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(
        children: items.take(10).map((g) {
          final name = (g['guest_name'] ?? '-').toString();
          final phone = (g['phone'] ?? '').toString();
          final amount = g['amount']?.toString() ?? '0';
          final status = (g['payment_status'] ?? '').toString();
          final ref = (g['booking_ref'] ?? '').toString();
          final channel = (g['channel_name'] ?? '').toString();
          return InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => BookingDetailScreen(booking: Map<String, dynamic>.from(g as Map)),
            )),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border(bottom: g != items.last ? const BorderSide(color: AppColors.border) : BorderSide.none)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          if (ref.isNotEmpty) Text('#$ref', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                        ]),
                        const SizedBox(height: 2),
                        Text([channel, phone].where((s) => s.isNotEmpty).join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('₹$amount', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    if (status.isNotEmpty) Text(status, style: const TextStyle(fontSize: 10, color: AppColors.primary)),
                  ]),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _inventoryListCard(List<dynamic> items) {
    return Container(
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(
        children: items.map((r) {
          final name = (r['roomCode'] ?? '-').toString();
          final available = r['available']?.toString() ?? '0';
          final price = r['price']?.toString() ?? '0';
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border(bottom: r != items.last ? const BorderSide(color: AppColors.border) : BorderSide.none)),
            child: Row(children: [
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              Text('$available avail', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 10),
              Text('₹$price', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _noshowListCard(List<dynamic> items) {
    return Container(
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(
        children: items.take(10).map((g) {
          final name = (g['guest_name'] ?? '-').toString();
          final phone = (g['guest_phone'] ?? '').toString();
          final ref = (g['booking_ref'] ?? '').toString();
          final amount = g['amount']?.toString() ?? '0';
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border(bottom: g != items.last ? const BorderSide(color: AppColors.border) : BorderSide.none)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text([phone, if (ref.isNotEmpty) '#$ref'].where((s) => s.isNotEmpty).join('  ·  '), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ]),
              ),
              Text('₹$amount', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _channelTableCard(List<dynamic> items, {required String valueKey, required String valueLabel}) {
    return Container(
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(
        children: items.take(10).map((c) {
          final channel = (c['channel'] ?? '-').toString();
          final value = c[valueKey]?.toString() ?? '0';
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border(bottom: c != items.last ? const BorderSide(color: AppColors.border) : BorderSide.none)),
            child: Row(children: [
              Expanded(child: Text(channel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              Text('₹$value $valueLabel', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _receivablesCard(List<dynamic> items) {
    return Container(
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(
        children: items.take(10).map((r) {
          final guest = (r['guest'] ?? '-').toString();
          final pending = r['pending']?.toString() ?? '0';
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border(bottom: r != items.last ? const BorderSide(color: AppColors.border) : BorderSide.none)),
            child: Row(children: [
              Expanded(child: Text(guest, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              Text('₹$pending pending', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFFDC2626))),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _rateSuggestionCard(Map<String, dynamic> d) {
    final direction = (d['direction'] ?? 'hold').toString();
    final color = direction == 'increase' ? AppColors.success : direction == 'decrease' ? const Color(0xFFEF4444) : AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.4))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 16, runSpacing: 6, children: [
            _statPill('${d['total_bookings_30d']}', 'bookings (30d)'),
            _statPill('${d['last_minute_pct']}%', 'last-minute'),
            _statPill('${d['avg_lead_days']}d', 'avg lead time'),
          ]),
          if ((d['categories'] as List?)?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 8),
            ...List<dynamic>.from(d['categories']).map((c) {
              final cat = Map<String, dynamic>.from(c as Map);
              final name = (cat['room_category_name'] ?? '').toString();
              final current = cat['current_price']?.toString() ?? '0';
              final suggested = cat['suggested_price']?.toString() ?? '0';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  Text('₹$current → ₹$suggested', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _statPill(String value, String label) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
    ]);
  }

  Widget _rateSuggestionRangeCard(List<dynamic> items) {
    final byDate = <String, List<dynamic>>{};
    for (final item in items) {
      final date = (item['date'] ?? '').toString();
      byDate.putIfAbsent(date, () => []).add(item);
    }
    return Container(
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(
        children: byDate.entries.map((entry) {
          final isLast = entry.key == byDate.keys.last;
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border(bottom: isLast ? BorderSide.none : const BorderSide(color: AppColors.border))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                ...entry.value.map((r) => _RateRangeRow(data: Map<String, dynamic>.from(r as Map))),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _actionConfirmCard(_ResultBlock r) {
    final data = Map<String, dynamic>.from(r.data as Map);
    final action = data['action']?.toString();
    if (action == 'inventory_update') {
      return _InventoryUpdateConfirmCard(data: data, done: r.actionDone, onConfirmed: () => setState(() => r.actionDone = true));
    }
    if (action == 'noshow_mark') {
      return _NoShowConfirmCard(data: data, done: r.actionDone, onConfirmed: () => setState(() => r.actionDone = true));
    }
    if (action == 'booking_cancel') {
      return _BookingCancelConfirmCard(data: data, done: r.actionDone, onConfirmed: () => setState(() => r.actionDone = true));
    }
    if (action == 'invoice_generate') {
      return _InvoiceGenerateConfirmCard(data: data, done: r.actionDone, onConfirmed: () => setState(() => r.actionDone = true));
    }
    return const SizedBox.shrink();
  }
}

// ============================================================
// ACTION FORM SHEET
// ============================================================
class _ActionFormSheet extends StatefulWidget {
  final _ActionDef action;
  const _ActionFormSheet({required this.action});
  @override
  State<_ActionFormSheet> createState() => _ActionFormSheetState();
}

class _ActionFormSheetState extends State<_ActionFormSheet> {
  DateTime? _date;
  DateTime? _startDate;
  DateTime? _endDate;
  final _searchCtrl = TextEditingController();
  final _roomCatIdCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _availCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.action.fields.contains('date')) {
      _date = DateTime.now();
    }
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _roomCatIdCtrl.dispose();
    _priceCtrl.dispose();
    _availCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context, initialDate: _date ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context, firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (range != null) setState(() { _startDate = range.start; _endDate = range.end; });
  }

  void _submit() {
    final fields = widget.action.fields;
    final params = <String, dynamic>{};
    if (fields.contains('date') && _date != null) params['date'] = _fmt(_date!);
    if (fields.contains('start_date') && _startDate != null) params['start_date'] = _fmt(_startDate!);
    if (fields.contains('end_date') && _endDate != null) params['end_date'] = _fmt(_endDate!);
    if (fields.contains('search_term')) params['search_term'] = _searchCtrl.text.trim();
    if (fields.contains('room_category_id')) params['room_category_id'] = _roomCatIdCtrl.text.trim();
    if (fields.contains('new_price')) params['new_price'] = int.tryParse(_priceCtrl.text.trim());
    if (fields.contains('new_available')) params['new_available'] = int.tryParse(_availCtrl.text.trim());
    Navigator.of(context).pop(params);
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.action.fields;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.action.labelEn, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            if (fields.contains('date')) _dateField('Date', _date, _pickDate),
            if (fields.contains('start_date') || fields.contains('end_date'))
              _rangeField('Date range', _startDate, _endDate, _pickRange),
            if (fields.contains('search_term'))
              _textField('Guest name / phone / booking ID', _searchCtrl),
            if (fields.contains('room_category_id'))
              _textField('Room category ID', _roomCatIdCtrl, keyboardType: TextInputType.number),
            if (fields.contains('new_price'))
              _textField('New price (₹)', _priceCtrl, keyboardType: TextInputType.number),
            if (fields.contains('new_available'))
              _textField('New available rooms', _availCtrl, keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 42,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: const Text('Run', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateField(String label, DateTime? value, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
          child: Row(children: [
            const Icon(Icons.calendar_today, size: 15, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(value == null ? label : _fmt(value), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _rangeField(String label, DateTime? start, DateTime? end, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
          child: Row(children: [
            const Icon(Icons.date_range, size: 15, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(start == null ? 'Tap to select $label' : '${_fmt(start)}  →  ${_fmt(end!)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _textField(String label, TextEditingController ctrl, {TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: TextField(
              controller: ctrl, keyboardType: keyboardType,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(border: InputBorder.none, isCollapsed: true),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SHARED DONE BANNER
// ============================================================
Widget _doneBanner(String text) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.successSoft, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.success)),
    child: Row(children: [
      const Icon(Icons.check_circle, color: AppColors.success, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success))),
    ]),
  );
}

// ============================================================
// INVENTORY UPDATE CONFIRM CARD
// ============================================================
class _InventoryUpdateConfirmCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool done;
  final VoidCallback onConfirmed;
  const _InventoryUpdateConfirmCard({required this.data, required this.done, required this.onConfirmed});
  @override
  State<_InventoryUpdateConfirmCard> createState() => _InventoryUpdateConfirmCardState();
}

class _InventoryUpdateConfirmCardState extends State<_InventoryUpdateConfirmCard> {
  late TextEditingController _priceCtrl;
  late TextEditingController _availCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(text: (widget.data['suggested_price'] ?? widget.data['current_price'] ?? 0).toString().replaceAll('.0', ''));
    _availCtrl = TextEditingController(text: (widget.data['suggested_available'] ?? widget.data['current_available'] ?? 0).toString());
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _availCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      await ApiService.instance.postData(AppConfig.aiConfirmInventoryUpdate, {
        'user_id': uid,
        'room_category_id': widget.data['room_category_id'],
        'date': widget.data['date'],
        'new_price': int.tryParse(_priceCtrl.text.trim()) ?? widget.data['current_price'],
        'new_available': int.tryParse(_availCtrl.text.trim()) ?? widget.data['current_available'],
      });
      if (!mounted) return;
      widget.onConfirmed();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomName = (widget.data['room_category_name'] ?? '').toString();
    final dateStr = (widget.data['date'] ?? '').toString();
    if (widget.done) return _doneBanner('$roomName rate updated for $dateStr.');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.primary, width: 1.2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.tune, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(child: Text('$roomName · $dateStr', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _confirmField('Price (₹)', _priceCtrl)),
            const SizedBox(width: 10),
            Expanded(child: _confirmField('Available rooms', _availCtrl)),
          ]),
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626)))],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity, height: 40,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _confirmField(String label, TextEditingController ctrl) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      const SizedBox(height: 4),
      Container(
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: TextField(controller: ctrl, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), decoration: const InputDecoration(border: InputBorder.none, isCollapsed: true)),
      ),
    ]);
  }
}

// ============================================================
// NO-SHOW CONFIRM CARD
// ============================================================
class _NoShowConfirmCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool done;
  final VoidCallback onConfirmed;
  const _NoShowConfirmCard({required this.data, required this.done, required this.onConfirmed});
  @override
  State<_NoShowConfirmCard> createState() => _NoShowConfirmCardState();
}

class _NoShowConfirmCardState extends State<_NoShowConfirmCard> {
  bool _saving = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() { _saving = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      await ApiService.instance.postData(AppConfig.aiConfirmNoshow, {'user_id': uid, 'booking_id': widget.data['booking_id']});
      if (!mounted) return;
      widget.onConfirmed();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final guestName = (widget.data['guest_name'] ?? '').toString();
    final ref = (widget.data['booking_ref'] ?? '').toString();
    final amount = widget.data['amount']?.toString() ?? '0';
    if (widget.done) return _doneBanner('$guestName marked as no-show.');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEF4444), width: 1.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.event_busy_outlined, size: 16, color: Color(0xFFEF4444)),
            const SizedBox(width: 6),
            Expanded(child: Text(guestName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            if (ref.isNotEmpty) Text('#$ref', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: 4),
          Text('₹$amount', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626)))],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity, height: 40,
            child: ElevatedButton(
              onPressed: _saving ? null : _confirm,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Confirm No-Show', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// RATE RANGE ROW
// ============================================================
class _RateRangeRow extends StatefulWidget {
  final Map<String, dynamic> data;
  const _RateRangeRow({required this.data});
  @override
  State<_RateRangeRow> createState() => _RateRangeRowState();
}

class _RateRangeRowState extends State<_RateRangeRow> {
  bool _applying = false;
  bool _applied = false;
  String? _error;

  Future<void> _apply() async {
    setState(() { _applying = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      await ApiService.instance.postData(AppConfig.aiConfirmInventoryUpdate, {
        'user_id': uid,
        'room_category_id': widget.data['room_category_id'],
        'date': widget.data['date'],
        'new_price': widget.data['suggested_price'],
        'new_available': widget.data['available'],
      });
      if (!mounted) return;
      setState(() => _applied = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.data['room_category_name'] ?? '').toString();
    final current = widget.data['current_price']?.toString() ?? '0';
    final suggested = widget.data['suggested_price']?.toString() ?? '0';
    final direction = (widget.data['direction'] ?? 'hold').toString();
    final color = direction == 'increase' ? AppColors.success : direction == 'decrease' ? const Color(0xFFEF4444) : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
        Text('₹$current', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(width: 6),
        Icon(Icons.arrow_forward, size: 11, color: color),
        const SizedBox(width: 6),
        Text('₹$suggested', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(width: 10),
        if (_applied)
          const Icon(Icons.check_circle, size: 18, color: AppColors.success)
        else
          SizedBox(
            height: 28,
            child: ElevatedButton(
              onPressed: _applying ? null : _apply,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0),
              child: _applying
                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Apply', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ),
      ]),
    );
  }
}

// ============================================================
// BOOKING CANCEL CONFIRM CARD
// ============================================================
class _BookingCancelConfirmCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool done;
  final VoidCallback onConfirmed;
  const _BookingCancelConfirmCard({required this.data, required this.done, required this.onConfirmed});
  @override
  State<_BookingCancelConfirmCard> createState() => _BookingCancelConfirmCardState();
}

class _BookingCancelConfirmCardState extends State<_BookingCancelConfirmCard> {
  bool _saving = false;
  String? _error;
  bool _checkedWarning = false;

  Future<void> _confirm() async {
    setState(() { _saving = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      await ApiService.instance.postData(AppConfig.aiConfirmCancelBooking, {'user_id': uid, 'booking_id': widget.data['booking_id']});
      if (!mounted) return;
      widget.onConfirmed();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final guestName = (widget.data['guest_name'] ?? '').toString();
    final ref = (widget.data['booking_ref'] ?? '').toString();
    final amount = widget.data['amount']?.toString() ?? '0';
    final ci = (widget.data['check_in_date'] ?? '').toString();
    final co = (widget.data['check_out_date'] ?? '').toString();
    if (widget.done) return _doneBanner('$guestName\'s booking cancelled.');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEF4444), width: 1.4))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFEF4444)),
            const SizedBox(width: 6),
            const Expanded(child: Text('This will permanently cancel the booking', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Color(0xFFEF4444)))),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(guestName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                  if (ref.isNotEmpty) Text('#$ref', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ]),
                if (ci.isNotEmpty || co.isNotEmpty) ...[const SizedBox(height: 2), Text('$ci → $co', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))],
                const SizedBox(height: 2),
                Text('₹$amount', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => setState(() => _checkedWarning = !_checkedWarning),
            child: Row(children: [
              Icon(_checkedWarning ? Icons.check_box : Icons.check_box_outline_blank, size: 18, color: _checkedWarning ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 6),
              const Expanded(child: Text('I understand this cannot be undone', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary))),
            ]),
          ),
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626)))],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity, height: 40,
            child: ElevatedButton(
              onPressed: (_saving || !_checkedWarning) ? null : _confirm,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), disabledBackgroundColor: AppColors.border, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Confirm Cancel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// INVOICE GENERATE CONFIRM CARD
// ============================================================
class _InvoiceGenerateConfirmCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool done;
  final VoidCallback onConfirmed;
  const _InvoiceGenerateConfirmCard({required this.data, required this.done, required this.onConfirmed});
  @override
  State<_InvoiceGenerateConfirmCard> createState() => _InvoiceGenerateConfirmCardState();
}

class _InvoiceGenerateConfirmCardState extends State<_InvoiceGenerateConfirmCard> {
  bool _saving = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() { _saving = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      await ApiService.instance.postData(AppConfig.aiConfirmInvoiceGenerate, {'user_id': uid, 'booking_id': widget.data['booking_id']});
      if (!mounted) return;
      widget.onConfirmed();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final guestName = (widget.data['guest_name'] ?? '').toString();
    final ref = (widget.data['booking_ref'] ?? '').toString();
    final amount = widget.data['amount']?.toString() ?? '0';
    if (widget.done) return _doneBanner('Invoice generated for $guestName.');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.primary, width: 1.2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.receipt_long_outlined, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(guestName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            if (ref.isNotEmpty) Text('#$ref', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: 4),
          Text('₹$amount', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626)))],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity, height: 40,
            child: ElevatedButton(
              onPressed: _saving ? null : _confirm,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Generate Invoice', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BOOKING CREATE WIZARD
// ============================================================
class _BookingWizardCard extends StatefulWidget {
  @override
  State<_BookingWizardCard> createState() => _BookingWizardCardState();
}

enum _WizardStep { dates, rooms, guest, payment, done }

class _BookingWizardCardState extends State<_BookingWizardCard> {
  _WizardStep _step = _WizardStep.dates;
  bool _loading = false;
  String? _error;
  DateTime? _checkin;
  DateTime? _checkout;
  Map<String, dynamic>? _availabilityData;
  Map<String, dynamic>? _selectedRoom;
  int _roomQty = 1;
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _advanceCtrl = TextEditingController(text: '0');
  String _paymentMode = 'cash';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _advanceCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context, firstDate: now, lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _checkin != null && _checkout != null ? DateTimeRange(start: _checkin!, end: _checkout!) : null,
    );
    if (range == null) return;
    setState(() { _checkin = range.start; _checkout = range.end; });
  }

  Future<void> _checkAvailability() async {
    if (_checkin == null || _checkout == null) {
      setState(() => _error = 'Please select check-in and check-out dates.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(AppConfig.aiWizardCheckDates, {
        'user_id': uid, 'checkin': _fmtDate(_checkin!), 'checkout': _fmtDate(_checkout!),
      });
      if (!mounted) return;
      setState(() { _availabilityData = Map<String, dynamic>.from(res.data as Map); _step = _WizardStep.rooms; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectRoom(Map<String, dynamic> room) {
    setState(() { _selectedRoom = room; _roomQty = 1; _step = _WizardStep.guest; });
  }

  void _goToPayment() {
    if (_nameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Guest name and phone are required.');
      return;
    }
    setState(() { _error = null; _step = _WizardStep.payment; });
  }

  double get _nights {
    if (_checkin == null || _checkout == null) return 1;
    return _checkout!.difference(_checkin!).inDays.toDouble().clamp(1, 999);
  }

  double get _pricePerNight => (_selectedRoom?['price'] as num?)?.toDouble() ?? 0;
  double get _grandTotal => _pricePerNight * _nights * _roomQty;

  Future<void> _createBooking() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      final advance = double.tryParse(_advanceCtrl.text.trim()) ?? 0;
      final remaining = (_grandTotal - advance).clamp(0, double.infinity);
      await ApiService.instance.postData(AppConfig.aiConfirmCreateBooking, {
        'user_id': uid,
        'checkin': _fmtDate(_checkin!),
        'checkout': _fmtDate(_checkout!),
        'guest_name': _nameCtrl.text.trim(),
        'guest_contact': _phoneCtrl.text.trim(),
        'total_guests': 1,
        'payment_mode': _paymentMode,
        'advance_amount': advance,
        'grand_total': _grandTotal,
        'total_base': _grandTotal,
        'total_tax': 0,
        'remaining_amount': remaining,
        'special_request': '',
        'is_occupancy_based': false,
        'rate_plan': _selectedRoom?['rate_plan_name'] ?? '',
        'rooms_data': [{'cat_id': _selectedRoom?['id'], 'qty': _roomQty, 'settle_total': _grandTotal, 'base': _grandTotal, 'gst': 0}],
        'extra_charges': {},
      });
      if (!mounted) return;
      setState(() => _step = _WizardStep.done);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_step == _WizardStep.done) return _doneBanner('Booking created for ${_nameCtrl.text.trim()}.');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.primary, width: 1.2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _wizardStepIndicator(),
          const SizedBox(height: 12),
          if (_step == _WizardStep.dates) _datesStep(),
          if (_step == _WizardStep.rooms) _roomsStep(),
          if (_step == _WizardStep.guest) _guestStep(),
          if (_step == _WizardStep.payment) _paymentStep(),
          if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: const TextStyle(fontSize: 11.5, color: Color(0xFFDC2626)))],
        ],
      ),
    );
  }

  Widget _wizardStepIndicator() {
    final currentIndex = _step.index.clamp(0, 3);
    return Row(
      children: List.generate(4, (i) {
        final active = i <= currentIndex;
        return Expanded(
          child: Row(children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: active ? AppColors.primary : AppColors.border)),
            if (i < 3) Expanded(child: Container(height: 1.5, color: active ? AppColors.primary : AppColors.border)),
          ]),
        );
      }),
    );
  }

  Widget _datesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select check-in & check-out', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 10),
        InkWell(
          onTap: _pickDateRange,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
            child: Row(children: [
              const Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(_checkin == null ? 'Tap to select dates' : '${_fmtDate(_checkin!)}  →  ${_fmtDate(_checkout!)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity, height: 40,
          child: ElevatedButton(
            onPressed: _loading ? null : _checkAvailability,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Check Availability', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _roomsStep() {
    final rooms = (_availabilityData?['rooms'] as List?) ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select a room category', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 10),
        if (rooms.isEmpty)
          const Text('No rooms available for these dates.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))
        else
          ...rooms.map((r) {
            final room = Map<String, dynamic>.from(r as Map);
            final available = (room['available'] as num?)?.toInt() ?? 0;
            final isAvailable = available > 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: isAvailable ? () => _selectRoom(room) : null,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isAvailable ? AppColors.background : AppColors.border.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(room['name']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(isAvailable ? '$available available' : 'Sold out', style: TextStyle(fontSize: 11, color: isAvailable ? AppColors.textSecondary : const Color(0xFFDC2626))),
                      ]),
                    ),
                    Text('₹${room['price']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    if (isAvailable) const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
                  ]),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _guestStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_selectedRoom?['name'] ?? ''} · ${_fmtDate(_checkin!)} → ${_fmtDate(_checkout!)}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        const Text('Guest details', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        _wizardTextField('Guest name', _nameCtrl),
        const SizedBox(height: 8),
        _wizardTextField('Phone number', _phoneCtrl, keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity, height: 40,
          child: ElevatedButton(
            onPressed: _goToPayment,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
            child: const Text('Next', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _paymentStep() {
    final advance = double.tryParse(_advanceCtrl.text.trim()) ?? 0;
    final remaining = (_grandTotal - advance).clamp(0, double.infinity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_nameCtrl.text.trim(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text('${_selectedRoom?['name'] ?? ''} · ${_nights.toInt()} night(s)', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text('Total: ₹${_grandTotal.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
        ),
        const SizedBox(height: 10),
        _wizardTextField('Advance amount (₹)', _advanceCtrl, keyboardType: TextInputType.number, onChanged: (_) => setState(() {})),
        const SizedBox(height: 4),
        Text('Remaining: ₹${remaining.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Row(
          children: ['cash', 'online', 'card'].map((mode) {
            final selected = _paymentMode == mode;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => setState(() => _paymentMode = mode),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: selected ? AppColors.primary : AppColors.accentSoft, borderRadius: BorderRadius.circular(16)),
                  child: Text(mode, style: TextStyle(fontSize: 11, color: selected ? Colors.white : AppColors.primary)),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity, height: 42,
          child: ElevatedButton(
            onPressed: _loading ? null : _createBooking,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Create Booking', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _wizardTextField(String label, TextEditingController ctrl, {TextInputType? keyboardType, void Function(String)? onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: TextField(controller: ctrl, keyboardType: keyboardType, onChanged: onChanged, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), decoration: const InputDecoration(border: InputBorder.none, isCollapsed: true)),
        ),
      ],
    );
  }
}

// ============================================================
// PDF DOWNLOAD BUTTON
// ============================================================
class _PdfDownloadButton extends StatefulWidget {
  final String pdfType;
  final String pdfDate;
  const _PdfDownloadButton({required this.pdfType, required this.pdfDate});
  @override
  State<_PdfDownloadButton> createState() => _PdfDownloadButtonState();
}

class _PdfDownloadButtonState extends State<_PdfDownloadButton> {
  bool _downloading = false;
  String? _error;

  Future<void> _download() async {
    setState(() { _downloading = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      final bytes = await ApiService.instance.getBytes(AppConfig.aiExportPdf, query: {'user_id': uid, 'type': widget.pdfType, 'date': widget.pdfDate});
      final tempDir = Directory.systemTemp;
      final fileName = '${widget.pdfType}_${widget.pdfDate.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '_')}.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await launchUrl(Uri.file(file.path), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _downloading ? null : _download,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _downloading
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                  : const Icon(Icons.picture_as_pdf_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(_downloading ? 'Preparing PDF…' : 'Download as PDF', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.primary)),
            ]),
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_error!, style: const TextStyle(fontSize: 10.5, color: Color(0xFFDC2626)))),
      ],
    );
  }
}