import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';

class OtaCommissionScreen extends StatefulWidget {
  const OtaCommissionScreen({super.key});
  @override
  State<OtaCommissionScreen> createState() => _OtaCommissionScreenState();
}

class _OtaCommissionScreenState extends State<OtaCommissionScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to   = DateTime.now();
  String _filterType = 'checkin';

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  static const _filterOptions = [
    {'key': 'checkin',  'label': 'Stay Date'},
    {'key': 'booking',  'label': 'Booking Date'},
    {'key': 'checkout', 'label': 'Checkout Date'},
  ];

  @override
  void initState() { super.initState(); _load(); }

  String _apiDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  String _prettyDate(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')} ${_months[d.month-1]} ${d.year}';

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(
          AppConfig.otaCommission, {
        'user_id':     uid,
        'start_date':  _apiDate(_from),
        'end_date':    _apiDate(_to),
        'filter_type': _filterType,
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
        backgroundColor: AppColors.card,
        elevation: 0,
        title: const Text('OTA Commission',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
      ),
      body: Column(children: [

        // ── Filters ──
        Container(
          color: AppColors.card,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
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
                          color: AppColors.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.search, color: Colors.white, size: 18))),
            ]),
            const SizedBox(height: 10),
            // Filter type chips
            Row(children: _filterOptions.map((f) {
              final sel = _filterType == f['key'];
              return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                      onTap: () => setState(() => _filterType = f['key']!),
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: sel ? AppColors.primary : AppColors.background,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: sel ? AppColors.primary : AppColors.border)),
                          child: Text(f['label']!,
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600,
                                  color: sel ? Colors.white : AppColors.textSecondary)))));
            }).toList()),
          ]),
        ),

        // ── Body ──
        Expanded(child: _loading
            ? _skeleton()
            : _error != null
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: const TextStyle(
              color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ]))
            : RefreshIndicator(
            onRefresh: _load,
            color: AppColors.primary,
            child: _body())),
      ]),
    );
  }

  Widget _body() {
    final channels     = (_data?['channel_data'] as List?) ?? [];
    final totalRns     = _data?['total_rns'] ?? 0;
    final totalRev     = _n(_data?['total_revenue']);
    final totalComm    = _n(_data?['total_commission']);
    final avgCommPct   = _n(_data?['avg_comm_percent']);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [

        // ── Summary KPIs ──
        GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: [
              _kpi('Total Revenue', '₹${_f(totalRev, d: 0)}',
                  Icons.currency_rupee, const Color(0xFF16A34A)),
              _kpi('Total Commission', '₹${_f(totalComm, d: 0)}',
                  Icons.percent, const Color(0xFFDC2626)),
              _kpi('Avg Commission', '${_f(avgCommPct, d: 1)}%',
                  Icons.trending_down, const Color(0xFFD97706)),
              _kpi('Total Bookings', '$totalRns',
                  Icons.book_outlined, AppColors.primary),
            ]),

        const SizedBox(height: 16),

        // ── Channel Table ──
        if (channels.isNotEmpty) ...[
          _sec('Channel-wise Commission'),
          _card(Column(children: [
            _tRow(['Channel','RNs','Revenue','Commission','Comm%'],
                header: true),
            ...channels.map((c) {
              final m = Map<String,dynamic>.from(c as Map);
              return _tRow([
                m['channel']?.toString() ?? '-',
                '${m['rns'] ?? 0}',
                '₹${_f(m['revenue'], d: 0)}',
                '₹${_f(m['commission'], d: 0)}',
                '${_f(m['commission_percent'], d: 1)}%',
              ]);
            }),
            // Total row
            _tRow([
              'Total',
              '$totalRns',
              '₹${_f(totalRev, d: 0)}',
              '₹${_f(totalComm, d: 0)}',
              '${_f(avgCommPct, d: 1)}%',
            ], isTotal: true),
          ])),
        ] else
          Center(child: Padding(
              padding: const EdgeInsets.all(40),
              child: Text('No commission data found',
                  style: const TextStyle(color: AppColors.textSecondary)))),

        const SizedBox(height: 16),

        // Disclaimer
        Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(10)),
            child: const Text(
                '* Revenue values are calculated from booking data and '
                    'may differ slightly from actual PMS revenues.',
                style: TextStyle(fontSize: 10, color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic))),

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _kpi(String label, String value, IconData icon, Color color) =>
      Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: const [BoxShadow(
                color: Color(0x06000000), blurRadius: 8, offset: Offset(0,3))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: 20),
            const Spacer(),
            Text(value, style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary)),
          ]));

  Widget _tRow(List<String> cols,
      {bool header = false, bool isTotal = false}) =>
      Container(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          decoration: BoxDecoration(
            color: header
                ? const Color(0xFF1a1a1a)
                : isTotal
                ? const Color(0xFFF0F0F0)
                : Colors.transparent,
            border: const Border(
                bottom: BorderSide(color: AppColors.border, width: 0.5)),
          ),
          child: Row(children: cols.asMap().entries.map((e) {
            final isFirst = e.key == 0;
            return Expanded(flex: isFirst ? 2 : 1,
                child: Text(e.value,
                    textAlign: isFirst ? TextAlign.left : TextAlign.center,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: (header || isTotal)
                            ? FontWeight.w700 : FontWeight.w500,
                        color: header ? Colors.white : AppColors.textPrimary)));
          }).toList()));

  Widget _sec(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary)));

  Widget _card(Widget child) => Container(
      width: double.infinity, padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(
            color: Color(0x06000000), blurRadius: 10, offset: Offset(0,4))],
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
                Expanded(child: Text(_prettyDate(value),
                    style: const TextStyle(fontSize: 11,
                        color: AppColors.primary, fontWeight: FontWeight.w600))),
              ])));

  Widget _skeleton() => Shimmer.fromColors(
      baseColor: const Color(0xFFE8E8E8),
      highlightColor: const Color(0xFFF5F5F5),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(child: Container(height: 80,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(16)))),
          Expanded(child: Container(height: 80,
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(16)))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Container(height: 80,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(16)))),
          Expanded(child: Container(height: 80,
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(16)))),
        ]),
        const SizedBox(height: 16),
        Container(height: 300, decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(16))),
      ]));
}