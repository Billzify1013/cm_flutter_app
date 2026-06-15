import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:io';
import 'dart:convert';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';

class Gstr1Screen extends StatefulWidget {
  const Gstr1Screen({super.key});
  @override State<Gstr1Screen> createState() => _Gstr1ScreenState();
}

class _Gstr1ScreenState extends State<Gstr1Screen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();

  late TabController _tab;

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
  }

  @override void dispose() { _tab.dispose(); super.dispose(); }

  String _apiDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  String _pretty(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')} ${_months[d.month-1]} ${d.year}';

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(AppConfig.gstr1, {
        'user_id': uid,
        'date_from': _apiDate(_from),
        'date_to': _apiDate(_to),
      });
      if (!mounted) return;
      setState(() { _data = Map<String, dynamic>.from(res.data); _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020), lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => isFrom ? _from = picked : _to = picked);
  }

  double _n(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;
  String _f(dynamic v, {int d = 2}) => _n(v).toStringAsFixed(d);

  Future<void> _exportCsv() async {
    try {
      _snack('Generating CSV...');
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(AppConfig.gstr1Export, {
        'user_id': uid,
        'date_from': _apiDate(_from),
        'date_to': _apiDate(_to),
        'format': 'csv',
      });
      final csvData = res.data['csv_data']?.toString() ?? '';
      if (csvData.isEmpty) { _snack('No data to export'); return; }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/GSTR1_${_apiDate(_from)}_to_${_apiDate(_to)}.csv');
      await file.writeAsString(csvData);
      await Share.shareXFiles([XFile(file.path)],
          subject: 'GSTR-1 CSV ${_apiDate(_from)} to ${_apiDate(_to)}');
    } catch (e) { _snack(friendlyError(e)); }
  }

  Future<void> _exportExcel() async {
    try {
      _snack('Downloading Excel...');
      final uid = await ApiService.instance.getUserId();
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/GSTR1_${_apiDate(_from)}_to_${_apiDate(_to)}.xlsx';

      await ApiService.instance.downloadFile(
        AppConfig.gstr1ExportExcel,
        filePath,
        data: {
          'user_id': uid,
          'date_from': _apiDate(_from),
          'date_to': _apiDate(_to),
        },
      );

      await Share.shareXFiles([XFile(filePath)],
          subject: 'GSTR-1 Excel ${_apiDate(_from)} to ${_apiDate(_to)}');
    } catch (e) { _snack(friendlyError(e)); }
  }

  Future<void> _exportJson() async {
    try {
      _snack('Generating JSON...');
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(AppConfig.gstr1Export, {
        'user_id': uid,
        'date_from': _apiDate(_from),
        'date_to': _apiDate(_to),
        'format': 'json',
      });

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/GSTR1_${_apiDate(_from)}_to_${_apiDate(_to)}.json');
      await file.writeAsString(JsonEncoder.withIndent('  ').convert(res.data));
      await Share.shareXFiles([XFile(file.path)],
          subject: 'GSTR-1 JSON ${_apiDate(_from)} to ${_apiDate(_to)}');
    } catch (e) { _snack(friendlyError(e)); }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a1a),
        elevation: 0,
        title: const Text('GSTR-1 Report',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.download_outlined, color: Colors.white),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) {
              if (v == 'excel') _exportExcel();
              if (v == 'csv') _exportCsv();
              if (v == 'json') _exportJson();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'excel',
                  child: Row(children: [
                    Icon(Icons.grid_on, size: 16),
                    SizedBox(width: 8), Text('Download Excel')])),
              const PopupMenuItem(value: 'csv',
                  child: Row(children: [
                    Icon(Icons.table_chart_outlined, size: 16),
                    SizedBox(width: 8), Text('Export CSV')])),
              const PopupMenuItem(value: 'json',
                  child: Row(children: [
                    Icon(Icons.data_object, size: 16),
                    SizedBox(width: 8), Text('Export JSON')])),
            ],
          ),
        ],
        bottom: TabBar(
            controller: _tab,
            isScrollable: true,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Summary'),
              Tab(text: 'B2B'),
              Tab(text: 'B2C'),
              Tab(text: 'HSN'),
            ]),
      ),
      body: Column(children: [
        // Filters
        Container(
          color: AppColors.card,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            Expanded(child: _dateBox('From', _from, () => _pickDate(true))),
            const SizedBox(width: 8),
            Expanded(child: _dateBox('To', _to, () => _pickDate(false))),
            const SizedBox(width: 8),
            GestureDetector(
                onTap: _load,
                child: Container(
                    width: 40, height: 40,
                    decoration: const BoxDecoration(
                        color: Color(0xFF1a1a1a), shape: BoxShape.circle),
                    child: const Icon(Icons.search, color: Colors.white, size: 18))),
          ]),
        ),
        // Content
        Expanded(child: _loading
            ? _skeleton()
            : _error != null
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ]))
            : TabBarView(controller: _tab, children: [
          _summaryTab(),
          _b2bTab(),
          _b2cTab(),
          _hsnTab(),
        ])),
      ]),
    );
  }

  // ── SUMMARY TAB ──
  Widget _summaryTab() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Hotel info
      if ((_data?['hotel_name'] ?? '').toString().isNotEmpty)
        Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: AppColors.accentSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.business, size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_data!['hotel_name'].toString(),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text(_data!['hotel_state']?.toString() ?? '',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ])),
            ])),

      // KPI Grid
      GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 10, mainAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: [
            _kpi('Taxable Value', '₹${_f(_data?['total_taxable'], d: 0)}',
                Icons.receipt_outlined, const Color(0xFF6C5CE7)),
            _kpi('CGST', '₹${_f(_data?['total_cgst'], d: 0)}',
                Icons.account_balance, const Color(0xFF4F8DF5)),
            _kpi('SGST', '₹${_f(_data?['total_sgst'], d: 0)}',
                Icons.account_balance_wallet, const Color(0xFF10B981)),
            _kpi('Total Tax', '₹${_f(_data?['total_tax'], d: 0)}',
                Icons.currency_rupee, const Color(0xFFDC2626)),
          ]),
      const SizedBox(height: 16),

      // Document Summary
      _sec('Document Summary'),
      _card(Column(children: [
        _infoRow('Invoice Range', '${_data?['doc_from'] ?? 0} to ${_data?['doc_to'] ?? 0}'),
        _infoRow('Total Invoices', '${_data?['doc_count'] ?? 0}'),
        _infoRow('B2B Invoices', '${_data?['b2b_count'] ?? 0}'),
        _infoRow('B2C Rate Groups', '${_data?['b2cs_count'] ?? 0}'),
      ])),
    ]);
  }

  // ── B2B TAB ──
  Widget _b2bTab() {
    final rows = (_data?['b2b_rows'] as List?) ?? [];
    if (rows.isEmpty) return _empty('No B2B invoices in this period');
    return ListView(padding: const EdgeInsets.all(16), children: [
      _sec('B2B Invoices — Registered (4A, 4B, 6B, 6C)'),
      ...rows.map((r) {
        final m = Map<String, dynamic>.from(r as Map);
        return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppColors.card, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(m['receiver']?.toString() ?? '-',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                Text('Inv #${m['invoice_number']}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ]),
              const SizedBox(height: 4),
              Text('GSTIN: ${m['gstin'] ?? '-'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.primary,
                      fontWeight: FontWeight.w600)),
              Text('Date: ${m['invoice_date']}  •  Rate: ${m['rate']}%',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(children: [
                _miniBox('Taxable', '₹${_f(m['taxable'], d: 0)}'),
                const SizedBox(width: 8),
                _miniBox('CGST', '₹${_f(m['cgst'], d: 0)}'),
                const SizedBox(width: 8),
                _miniBox('SGST', '₹${_f(m['sgst'], d: 0)}'),
              ]),
            ]));
      }),
    ]);
  }

  // ── B2C TAB ──
  Widget _b2cTab() {
    final rows = (_data?['b2cs_list'] as List?) ?? [];
    if (rows.isEmpty) return _empty('No B2C invoices in this period');
    return ListView(padding: const EdgeInsets.all(16), children: [
      _sec('B2C (Small) — Rate-wise (7)'),
      _card(Column(children: [
        _tRow(['POS', 'Rate', 'Taxable', 'CGST', 'SGST', 'Total Tax'], header: true),
        ...rows.map((r) {
          final m = Map<String, dynamic>.from(r as Map);
          return _tRow([
            m['pos']?.toString() ?? '-',
            '${m['rate']}%',
            '₹${_f(m['taxable'], d: 0)}',
            '₹${_f(m['cgst'], d: 0)}',
            '₹${_f(m['sgst'], d: 0)}',
            '₹${_f(m['total'], d: 0)}',
          ]);
        }),
      ])),
    ]);
  }

  // ── HSN TAB ──
  Widget _hsnTab() {
    final rows = (_data?['hsn_list'] as List?) ?? [];
    if (rows.isEmpty) return _empty('No HSN data in this period');
    return ListView(padding: const EdgeInsets.all(16), children: [
      _sec('HSN / SAC Summary (12)'),
      ...rows.map((h) {
        final m = Map<String, dynamic>.from(h as Map);
        return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppColors.card, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: AppColors.accentSoft, borderRadius: BorderRadius.circular(6)),
                    child: Text(m['hsn']?.toString() ?? '-',
                        style: const TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w700, color: AppColors.primary))),
                const SizedBox(width: 8),
                Expanded(child: Text(m['desc']?.toString() ?? '-',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                Text('${m['rate']}%', style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _miniBox('Taxable', '₹${_f(m['taxable'], d: 0)}'),
                const SizedBox(width: 6),
                _miniBox('CGST', '₹${_f(m['cgst'], d: 0)}'),
                const SizedBox(width: 6),
                _miniBox('SGST', '₹${_f(m['sgst'], d: 0)}'),
                const SizedBox(width: 6),
                _miniBox('Value', '₹${_f(m['value'], d: 0)}'),
              ]),
              if ((m['qty'] as num? ?? 0) > 0)
                Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Qty: ${m['qty']}  •  UQC: ${m['uqc']}',
                        style: const TextStyle(fontSize: 10, color: AppColors.textSecondary))),
            ]));
      }),
    ]);
  }

  // ── Helpers ──
  Widget _kpi(String label, String value, IconData icon, Color color) =>
      Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: AppColors.card, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: 18),
            const Spacer(),
            Text(value, style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary)),
          ]));

  Widget _miniBox(String label, String value) => Expanded(
      child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          decoration: BoxDecoration(
              color: AppColors.background, borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
            Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ])));

  Widget _infoRow(String l, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]));

  Widget _tRow(List<String> cols, {bool header = false}) =>
      Container(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          decoration: BoxDecoration(
              color: header ? const Color(0xFF1a1a1a) : Colors.transparent,
              border: Border(bottom: BorderSide(
                  color: header ? Colors.transparent : AppColors.border, width: 0.5))),
          child: Row(children: cols.asMap().entries.map((e) =>
              Expanded(flex: e.key == 0 ? 2 : 1,
                  child: Text(e.value,
                      textAlign: e.key == 0 ? TextAlign.left : TextAlign.right,
                      style: TextStyle(fontSize: 9,
                          fontWeight: header ? FontWeight.w700 : FontWeight.w500,
                          color: header ? Colors.white : AppColors.textPrimary)))).toList()));

  Widget _sec(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)));

  Widget _card(Widget child) => Container(
      width: double.infinity, padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppColors.card, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border)),
      child: child);

  Widget _dateBox(String label, DateTime value, VoidCallback onTap) =>
      GestureDetector(
          onTap: onTap,
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                  color: AppColors.background, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border)),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(_pretty(value),
                    style: const TextStyle(fontSize: 11,
                        color: AppColors.primary, fontWeight: FontWeight.w600))),
              ])));

  Widget _empty(String msg) => Center(child: Padding(
      padding: const EdgeInsets.all(40),
      child: Text(msg, style: const TextStyle(color: AppColors.textSecondary))));

  Widget _skeleton() => Shimmer.fromColors(
      baseColor: const Color(0xFFE8E8E8), highlightColor: const Color(0xFFF5F5F5),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(child: Container(height: 80, margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)))),
          Expanded(child: Container(height: 80,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Container(height: 80, margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)))),
          Expanded(child: Container(height: 80,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)))),
        ]),
        const SizedBox(height: 16),
        Container(height: 200, decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14))),
      ]));
}