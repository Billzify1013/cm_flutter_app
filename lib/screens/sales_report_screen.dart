import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:share_plus/share_plus.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';
import '../widgets/channel_avatar.dart';

class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key});
  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  DateTime _selectedFrom = DateTime.now().subtract(const Duration(days: 30));
  DateTime _selectedTo   = DateTime.now();
  int? _selectedChannelIdx;

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  @override
  void initState() { super.initState(); _load(); }

  String _apiDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  String _prettyDate(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')} ${_months[d.month-1]} ${d.year}';

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _selectedFrom : _selectedTo,
      firstDate: DateTime(2020), lastDate: DateTime(2030),
    );
    if (picked != null)
      setState(() => isFrom ? _selectedFrom = picked : _selectedTo = picked);
  }

  void _preset(String p) {
    final now = DateTime.now();
    setState(() {
      switch (p) {
        case 'today':
          _selectedFrom = now; _selectedTo = now; break;
        case '7d':
          _selectedFrom = now.subtract(const Duration(days: 6)); _selectedTo = now; break;
        case '30d':
          _selectedFrom = now.subtract(const Duration(days: 29)); _selectedTo = now; break;
        case 'month':
          _selectedFrom = DateTime(now.year, now.month, 1); _selectedTo = now; break;
        case 'lmonth':
          _selectedFrom = DateTime(now.year, now.month - 1, 1);
          _selectedTo   = DateTime(now.year, now.month, 0); break;
        case 'year':
          _selectedFrom = DateTime(now.year, 1, 1); _selectedTo = now; break;
      }
    });
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _selectedChannelIdx = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(AppConfig.salesReport, {
        'user_id':    uid,
        'start_date': _apiDate(_selectedFrom),
        'end_date':   _apiDate(_selectedTo),
      });
      if (!mounted) return;
      setState(() { _data = Map<String, dynamic>.from(res.data); _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  double _n(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;
  String _f(dynamic v, {int d = 0}) => _n(v).toStringAsFixed(d);

  void _exportCsv() {
    final occupancy = (_data?['occupancy_data'] as List?) ?? [];
    if (occupancy.isEmpty) { _snack('No data to export'); return; }
    final buf = StringBuffer();
    buf.writeln('Date,Booked Rooms,Total Rooms,Occupancy %');
    for (final o in occupancy) {
      final m = Map<String,dynamic>.from(o as Map);
      buf.writeln('${m['date']},${m['booked']},${m['total_rooms']},${m['occupancy']}');
    }
    Share.share(buf.toString(), subject: 'Occupancy Report');
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m),
      duration: const Duration(seconds: 2)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        title: const Text('Sales Report',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
      ),
      body: Column(children: [

        // ── Date Filter ──
        Container(
          color: AppColors.card,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(children: [
            Row(children: [
              Expanded(child: _dateBox(_selectedFrom, () => _pickDate(true))),
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('→', style: TextStyle(
                      fontSize: 16, color: AppColors.textSecondary))),
              Expanded(child: _dateBox(_selectedTo, () => _pickDate(false))),
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
            SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _presetChip('Today',      'today'),
                  _presetChip('7 Days',     '7d'),
                  _presetChip('30 Days',    '30d'),
                  _presetChip('This Month', 'month'),
                  _presetChip('Last Month', 'lmonth'),
                  _presetChip('This Year',  'year'),
                ])),
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
    final channels  = (_data?['channels']       as List?) ?? [];
    final occupancy = (_data?['occupancy_data'] as List?) ?? [];
    final revenue   = _n(_data?['total_revenue']);
    final cancelled = _n(_data?['total_cancelled']);
    final avgOcc    = _n(_data?['avg_occupancy']);
    final bookedRms = _n(_data?['total_booked_rooms']);
    final adr       = _n(_data?['adr']);

    int totalBookings = 0, totalNights = 0, totalRooms = 0;
    for (final c in channels) {
      final m = Map<String,dynamic>.from(c as Map);
      totalBookings += (m['bookings'] as num?)?.toInt() ?? 0;
      totalNights   += (m['nights']   as num?)?.toInt() ?? 0;
      totalRooms    += (m['rooms']    as num?)?.toInt() ?? 0;
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [

        // ── KPI Grid ──
        GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 10, mainAxisSpacing: 10,
            childAspectRatio: 1.55,
            children: [
              _kpi('Net Revenue',   '₹${_f(revenue)}',
                  Icons.currency_rupee,  const Color(0xFF6C5CE7)),
              _kpi('Cancelled',     '₹${_f(cancelled)}',
                  Icons.cancel_outlined, const Color(0xFFDC2626)),
              _kpi('Avg Occupancy', '${_f(avgOcc, d:1)}%',
                  Icons.bed_outlined,    AppColors.primary),
              _kpi('ADR',           '₹${_f(adr)}',
                  Icons.trending_up,     const Color(0xFF9333EA)),
            ]),
        const SizedBox(height: 12),

        // ── Stats Row ──
        Row(children: [
          _statPill('Bookings',   '$totalBookings', Icons.book_outlined),
          const SizedBox(width: 8),
          _statPill('Nights',     '$totalNights',   Icons.nights_stay_outlined),
          const SizedBox(width: 8),
          _statPill('Rooms',      '$totalRooms',    Icons.meeting_room_outlined),
          const SizedBox(width: 8),
          _statPill('Booked Rms', '${bookedRms.toInt()}', Icons.hotel_outlined),
        ]),
        const SizedBox(height: 16),

        // ── Channel Revenue Graph ──
        if (channels.isNotEmpty) ...[
          _sec('Channel Revenue'),
          _card(_channelRevenueChart(channels)),
          const SizedBox(height: 16),
        ],

        // ── Channel Table ──
        if (channels.isNotEmpty) ...[
          _sec('Channel-wise Breakdown'),
          _card(Column(children: [
            _tRow(['Channel','Bkgs','Nts','Rms','Revenue'], header: true),
            ...channels.map((c) {
              final m = Map<String,dynamic>.from(c as Map);
              return _tRow([
                m['channel']?.toString() ?? '-',
                '${m['bookings'] ?? 0}',
                '${m['nights'] ?? 0}',
                '${m['rooms'] ?? 0}',
                '₹${_f(m['sales'])}',
              ]);
            }),
            _tRow([
              'Total', '$totalBookings', '$totalNights',
              '$totalRooms', '₹${_f(revenue)}',
            ], isTotal: true),
          ])),
          const SizedBox(height: 16),
        ],

        // ── Occupancy Table ──
        if (occupancy.isNotEmpty) ...[
          _secRow('Date-wise Occupancy',
              trailing: GestureDetector(
                  onTap: _exportCsv,
                  child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.download_outlined, size: 13, color: Color(0xFF065F46)),
                        SizedBox(width: 4),
                        Text('Export CSV', style: TextStyle(fontSize: 11,
                            color: Color(0xFF065F46), fontWeight: FontWeight.w600)),
                      ])))),
          const SizedBox(height: 8),
          _card(Column(children: [
            _tRow(['Date','Booked','Total','Occ%'], header: true),
            ...occupancy.map((o) {
              final m = Map<String,dynamic>.from(o as Map);
              final occ = _n(m['occupancy']);
              return _tRow([
                m['date']?.toString() ?? '',
                '${m['booked'] ?? 0}',
                '${m['total_rooms'] ?? 0}',
                '${occ.toStringAsFixed(1)}%',
              ], highlight: occ >= 80);
            }),
          ])),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Channel Revenue Chart ──
  Widget _channelRevenueChart(List channels) {
    if (channels.isEmpty) return const SizedBox.shrink();

    final maxRev = channels
        .map((c) => _n((c as Map)['sales']))
        .fold<double>(0, (a, b) => a > b ? a : b);
    if (maxRev == 0) return const SizedBox.shrink();

    final colors = [
      const Color(0xFF6C5CE7), const Color(0xFF4F8DF5),
      const Color(0xFF10B981), const Color(0xFFF59E0B),
      const Color(0xFFEF4444), const Color(0xFF8B5CF6),
      const Color(0xFF22D3EE), const Color(0xFFEC4899),
    ];

    return StatefulBuilder(builder: (ctx, set) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bars
          SizedBox(
            height: 160,
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: channels.asMap().entries.map((e) {
                  final idx  = e.key;
                  final m    = Map<String,dynamic>.from(e.value as Map);
                  final rev  = _n(m['sales']);
                  final h    = (rev / maxRev).clamp(0.0, 1.0);
                  final col  = colors[idx % colors.length];
                  final ch   = m['channel']?.toString() ?? '-';
                  final isSel = _selectedChannelIdx == idx;

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() =>
                      _selectedChannelIdx = isSel ? null : idx),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (isSel)
                            Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 3),
                                decoration: BoxDecoration(
                                    color: col,
                                    borderRadius: BorderRadius.circular(6)),
                                child: Text('₹${_f(rev)}',
                                    style: const TextStyle(
                                        fontSize: 8, color: Colors.white,
                                        fontWeight: FontWeight.w700))),
                          Flexible(
                            child: FractionallySizedBox(
                              heightFactor: h > 0.05 ? h : 0.05,
                              child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  decoration: BoxDecoration(
                                      color: isSel ? col : col.withOpacity(0.7),
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(6)),
                                      border: isSel
                                          ? Border.all(color: col, width: 2)
                                          : null)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: isSel ? col : Colors.transparent,
                                      width: isSel ? 2 : 0)),
                              child: ChannelAvatar(channel: ch, size: 28)),
                        ],
                      ),
                    ),
                  );
                }).toList()),
          ),

          const SizedBox(height: 10),

          // Selected detail card
          if (_selectedChannelIdx != null &&
              _selectedChannelIdx! < channels.length) ...[
            Builder(builder: (_) {
              final m   = Map<String,dynamic>.from(
                  channels[_selectedChannelIdx!] as Map);
              final col = colors[_selectedChannelIdx! % colors.length];
              return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: col.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: col.withOpacity(0.3))),
                  child: Row(children: [
                    ChannelAvatar(channel: m['channel']?.toString() ?? '-', size: 32),
                    const SizedBox(width: 10),
                    Expanded(child: Text(m['channel']?.toString() ?? '-',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700))),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('₹${_f(m['sales'])}',
                          style: TextStyle(fontSize: 14,
                              fontWeight: FontWeight.w800, color: col)),
                      Text('${m['bookings']??0} bkgs · ${m['nights']??0} nts',
                          style: const TextStyle(fontSize: 10,
                              color: AppColors.textSecondary)),
                    ]),
                  ]));
            }),
            const SizedBox(height: 8),
          ],

          // Legend
          Wrap(spacing: 8, runSpacing: 4,
              children: channels.asMap().entries.map((e) {
                final idx = e.key;
                final m   = Map<String,dynamic>.from(e.value as Map);
                final col = colors[idx % colors.length];
                return GestureDetector(
                    onTap: () => setState(() =>
                    _selectedChannelIdx = _selectedChannelIdx == idx ? null : idx),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 8, height: 8,
                          decoration: BoxDecoration(
                              color: col, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(m['channel']?.toString() ?? '-',
                          style: const TextStyle(
                              fontSize: 9, color: AppColors.textSecondary)),
                    ]));
              }).toList()),
        ]));
  }

  // ── Helpers ──

  Widget _dateBox(DateTime value, VoidCallback onTap) =>
      GestureDetector(
          onTap: onTap,
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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

  Widget _presetChip(String label, String key) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
          onTap: () => _preset(key),
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border)),
              child: Text(label, style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)))));

  Widget _kpi(String label, String value, IconData icon, Color color) =>
      Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: const [BoxShadow(
                  color: Color(0x06000000), blurRadius: 8, offset: Offset(0,3))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: 18),
            const Spacer(),
            Text(value, style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary)),
          ]));

  Widget _statPill(String label, String value, IconData icon) =>
      Expanded(child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border)),
          child: Column(children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700)),
            Text(label, style: const TextStyle(
                fontSize: 9, color: AppColors.textSecondary)),
          ])));

  Widget _sec(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary)));

  Widget _secRow(String t, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(child: Text(t, style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700,
            color: AppColors.textSecondary))),
        if (trailing != null) trailing,
      ]));

  Widget _card(Widget child) => Container(
      width: double.infinity, padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(
            color: Color(0x06000000), blurRadius: 10, offset: Offset(0,4))],
      ), child: child);

  Widget _tRow(List<String> cols,
      {bool header = false, bool isTotal = false, bool highlight = false}) =>
      Container(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          decoration: BoxDecoration(
              color: header
                  ? const Color(0xFF1a1a1a)
                  : isTotal ? const Color(0xFFF0F0F0)
                  : highlight ? const Color(0xFFD1FAE5) : Colors.transparent,
              border: const Border(
                  bottom: BorderSide(color: AppColors.border, width: 0.5))),
          child: Row(children: cols.asMap().entries.map((e) {
            final isFirst = e.key == 0;
            final isLast  = e.key == cols.length - 1;
            return Expanded(flex: isFirst ? 2 : 1,
                child: Text(e.value,
                    textAlign: isLast ? TextAlign.right
                        : isFirst ? TextAlign.left : TextAlign.center,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: (header || isTotal)
                            ? FontWeight.w700 : FontWeight.w500,
                        color: header ? Colors.white : AppColors.textPrimary)));
          }).toList()));

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
        Container(height: 200, decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(16))),
        const SizedBox(height: 10),
        Container(height: 200, decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(16))),
      ]));
}