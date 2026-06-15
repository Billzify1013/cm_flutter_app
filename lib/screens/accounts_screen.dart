import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';
import 'gstr1_screen.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});
  @override State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen>
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
    _tab = TabController(length: 3, vsync: this);
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
      final res = await ApiService.instance.postData(AppConfig.accounts, {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a1a),
        elevation: 0,
        title: const Text('Accounts & Taxes',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const Gstr1Screen())),
            child: const Text('GSTR-1', style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
            controller: _tab,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Taxes'),
              Tab(text: 'Receivables'),
              Tab(text: 'Payables'),
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
          _taxesTab(),
          _receivablesTab(),
          _payablesTab(),
        ])),
      ]),
    );
  }

  // ── TAXES TAB ──
  Widget _taxesTab() {
    final taxes = (_data?['tax_list'] as List?) ?? [];
    final total = _n(_data?['total_tax_collected']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      _summaryCard('Total GST Collected', '₹${_f(total, d: 0)}',
          Icons.receipt_long, const Color(0xFF16A34A)),
      const SizedBox(height: 12),
      if (taxes.isEmpty)
        _empty('No tax data for this period')
      else
        _card(Column(children: [
          _tRow(['Tax', 'CGST', 'SGST', 'Total'], header: true),
          ...taxes.map((t) {
            final m = Map<String, dynamic>.from(t as Map);
            return _tRow([
              m['name']?.toString() ?? '-',
              '₹${_f(m['cgst'])}',
              '₹${_f(m['sgst'])}',
              '₹${_f(m['total'])}',
            ]);
          }),
        ])),
    ]);
  }

  // ── RECEIVABLES TAB ──
  Widget _receivablesTab() {
    final list = (_data?['receivables'] as List?) ?? [];
    final total = _n(_data?['total_receivable']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      _summaryCard('Total Receivable', '₹${_f(total, d: 0)}',
          Icons.account_balance_wallet, const Color(0xFFDC2626)),
      const SizedBox(height: 12),
      if (list.isEmpty)
        _empty('No pending receivables')
      else
        ...list.map((r) {
          final m = Map<String, dynamic>.from(r as Map);
          return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(m['guest']?.toString() ?? '-',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('₹${_f(m['pending'], d: 0)}',
                          style: const TextStyle(fontSize: 11,
                              fontWeight: FontWeight.w700, color: Color(0xFFDC2626)))),
                ]),
                const SizedBox(height: 4),
                Text('${m['checkin']} → ${m['checkout']}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                Text('Total: ₹${_f(m['total'], d: 0)}  •  ${m['phone'] ?? ''}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ]));
        }),
    ]);
  }

  // ── PAYABLES TAB ──
  Widget _payablesTab() {
    final purchases = (_data?['payables_purchase'] as List?) ?? [];
    final expenses = (_data?['payables_expense'] as List?) ?? [];
    final total = _n(_data?['total_payable']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      _summaryCard('Total Payable', '₹${_f(total, d: 0)}',
          Icons.payment, const Color(0xFFF59E0B)),
      const SizedBox(height: 12),
      if (purchases.isNotEmpty) ...[
        _sec('Purchase Pending'),
        _card(Column(children: [
          _tRow(['Supplier', 'Bill', 'Total', 'Pending'], header: true),
          ...purchases.map((p) {
            final m = Map<String, dynamic>.from(p as Map);
            return _tRow([
              m['supplier']?.toString() ?? '-',
              m['bill_number']?.toString() ?? '-',
              '₹${_f(m['total'], d: 0)}',
              '₹${_f(m['pending'], d: 0)}',
            ]);
          }),
        ])),
        const SizedBox(height: 12),
      ],
      if (expenses.isNotEmpty) ...[
        _sec('Expense Pending'),
        _card(Column(children: [
          _tRow(['Title', 'Category', 'Total', 'Pending'], header: true),
          ...expenses.map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return _tRow([
              m['title']?.toString() ?? '-',
              m['category']?.toString() ?? '-',
              '₹${_f(m['total'], d: 0)}',
              '₹${_f(m['pending'], d: 0)}',
            ]);
          }),
        ])),
      ],
      if (purchases.isEmpty && expenses.isEmpty)
        _empty('No pending payables'),
    ]);
  }

  // ── Helpers ──
  Widget _summaryCard(String label, String value, IconData icon, Color color) =>
      Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: AppColors.card, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border)),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 22)),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
              Text(value, style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            ]),
          ]));

  Widget _tRow(List<String> cols, {bool header = false}) =>
      Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
              color: header ? const Color(0xFF1a1a1a) : Colors.transparent,
              border: Border(bottom: BorderSide(
                  color: header ? Colors.transparent : AppColors.border, width: 0.5))),
          child: Row(children: cols.asMap().entries.map((e) =>
              Expanded(flex: e.key == 0 ? 2 : 1,
                  child: Text(e.value,
                      textAlign: e.key == 0 ? TextAlign.left : TextAlign.right,
                      style: TextStyle(fontSize: 10,
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
        Container(height: 80, decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16))),
        const SizedBox(height: 12),
        Container(height: 200, decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16))),
      ]));
}