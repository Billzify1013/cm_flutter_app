import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';
import 'booking_detail_screen.dart';

class DetailedSalesReportScreen extends StatefulWidget {
  const DetailedSalesReportScreen({super.key});
  @override
  State<DetailedSalesReportScreen> createState() =>
      _DetailedSalesReportScreenState();
}

class _DetailedSalesReportScreenState
    extends State<DetailedSalesReportScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to   = DateTime.now();
  String _basis  = 'checkin';

  late TabController _tab;

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  static const _basisOptions = [
    {'key': 'checkin', 'label': 'Check-in'},
    {'key': 'booking', 'label': 'Booking Date'},
    {'key': 'invoice', 'label': 'Invoice Date'},
    {'key': 'stay',    'label': 'Stay Date'},
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  String _apiDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  String _pretty(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')} ${_months[d.month-1]} ${d.year}';

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(
          AppConfig.salesReportDetailed, {
        'user_id':    uid,
        'date_from':  _apiDate(_from),
        'date_to':    _apiDate(_to),
        'date_basis': _basis,
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

  // Quick presets
  void _preset(String p) {
    final now = DateTime.now();
    setState(() {
      switch (p) {
        case 'today':
          _from = now; _to = now;
          break;
        case '7d':
          _from = now.subtract(const Duration(days: 6)); _to = now;
          break;
        case '30d':
          _from = now.subtract(const Duration(days: 29)); _to = now;
          break;
        case 'month':
          _from = DateTime(now.year, now.month, 1); _to = now;
          break;
        case 'lmonth':
          _from = DateTime(now.year, now.month - 1, 1);
          _to   = DateTime(now.year, now.month, 0);
          break;
      }
    });
    _load();
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
        title: const Text('Business Report',
            style: TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700, fontSize: 17)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        bottom: TabBar(
            controller: _tab,
            isScrollable: true,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Summary'),
              Tab(text: 'P&L'),
              Tab(text: 'Rate Plans'),
              Tab(text: 'Categories'),
              Tab(text: 'Products'),
              Tab(text: 'Ledger'),
            ]),
      ),
      body: Column(children: [

        // ── Filters ──
        Container(
          color: AppColors.card,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(children: [
            // Date row
            Row(children: [
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
            const SizedBox(height: 8),
            // Basis chips
            SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  ..._basisOptions.map((b) {
                    final sel = _basis == b['key'];
                    return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                            onTap: () => setState(() => _basis = b['key']!),
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                    color: sel ? const Color(0xFF1a1a1a) : AppColors.background,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: sel ? const Color(0xFF1a1a1a) : AppColors.border)),
                                child: Text(b['label']!,
                                    style: TextStyle(fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: sel ? Colors.white : AppColors.textSecondary)))));
                  }),
                  const SizedBox(width: 8),
                  // Quick presets
                  ...[
                    {'k':'today','l':'Today'},
                    {'k':'7d','l':'7D'},
                    {'k':'30d','l':'30D'},
                    {'k':'month','l':'This Month'},
                    {'k':'lmonth','l':'Last Month'},
                  ].map((p) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                          onTap: () => _preset(p['k']!),
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                  color: const Color(0xFFEEF0F8),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(p['l']!,
                                  style: const TextStyle(fontSize: 11,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600)))))),
                ])),
          ]),
        ),

        // ── Content ──
        Expanded(child: _loading
            ? _skeleton()
            : _error != null
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: const TextStyle(
              color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load,
              child: const Text('Retry')),
        ]))
            : TabBarView(
            controller: _tab,
            children: [
              _summaryTab(),
              _plTab(),
              _ratePlanTab(),
              _categoryTab(),
              _productsTab(),
              _ledgerTab(),
            ])),
      ]),
    );
  }

  // ── TAB 1: Summary ──
  Widget _summaryTab() {
    final rev     = _n(_data?['total_revenue']);
    final bookings = _data?['total_bookings_count'] ?? 0;
    final nights   = _data?['total_nights'] ?? 0;
    final rooms    = _data?['total_rooms_count'] ?? 0;
    final roomsRev = _n(_data?['rooms_revenue']);
    final prodRev  = _n(_data?['total_products_revenue']);
    final prodQty  = _data?['total_products_qty'] ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 10, mainAxisSpacing: 10,
            childAspectRatio: 1.5,
            children: [
              _kpi('Total Revenue', '₹${_f(rev, d:0)}',
                  Icons.currency_rupee, const Color(0xFF6C5CE7)),
              _kpi('Bookings', '$bookings',
                  Icons.book_outlined, const Color(0xFF4F8DF5)),
              _kpi('Rooms Revenue', '₹${_f(roomsRev, d:0)}',
                  Icons.bed_outlined, const Color(0xFF10B981)),
              _kpi('Products Revenue', '₹${_f(prodRev, d:0)}',
                  Icons.shopping_bag_outlined, const Color(0xFFF59E0B)),
            ]),
        const SizedBox(height: 12),
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sec('Stay Details'),
          const SizedBox(height: 8),
          _infoRow('Total Bookings', '$bookings'),
          _infoRow('Total Rooms', '$rooms'),
          _infoRow('Total Nights', '$nights'),
          _infoRow('Products Sold', '$prodQty items'),
          _infoRow('Date Basis', _basis),
          _infoRow('Period', '${_pretty(_from)} → ${_pretty(_to)}'),
        ])),
      ],
    );
  }

  // ── TAB 2: P&L ──
  Widget _plTab() {
    final income    = _n(_data?['total_income']);
    final purchase  = _n(_data?['total_purchase']);
    final expense   = _n(_data?['total_expense']);
    final outflow   = _n(_data?['total_outflow']);
    final profit    = _n(_data?['net_profit']);
    final pending   = _n(_data?['total_pending_payable']);
    final pCount    = _data?['purchase_count'] ?? 0;
    final eCount    = _data?['expense_count'] ?? 0;
    final purPaid   = _n(_data?['total_purchase_paid']);
    final purPend   = _n(_data?['total_purchase_pending']);
    final expPaid   = _n(_data?['total_expense_paid']);
    final expPend   = _n(_data?['total_expense_pending']);
    final isProfit  = profit >= 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // P&L Summary
        _plCard('Total Income', '₹${_f(income,d:0)}',
            'Rooms + Products', const Color(0xFF10B981)),
        const SizedBox(height: 10),
        _plCard('Total Purchases', '₹${_f(purchase,d:0)}',
            '$pCount bill(s)', const Color(0xFFF59E0B)),
        const SizedBox(height: 10),
        _plCard('Total Expenses', '₹${_f(expense,d:0)}',
            '$eCount entry(s)', const Color(0xFFEF4444)),
        const SizedBox(height: 10),
        Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: isProfit
                    ? const Color(0xFFEFF6FF) : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isProfit
                        ? const Color(0xFF1E40AF) : const Color(0xFFB91C1C))),
            child: Row(children: [
              Icon(isProfit ? Icons.trending_up : Icons.trending_down,
                  color: isProfit
                      ? const Color(0xFF1E40AF) : const Color(0xFFB91C1C),
                  size: 28),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Net Profit',
                    style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
                Text('₹${_f(profit,d:0)}',
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800,
                        color: isProfit
                            ? const Color(0xFF1E40AF)
                            : const Color(0xFFB91C1C))),
                Text('Income − (Purchase + Expense)',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textSecondary)),
              ])),
            ])),
        const SizedBox(height: 14),
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sec('Payment Details'),
          const SizedBox(height: 8),
          _infoRow('Total Outflow', '₹${_f(outflow,d:0)}'),
          _infoRow('Pending Payable', '₹${_f(pending,d:0)}',
              color: const Color(0xFFDC2626)),
          const Divider(height: 16),
          _infoRow('Purchase Paid', '₹${_f(purPaid,d:0)}',
              color: const Color(0xFF16A34A)),
          _infoRow('Purchase Pending', '₹${_f(purPend,d:0)}',
              color: const Color(0xFFDC2626)),
          const Divider(height: 16),
          _infoRow('Expense Paid', '₹${_f(expPaid,d:0)}',
              color: const Color(0xFF16A34A)),
          _infoRow('Expense Pending', '₹${_f(expPend,d:0)}',
              color: const Color(0xFFDC2626)),
        ])),
      ],
    );
  }

  // ── TAB 3: Rate Plans ──
  Widget _ratePlanTab() {
    final list = (_data?['rateplan_list'] as List?) ?? [];
    if (list.isEmpty) return _empty('No room sales in this period');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(Column(children: [
          _tHdr(['Rate Plan','Rms','Nts','Base','Tax','Revenue']),
          ...list.map((r) {
            final m = Map<String,dynamic>.from(r as Map);
            return _tRow([
              m['rate_plan']?.toString() ?? '-',
              '${m['rooms_count']??0}',
              '${m['nights_total']??0}',
              '₹${_f(m['base_total'],d:0)}',
              '₹${_f(m['tax_total'],d:0)}',
              '₹${_f(m['revenue_total'],d:0)}',
            ]);
          }),
        ])),
      ],
    );
  }

  // ── TAB 4: Categories ──
  Widget _categoryTab() {
    final list = (_data?['category_list'] as List?) ?? [];
    if (list.isEmpty) return _empty('No category data');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(Column(children: [
          _tHdr(['Category','Rooms','Nights','Revenue']),
          ...list.map((c) {
            final m = Map<String,dynamic>.from(c as Map);
            return _tRow([
              m['category']?.toString() ?? '-',
              '${m['rooms_count']??0}',
              '${m['nights_total']??0}',
              '₹${_f(m['revenue_total'],d:0)}',
            ]);
          }),
        ])),
      ],
    );
  }

  // ── TAB 5: Products ──
  Widget _productsTab() {
    final list = (_data?['products_list'] as List?) ?? [];
    if (list.isEmpty) return _empty('No product sales');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: list.map((p) {
        final m = Map<String,dynamic>.from(p as Map);
        return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(m['product']?.toString() ?? '-',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700))),
                Text('₹${_f(m['revenue_total'],d:0)}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 12, children: [
                _chip('GST ${_f(m['gst_rate'],d:0)}%'),
                _chip('Qty: ${m['qty_total']??0}'),
                _chip('Bills: ${m['bills_count']??0}'),
                _chip('Base: ₹${_f(m['base_total'],d:0)}'),
                _chip('Tax: ₹${_f(m['tax_total'],d:0)}'),
              ]),
            ]));
      }).toList(),
    );
  }

  // ── TAB 6: Ledger ──
  Widget _ledgerTab() {
    final list = (_data?['ledger'] as List?) ?? [];
    if (list.isEmpty) return _empty('No transactions');

    return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        itemBuilder: (ctx, i) {
          final l = Map<String,dynamic>.from(list[i] as Map);
          final status   = l['status']?.toString() ?? '';
          final isCancel = status.contains('Cancel');
          final isInvoiced = l['invoiced'] == 'Yes';

          return GestureDetector(
            onTap: () {
              final pk = l['booking_pk'];
              if (pk != null) {
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) => BookingDetailScreen(
                        booking: {'id': pk, 'guest_name': l['guest']})));
              }
            },
            child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                          color: l['type'] == 'POS Product'
                              ? const Color(0xFFFEF3C7)
                              : AppColors.accentSoft,
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(
                          l['type'] == 'POS Product'
                              ? Icons.shopping_bag_outlined
                              : Icons.bed_outlined,
                          size: 18,
                          color: l['type'] == 'POS Product'
                              ? const Color(0xFFD97706)
                              : AppColors.primary)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(l['guest']?.toString() ?? '-',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Text('#${l['booking_id']}',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                    ]),
                    Text(l['description']?.toString() ?? '',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text(l['date']?.toString() ?? '',
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.textSecondary)),
                      const SizedBox(width: 8),
                      _statusBadge(status),
                      if (isInvoiced) ...[
                        const SizedBox(width: 6),
                        _chip2('Invoiced', const Color(0xFF1E40AF),
                            const Color(0xFFEFF6FF)),
                      ],
                    ]),
                  ])),
                  const SizedBox(width: 8),
                  Text('₹${_f(l['amount'],d:0)}',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: isCancel
                              ? const Color(0xFFDC2626) : AppColors.textPrimary)),
                ])),
          );
        });
  }

  // ── Helpers ──

  Widget _kpi(String label, String value, IconData icon, Color color) =>
      Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: 18),
            const Spacer(),
            Text(value, style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary)),
          ]));

  Widget _plCard(String title, String value, String sub, Color color) =>
      Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border)),
          child: Row(children: [
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary,
                  textBaseline: TextBaseline.alphabetic)),
              Text(value, style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: color)),
              Text(sub, style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
            ])),
          ]));

  Widget _tHdr(List<String> cols) => Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      color: const Color(0xFF1a1a1a),
      child: Row(children: cols.asMap().entries.map((e) =>
          Expanded(flex: e.key == 0 ? 2 : 1,
              child: Text(e.value,
                  textAlign: e.key == 0 ? TextAlign.left : TextAlign.center,
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                      color: Colors.white)))).toList()));

  Widget _tRow(List<String> cols) => Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: cols.asMap().entries.map((e) =>
          Expanded(flex: e.key == 0 ? 2 : 1,
              child: Text(e.value,
                  textAlign: e.key == 0 ? TextAlign.left : TextAlign.center,
                  style: const TextStyle(fontSize: 10,
                      color: AppColors.textPrimary)))).toList()));

  Widget _infoRow(String l, String v, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l, style: const TextStyle(
            fontSize: 12, color: AppColors.textSecondary)),
        Text(v, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: color ?? AppColors.textPrimary)),
      ]));

  Widget _chip(String t) => Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(6)),
      child: Text(t, style: const TextStyle(
          fontSize: 10, color: AppColors.primary)));

  Widget _chip2(String t, Color fg, Color bg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(t, style: TextStyle(
          fontSize: 9, fontWeight: FontWeight.w600, color: fg)));

  Widget _statusBadge(String s) {
    if (s.contains('Invoiced'))
      return _chip2(s, const Color(0xFF92400E), const Color(0xFFFEF3C7));
    if (s.contains('Cancel'))
      return _chip2(s, const Color(0xFFB91C1C), const Color(0xFFFEE2E2));
    return _chip2(s, const Color(0xFF065F46), const Color(0xFFD1FAE5));
  }

  Widget _sec(String t) => Text(t, style: const TextStyle(
      fontSize: 13, fontWeight: FontWeight.w700,
      color: AppColors.textSecondary));

  Widget _card(Widget child) => Container(
      width: double.infinity, padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(
            color: Color(0x06000000), blurRadius: 10, offset: Offset(0, 4))],
      ), child: child);

  Widget _dateBox(String label, DateTime value, VoidCallback onTap) =>
      GestureDetector(
          onTap: onTap,
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border)),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 13, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(_pretty(value),
                    style: const TextStyle(fontSize: 11,
                        color: AppColors.primary, fontWeight: FontWeight.w600))),
              ])));

  Widget _empty(String msg) => Center(child: Padding(
      padding: const EdgeInsets.all(40),
      child: Text(msg, style: const TextStyle(
          color: AppColors.textSecondary))));

  Widget _skeleton() => Shimmer.fromColors(
      baseColor: const Color(0xFFE8E8E8),
      highlightColor: const Color(0xFFF5F5F5),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(child: Container(height: 80, margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(14)))),
          Expanded(child: Container(height: 80,
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(14)))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Container(height: 80, margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(14)))),
          Expanded(child: Container(height: 80,
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(14)))),
        ]),
        const SizedBox(height: 16),
        Container(height: 300, decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(14))),
      ]));
}