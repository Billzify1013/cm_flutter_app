import 'package:flutter/material.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';
import 'booking_detail_screen.dart';

class StayViewScreen extends StatefulWidget {
  const StayViewScreen({super.key});
  @override
  State<StayViewScreen> createState() => _StayViewScreenState();
}

class _StayViewScreenState extends State<StayViewScreen> {
  bool _loading = true;
  bool _firstLoad = true;
  bool _refreshing = false;
  bool _netError = false;
  DateTime _startDate = DateTime.now();

  List<String> _dates = [];
  String _today = '';
  List<dynamic> _categories = [];
  Map<String, dynamic> _stats = {};

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];
  static const _weekdays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

  String _apiDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  String _fmtShort(String iso) {
    try {
      final p = iso.split('-');
      return '${int.parse(p[2]).toString().padLeft(2,'0')} ${_months[int.parse(p[1])-1]}';
    } catch (_) { return iso; }
  }

  String _weekday(String iso) {
    try { return _weekdays[DateTime.parse(iso).weekday - 1]; } catch (_) { return ''; }
  }

  String _dayNum(String iso) {
    try { return iso.split('-')[2]; } catch (_) { return ''; }
  }

  String _monthShort(String iso) {
    try { return _months[int.parse(iso.split('-')[1]) - 1]; } catch (_) { return ''; }
  }

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (_firstLoad) {
      setState(() { _loading = true; _netError = false; });
    } else {
      setState(() => _refreshing = true);
    }
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.getData(
        AppConfig.stayView,
        query: {'user_id': uid, 'start_date': _apiDate(_startDate)},
      );
      if (!mounted) return;
      final data = res.data as Map<String, dynamic>;
      setState(() {
        _dates = List<String>.from(data['dates'] ?? []);
        _today = data['today']?.toString() ?? '';
        _categories = data['categories'] as List? ?? [];
        _stats = data['stats'] as Map<String, dynamic>? ?? {};
        _loading = false; _firstLoad = false; _refreshing = false;
      });
    } catch (e) {
      print('STAY VIEW ERROR: $e');
      if (!mounted) return;
      if (isNetworkError(e)) _netError = true;
      setState(() { _loading = false; _firstLoad = false; _refreshing = false; });
    }
  }

  void _prevDays() { _startDate = _startDate.subtract(const Duration(days: 3)); _load(); }
  void _nextDays() { _startDate = _startDate.add(const Duration(days: 3)); _load(); }
  void _goToday() { _startDate = DateTime.now(); _load(); }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context, initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(
            primary: AppColors.primary, onPrimary: Colors.white, surface: Colors.white)),
        child: child!,
      ),
    );
    if (picked != null) { _startDate = picked; _load(); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card, elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context)),
        title: const Text('Stay View', style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        centerTitle: true,
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: AppColors.border)),
      ),
      body: _loading ? _buildShimmer()
          : _netError ? _buildError()
          : RefreshIndicator(
        onRefresh: _load, color: AppColors.primary,
        child: Stack(children: [
          _buildContent(),
          if (_refreshing)
            const Positioned(top: 0, left: 0, right: 0,
                child: LinearProgressIndicator(minHeight: 2.5,
                    backgroundColor: Colors.transparent, color: AppColors.primary)),
        ]),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 16),
        _buildStats(),
        const SizedBox(height: 16),
        _buildDateNav(),
        const SizedBox(height: 12),
        _buildLegend(),
        const SizedBox(height: 12),
        _buildDateHeader(),
        _buildRoomGrid(),
      ]),
    );
  }

  // ── Stats ──
  Widget _buildStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(left: 4, bottom: 6),
            child: Text('Today', style: TextStyle(fontSize: 13,
                fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
        Row(children: [
          _miniStat('Checked In', '${_stats['checked_in'] ?? 0}', const Color(0xFF00B894)),
          const SizedBox(width: 8),
          _miniStat('Pending', '${_stats['pending'] ?? 0}', const Color(0xFFD63031)),
          const SizedBox(width: 8),
          _miniStat('Check-out', '${_stats['checkouts'] ?? 0}', const Color(0xFF065F46)),
          const SizedBox(width: 8),
          _miniStat('Available', '${_stats['available'] ?? 0}', const Color(0xFF6C5CE7)),
        ]),
      ]),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(color: AppColors.card,
          borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, textAlign: TextAlign.center, style: const TextStyle(
            fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.textSecondary, height: 1.2)),
      ]),
    ));
  }

  // ── Date Nav ──
  Widget _buildDateNav() {
    final rangeText = _dates.isNotEmpty
        ? '${_fmtShort(_dates.first)} – ${_fmtShort(_dates.last)}' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(color: AppColors.card,
            borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          _navBtn(Icons.chevron_left, _prevDays),
          const SizedBox(width: 4),
          Expanded(child: GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (_refreshing)
                  const SizedBox(width: 12, height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary))
                else const Icon(Icons.calendar_today, size: 12, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(rangeText, style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ]),
            ),
          )),
          const SizedBox(width: 4),
          _navBtn(Icons.chevron_right, _nextDays),
          const SizedBox(width: 4),
          GestureDetector(onTap: _goToday,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('Today', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppColors.background,
            borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
        child: Icon(icon, size: 18, color: AppColors.textPrimary)),
  );

  // ── Legend ──
  Widget _buildLegend() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: Row(children: [
      _legendDot(const Color(0xFFEAE4F5), 'Booked'), const SizedBox(width: 14),
      _legendDot(const Color(0xFFFDEBEB), 'Checked-In'), const SizedBox(width: 14),
      _legendDot(const Color(0xFFB7F9EC), 'Checked-Out'),
    ]),
  );

  Widget _legendDot(Color c, String l) => Row(children: [
    Container(width: 24, height: 10,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
    const SizedBox(width: 4),
    Text(l, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500,
        color: AppColors.textSecondary)),
  ]);

  // ── Date Header ──
  Widget _buildDateHeader() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: AppColors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Container(width: 70, padding: const EdgeInsets.symmetric(vertical: 10),
            child: const Center(child: Text('ROOM', style: TextStyle(fontSize: 9,
                fontWeight: FontWeight.w800, color: AppColors.textSecondary, letterSpacing: 1)))),
        ...List.generate(_dates.length, (i) {
          final d = _dates[i]; final isT = d == _today;
          return Expanded(child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: isT ? AppColors.primary : Colors.transparent,
                borderRadius: i == _dates.length - 1
                    ? const BorderRadius.only(topRight: Radius.circular(11)) : null),
            child: Column(children: [
              Text(_dayNum(d), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: isT ? Colors.white : AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(_weekday(d), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                  color: isT ? Colors.white.withOpacity(0.8) : AppColors.textSecondary)),
              Text(_monthShort(d), style: TextStyle(fontSize: 8,
                  color: isT ? Colors.white.withOpacity(0.6) : AppColors.textSecondary)),
            ]),
          ));
        }),
      ]),
    );
  }

  // ── Room Grid ──
  Widget _buildRoomGrid() {
    if (_categories.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(color: AppColors.card,
            border: Border.all(color: AppColors.border),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12))),
        child: const Center(child: Column(children: [
          Icon(Icons.door_front_door_outlined, size: 36, color: AppColors.textSecondary),
          SizedBox(height: 8),
          Text('No rooms found', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ])),
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: AppColors.card,
          border: Border(left: BorderSide(color: AppColors.border),
              right: BorderSide(color: AppColors.border),
              bottom: BorderSide(color: AppColors.border)),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12))),
      child: Column(children: [
        for (final cat in _categories) _buildCatSection(cat),
      ]),
    );
  }

  Widget _buildCatSection(dynamic cat) {
    final name = (cat['category_name'] ?? '').toString();
    final rooms = cat['rooms'] as List? ?? [];
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: const BoxDecoration(color: Color(0xFFEDE9FF),
            border: Border(top: BorderSide(color: Color(0xFFC4B5FD), width: 1.5),
                bottom: BorderSide(color: Color(0xFFC4B5FD)))),
        child: Row(children: [
          const Icon(Icons.layers_outlined, size: 12, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: AppColors.primary, letterSpacing: 0.3)),
          const SizedBox(width: 6),
          Text('(${rooms.length})', style: const TextStyle(
              fontSize: 9, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        ]),
      ),
      for (final r in rooms) _buildRoomRow(r),
    ]);
  }

  Widget _buildRoomRow(dynamic room) {
    final rn = (room['room_number'] ?? '-').toString();
    final bks = room['bookings'] as List? ?? [];
    return Container(
      height: 56,
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
      child: Row(children: [
        Container(width: 70,
            decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.border, width: 1.5))),
            child: Center(child: Text(rn, style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)))),
        Expanded(child: LayoutBuilder(builder: (ctx, c) {
          final tw = c.maxWidth;
          return Stack(children: [
            Row(children: List.generate(_dates.length, (i) {
              final isT = _dates[i] == _today;
              return Expanded(child: Container(decoration: BoxDecoration(
                  color: isT ? const Color(0xFFF7F5FF) : Colors.transparent,
                  border: Border(left: BorderSide(
                      color: AppColors.border.withOpacity(0.4), width: 0.5)))));
            })),
            for (final bk in bks) _buildBar(bk, tw),
          ]);
        })),
      ]),
    );
  }

  Widget _buildBar(dynamic bk, double tw) {
    final lp = (bk['left_pct'] as num?)?.toDouble() ?? 0;
    final wp = (bk['width_pct'] as num?)?.toDouble() ?? 0;
    final st = (bk['status'] ?? 'booked').toString();
    final gn = (bk['guest_name'] ?? '-').toString();
    final ch = (bk['channel'] ?? '').toString();
    final cl = bk['cut_left'] == true; final cr = bk['cut_right'] == true;
    final l = (lp / 100) * tw; final w = (wp / 100) * tw;

    Color bg;
    if (st == 'checkin') bg = const Color(0xFFFDEBEB);
    else if (st == 'checkout') bg = const Color(0xFFB7F9EC);
    else bg = const Color(0xFFEAE4F5);

    return Positioned(left: l, top: 8, child: GestureDetector(
      onTap: () => _showBookingDetail(bk),
      child: Container(
        width: w.clamp(4.0, (tw - l).clamp(4.0, tw)), height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: bg,
            borderRadius: BorderRadius.horizontal(
                left: cl ? Radius.zero : const Radius.circular(6),
                right: cr ? Radius.zero : const Radius.circular(6)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06),
                blurRadius: 4, offset: const Offset(0, 1))]),
        child: Row(children: [
          Expanded(child: Text(gn, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary))),
          if (w > 80 && ch.isNotEmpty)
            Container(margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(3)),
                child: Text(ch.length > 6 ? '${ch.substring(0, 6)}..' : ch,
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary))),
        ]),
      ),
    ));
  }

  // ══════════════════════════════════════════════════════════
  //  BOOKING DETAIL BOTTOM SHEET
  // ══════════════════════════════════════════════════════════

  void _showBookingDetail(dynamic bk) {
    final status = (bk['status'] ?? 'booked').toString();
    final guestName = (bk['guest_name'] ?? '-').toString();
    final phone = (bk['phone'] ?? '').toString();
    final channel = (bk['channel'] ?? '').toString();
    final amount = (bk['amount'] ?? '0').toString();
    final checkin = (bk['checkin'] ?? '').toString();
    final checkout = (bk['checkout'] ?? '').toString();
    final bookingId = (bk['booking_id'] ?? '').toString();
    final bookingRef = (bk['booking_ref'] ?? '').toString();
    final entryId = (bk['entry_id'] ?? '').toString();
    final categoryId = (bk['category_id'] ?? '').toString();

    Color sc; String sl;
    if (status == 'checkin') { sc = const Color(0xFFD63031); sl = 'Checked-In'; }
    else if (status == 'checkout') { sc = const Color(0xFF00B894); sl = 'Checked-Out'; }
    else { sc = AppColors.primary; sl = 'Booked'; }

    showModalBottomSheet(
      context: context, backgroundColor: AppColors.card, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).padding.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(margin: const EdgeInsets.only(bottom: 14), width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          Row(children: [
            Expanded(child: Text(guestName, style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary))),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: sc.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(sl, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sc))),
          ]),
          if (channel.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 2),
                child: Align(alignment: Alignment.centerLeft,
                    child: Text(channel, style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)))),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border)),
            child: Column(children: [
              _dRow('Check-in', _fmtShort(checkin)), const SizedBox(height: 8),
              _dRow('Check-out', _fmtShort(checkout)), const SizedBox(height: 8),
              _dRow('Amount', '\u20B9$amount'),
              if (phone.isNotEmpty) ...[const SizedBox(height: 8), _dRow('Phone', phone)],
              const SizedBox(height: 8), if (bookingRef.isNotEmpty) ...[
    const SizedBox(height: 8),
    _dRow('Booking ID', '#$bookingRef'),
    ],
            ]),
          ),
          const SizedBox(height: 14),

          // ── Actions ──
          if (status == 'booked') ...[
            _aBtn('Check-In', Icons.login_rounded, const Color(0xFFD63031), () {
              Navigator.pop(context);
              _showCheckinDialog(bookingId, entryId, categoryId, checkin, checkout);
            }),
            const SizedBox(height: 8),
            _aBtn('Registration', Icons.assignment_outlined, AppColors.primary, () {
              Navigator.pop(context); _openRegistration(bookingId);
            }),
            const SizedBox(height: 8),
            _aBtn('Details', Icons.info_outline_rounded, const Color(0xFF64748B), () {
              Navigator.pop(context); _openDetails(bookingId, guestName, phone, channel, amount, checkin, checkout, status);;
            }),
          ],
          if (status == 'checkin') ...[
            _aBtn('Check-Out', Icons.logout_rounded, const Color(0xFF00B894), () {
              Navigator.pop(context);
              _confirmAction('Check-Out', 'Check-out $guestName?', () => _doCheckout(bookingId, entryId));
            }),
            const SizedBox(height: 8),
            _aBtn('Change Room', Icons.swap_horiz_rounded, const Color(0xFF4F8DF5), () {
              Navigator.pop(context);
              _showChangeRoomDialog(bookingId, entryId, categoryId, checkin, checkout);
            }),
            const SizedBox(height: 8),
            _aBtn('Registration', Icons.assignment_outlined, AppColors.primary, () {
              Navigator.pop(context); _openRegistration(bookingId);
            }),
            const SizedBox(height: 8),
            _aBtn('Undo Check-In', Icons.undo_rounded, const Color(0xFFF59E0B), () {
              Navigator.pop(context);
              _confirmAction('Undo Check-In', 'Revert to booked?', () => _doUndoCheckin(bookingId, entryId));
            }),
            const SizedBox(height: 8),
            _aBtn('Details', Icons.info_outline_rounded, const Color(0xFF64748B), () {
              Navigator.pop(context); _openDetails(bookingId, guestName, phone, channel, amount, checkin, checkout, status);
            }),
          ],
          if (status == 'checkout') ...[
            _aBtn('Undo Check-Out', Icons.undo_rounded, const Color(0xFFF59E0B), () {
              Navigator.pop(context);
              _confirmAction('Undo Check-Out', 'Revert to checked-in?', () => _doUndoCheckout(bookingId, entryId));
            }),
            const SizedBox(height: 8),
            _aBtn('Registration', Icons.assignment_outlined, AppColors.primary, () {
              Navigator.pop(context); _openRegistration(bookingId);
            }),
            const SizedBox(height: 8),
            _aBtn('Details', Icons.info_outline_rounded, const Color(0xFF64748B), () {
              Navigator.pop(context); _openDetails(bookingId, guestName, phone, channel, amount, checkin, checkout, status);;
            }),
          ],
        ]),
      ),
    );
  }

  Widget _dRow(String l, String v) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(l, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
    Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
  ]);

  Widget _aBtn(String l, IconData ic, Color c, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: c.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withOpacity(0.2))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(ic, size: 16, color: c), const SizedBox(width: 8),
        Text(l, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c)),
      ]),
    ),
  );

  // ══════════════════════════════════════════════════════════
  //  DIALOGS & API CALLS
  // ══════════════════════════════════════════════════════════

  void _confirmAction(String t, String m, VoidCallback onOk) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text(m, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
        TextButton(onPressed: () { Navigator.pop(ctx); onOk(); },
            child: Text('Confirm', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700))),
      ],
    ));
  }

  void _showCheckinDialog(String bid, String eid, String cid, String ci, String co) {
    final today = _apiDate(DateTime.now());
    if (ci != today) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Check-in available only on ${_fmtShort(ci)}')));
      return;
    }
    List<dynamic> rooms = []; bool loading = true; int? selId;
    showDialog(context: context, barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, sd) {
        if (loading) {
          loading = false;
          _fetchRooms(cid, ci, co, eid).then((r) {
            if (ctx.mounted) sd(() { rooms = r; if (r.isNotEmpty) selId = r[0]['id']; });
          });
        }
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Select Room', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: rooms.isEmpty
              ? const SizedBox(height: 40, child: Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
              : _roomDropdown(rooms, selId, (v) => sd(() => selId = v)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
            TextButton(
                onPressed: rooms.isEmpty ? null : () {
                  Navigator.pop(ctx); _doCheckin(bid, eid, (selId ?? rooms[0]['id']).toString());
                },
                child: const Text('Check-In', style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w700))),
          ],
        );
      }),
    );
  }

  void _showChangeRoomDialog(String bid, String eid, String cid, String ci, String co) {
    List<dynamic> rooms = []; bool loading = true; int? selId;
    showDialog(context: context, barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, sd) {
        if (loading) {
          loading = false;
          _fetchRooms(cid, ci, co, eid).then((r) {
            if (ctx.mounted) sd(() { rooms = r; if (r.isNotEmpty) selId = r[0]['id']; });
          });
        }
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Change Room', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: rooms.isEmpty
              ? const SizedBox(height: 40, child: Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
              : _roomDropdown(rooms, selId, (v) => sd(() => selId = v)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
            TextButton(
                onPressed: rooms.isEmpty ? null : () {
                  Navigator.pop(ctx); _doChangeRoom(bid, eid, (selId ?? rooms[0]['id']).toString());
                },
                child: const Text('Change', style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w700))),
          ],
        );
      }),
    );
  }

  Widget _roomDropdown(List<dynamic> rooms, int? sel, void Function(int?) onChange) {
    return DropdownButtonFormField<int>(
      value: sel,
      decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border))),
      items: rooms.map<DropdownMenuItem<int>>((r) {
        final rn = (r['room_number'] ?? '').toString();
        final fl = (r['floor'] ?? '').toString();
        return DropdownMenuItem<int>(value: r['id'] as int,
            child: Text('Room $rn${fl.isNotEmpty ? ' · Floor $fl' : ''}',
                style: const TextStyle(fontSize: 13)));
      }).toList(),
      onChanged: onChange,
    );
  }

  Future<List<dynamic>> _fetchRooms(String cid, String ci, String co, String eid) async {
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.getData(AppConfig.pmsAvailableRooms, query: {
        'user_id': uid, 'cat_id': cid, 'checkin': ci, 'checkout': co,
        'exclude_room_book_id': eid,
      });
      return (res.data['rooms'] as List?) ?? [];
    } catch (e) { print('ROOMS ERROR: $e'); return []; }
  }

  Future<void> _doCheckin(String bid, String eid, String rid) => _api(AppConfig.pmsCheckin,
      {'booking_id': bid, 'room_book_id': eid, 'assigned_room_id': rid}, 'Check-in done');

  Future<void> _doCheckout(String bid, String eid) => _api(AppConfig.pmsCheckout,
      {'booking_id': bid, 'room_book_id': eid}, 'Check-out done');

  Future<void> _doChangeRoom(String bid, String eid, String nid) => _api(AppConfig.pmsChangeRoom,
      {'booking_id': bid, 'room_book_id': eid, 'new_room_id': nid}, 'Room changed');

  Future<void> _doUndoCheckin(String bid, String eid) => _api(AppConfig.pmsUndoCheckin,
      {'booking_id': bid, 'room_book_id': eid}, 'Check-in undone');

  Future<void> _doUndoCheckout(String bid, String eid) => _api(AppConfig.pmsUndoCheckout,
      {'booking_id': bid, 'room_book_id': eid}, 'Check-out undone');

  Future<void> _api(String ep, Map<String, dynamic> body, String ok) async {
    try {
      final uid = await ApiService.instance.getUserId();
      body['user_id'] = uid;
      final res = await ApiService.instance.postData(ep, body);
      if (!mounted) return;
      final s = res.data['success'] == true;
      final m = (res.data['message'] ?? (s ? ok : 'Failed')).toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m),
          backgroundColor: s ? const Color(0xFF00B894) : const Color(0xFFD63031)));
      if (s) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyError(e)), backgroundColor: const Color(0xFFD63031)));
    }
  }

  // ── Details ──
  void _openDetails(String bookingId, String guestName, String phone,
      String channel, String amount, String checkin, String checkout, String status) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BookingDetailScreen(
        booking: {
          'id': int.tryParse(bookingId) ?? 0,
          'guest_name': guestName,
          'phone': phone,
          'channel_name': channel,
          'amount': amount,
          'check_in_date': checkin,
          'check_out_date': checkout,
          'payment_status': status,
        },
      ),
    ));
  }

  // ── Registration Modal ──
  void _openRegistration(String bookingId) async {
    Map<String, dynamic>? regData;
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.getData(AppConfig.pmsRegistration, query: {
        'user_id': uid, 'booking_id': bookingId,
      });
      regData = res.data as Map<String, dynamic>;
    } catch (e) { print('REG LOAD ERROR: $e'); }
    if (!mounted) return;
    showModalBottomSheet(
      context: context, backgroundColor: AppColors.card, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _RegistrationModal(bookingId: bookingId, data: regData, onSaved: _load),
    );
  }

  // ── Shimmer ──
  Widget _buildShimmer() => SingleChildScrollView(
    padding: const EdgeInsets.all(14),
    child: Column(children: [
      const SizedBox(height: 16),
      Row(children: List.generate(4, (_) => Expanded(child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4), height: 60,
          decoration: BoxDecoration(color: AppColors.border.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12)))))),
      const SizedBox(height: 16),
      Container(height: 44, decoration: BoxDecoration(
          color: AppColors.border.withOpacity(0.3), borderRadius: BorderRadius.circular(12))),
      const SizedBox(height: 16),
      ...List.generate(8, (_) => Container(margin: const EdgeInsets.only(bottom: 4), height: 56,
          decoration: BoxDecoration(color: AppColors.border.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4)))),
    ]),
  );

  // ── Error ──
  Widget _buildError() => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.wifi_off_rounded, size: 40, color: AppColors.textSecondary),
    const SizedBox(height: 12),
    const Text('No internet connection', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
    const SizedBox(height: 12),
    GestureDetector(onTap: _load, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
        child: const Text('Retry', style: TextStyle(color: Colors.white,
            fontWeight: FontWeight.w600, fontSize: 13)))),
  ],
  ));
}

// ══════════════════════════════════════════════════════════
//  REGISTRATION MODAL
// ══════════════════════════════════════════════════════════

class _RegistrationModal extends StatefulWidget {
  final String bookingId;
  final Map<String, dynamic>? data;
  final VoidCallback onSaved;
  const _RegistrationModal({required this.bookingId, this.data, required this.onSaved});
  @override
  State<_RegistrationModal> createState() => _RegistrationModalState();
}

class _RegistrationModalState extends State<_RegistrationModal> {
  final _nameC = TextEditingController();
  final _phoneC = TextEditingController();
  final _emailC = TextEditingController();
  final _idNumC = TextEditingController();
  final _fromC = TextEditingController();
  final _toC = TextEditingController();
  final _purposeC = TextEditingController();
  final _vehicleC = TextEditingController();
  final _addressC = TextEditingController();
  final _remarksC = TextEditingController();
  String _idType = '';
  int _male = 0, _female = 0, _children = 0;
  List<Map<String, dynamic>> _addGuests = [];
  List<dynamic> _rooms = [];
  bool _saving = false, _isEdit = false;

  static const _idTypes = [
    {'value': '', 'label': '-- Select --'},
    {'value': 'aadhaar', 'label': 'Aadhaar Card'},
    {'value': 'pan', 'label': 'PAN Card'},
    {'value': 'driving', 'label': 'Driving License'},
    {'value': 'passport', 'label': 'Passport'},
    {'value': 'voter', 'label': 'Voter ID'},
  ];

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    if (d != null) {
      _isEdit = d['exists'] == true;
      _nameC.text = (d['guest_name'] ?? '').toString();
      _phoneC.text = (d['phone'] ?? '').toString();
      _emailC.text = (d['email'] ?? '').toString();
      _idType = (d['id_type'] ?? '').toString();
      _idNumC.text = (d['id_number'] ?? '').toString();
      _male = (d['male_count'] as num?)?.toInt() ?? 0;
      _female = (d['female_count'] as num?)?.toInt() ?? 0;
      _children = (d['children_count'] as num?)?.toInt() ?? 0;
      _fromC.text = (d['from_location'] ?? '').toString();
      _toC.text = (d['to_location'] ?? '').toString();
      _purposeC.text = (d['purpose_of_visit'] ?? '').toString();
      _vehicleC.text = (d['vehicle_number'] ?? '').toString();
      _addressC.text = (d['address'] ?? '').toString();
      _remarksC.text = (d['remarks'] ?? '').toString();
      _rooms = (d['rooms'] as List?) ?? [];
      _addGuests = ((d['additional_guests'] as List?) ?? [])
          .map((g) => Map<String, dynamic>.from(g as Map)).toList();
    }
  }

  @override
  void dispose() {
    for (final c in [_nameC,_phoneC,_emailC,_idNumC,_fromC,_toC,_purposeC,_vehicleC,_addressC,_remarksC]) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameC.text.trim().isEmpty) { _msg('Guest name required'); return; }
    if (_phoneC.text.trim().isEmpty) { _msg('Phone required'); return; }
    if (_idType.isEmpty) { _msg('ID type required'); return; }
    if (_idNumC.text.trim().isEmpty) { _msg('ID number required'); return; }
    setState(() => _saving = true);
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(AppConfig.pmsRegistrationSave, {
        'user_id': uid, 'booking_id': widget.bookingId,
        'guest_name': _nameC.text.trim(), 'phone': _phoneC.text.trim(),
        'email': _emailC.text.trim(), 'id_type': _idType,
        'id_number': _idNumC.text.trim(),
        'male_count': _male, 'female_count': _female, 'children_count': _children,
        'from_location': _fromC.text.trim(), 'to_location': _toC.text.trim(),
        'purpose_of_visit': _purposeC.text.trim(), 'address': _addressC.text.trim(),
        'vehicle_number': _vehicleC.text.trim(), 'remarks': _remarksC.text.trim(),
        'additional_guests': _addGuests.where((g) => (g['name'] ?? '').toString().trim().isNotEmpty).toList(),
      });
      if (!mounted) return;
      if (res.data['success'] == true) {
        Navigator.pop(context); widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text((res.data['message'] ?? 'Saved').toString()),
            backgroundColor: const Color(0xFF00B894)));
      } else { _msg((res.data['message'] ?? 'Failed').toString()); }
    } catch (e) { _msg(friendlyError(e)); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final bp = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bp),
      child: SizedBox(height: MediaQuery.of(context).size.height * 0.85,
        child: Column(children: [
          Container(margin: const EdgeInsets.only(top: 12, bottom: 6), width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(children: [
                const Icon(Icons.assignment_outlined, color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Guest Registration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(_isEdit ? 'Edit Registration' : 'New Registration',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ])),
                if (_rooms.isNotEmpty) Wrap(spacing: 4, children: _rooms.map((r) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(6)),
                  child: Text('Room ${r['room_number']}', style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary)),
                )).toList()),
              ])),
          const Divider(height: 1),
          Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 20), children: [
            _sec('Guest Information'),
            _tf('Guest Name *', _nameC), _tf('Phone *', _phoneC, kb: TextInputType.phone),
            _tf('Email', _emailC, kb: TextInputType.emailAddress),
            _dd('ID Type *', _idType, _idTypes, (v) => setState(() => _idType = v)),
            _tf('ID Number *', _idNumC),
            const SizedBox(height: 20), _sec('Occupancy'),
            Row(children: [
              _cnt('Male', _male, (v) => setState(() => _male = v)),
              const SizedBox(width: 10),
              _cnt('Female', _female, (v) => setState(() => _female = v)),
              const SizedBox(width: 10),
              _cnt('Children', _children, (v) => setState(() => _children = v)),
              const SizedBox(width: 10),
              _cnt('Total', _male + _female + _children, null, ro: true),
            ]),
            const SizedBox(height: 20), _sec('Journey & Purpose'),
            _tf('Coming From', _fromC), _tf('Going To', _toC),
            _tf('Purpose', _purposeC), _tf('Vehicle No.', _vehicleC),
            _tf('Address', _addressC, ml: 2), _tf('Remarks', _remarksC, ml: 2),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: _sec('Additional Guests')),
              GestureDetector(
                onTap: () => setState(() => _addGuests.add(
                    {'name':'','age':'','gender':'','relation':'','id_type':'','id_number':''})),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(6)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add, size: 14, color: AppColors.primary), SizedBox(width: 4),
                    Text('Add', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            if (_addGuests.isEmpty) const Text('No additional guests',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            for (int i = 0; i < _addGuests.length; i++) _guestCard(i),
          ])),
          Container(
            padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: AppColors.background,
                        borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                    child: const Center(child: Text('Cancel', style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
              )),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: GestureDetector(
                onTap: _saving ? null : _save,
                child: Container(padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                    child: Center(child: _saving
                        ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_isEdit ? 'Update' : 'Save Registration',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)))),
              )),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _sec(String t) => Padding(padding: const EdgeInsets.only(bottom: 10),
      child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary, letterSpacing: 0.3)));

  Widget _tf(String l, TextEditingController c, {TextInputType? kb, int ml = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      TextField(controller: c, keyboardType: kb, maxLines: ml, style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary)))),
    ]),
  );

  Widget _dd(String l, String v, List<Map<String, String>> items, void Function(String) onChange) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(value: v.isEmpty ? '' : v, isDense: true,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border))),
          items: items.map((e) => DropdownMenuItem(value: e['value'], child: Text(e['label']!, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) => onChange(v ?? '')),
    ]),
  );

  Widget _cnt(String l, int v, void Function(int)? onChange, {bool ro = false}) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8), color: ro ? AppColors.background : null),
          child: ro
              ? Center(child: Text('$v', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)))
              : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            GestureDetector(onTap: v > 0 ? () => onChange!(v - 1) : null,
                child: Icon(Icons.remove_circle_outline, size: 18,
                    color: v > 0 ? AppColors.primary : AppColors.border)),
            Text('$v', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            GestureDetector(onTap: () => onChange!(v + 1),
                child: const Icon(Icons.add_circle_outline, size: 18, color: AppColors.primary)),
          ])),
    ]),
  );

  Widget _guestCard(int i) {
    final g = _addGuests[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border)),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text('Guest ${i+1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
          GestureDetector(onTap: () => setState(() => _addGuests.removeAt(i)),
              child: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFD63031))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _mf('Name', g['name'] ?? '', (v) => g['name'] = v)),
          const SizedBox(width: 8),
          SizedBox(width: 50, child: _mf('Age', (g['age'] ?? '').toString(), (v) => g['age'] = v, kb: TextInputType.number)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _mf('Gender', g['gender'] ?? '', (v) => g['gender'] = v)),
          const SizedBox(width: 8),
          Expanded(child: _mf('Relation', g['relation'] ?? '', (v) => g['relation'] = v)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _mf('ID Type', g['id_type'] ?? '', (v) => g['id_type'] = v)),
          const SizedBox(width: 8),
          Expanded(child: _mf('ID No.', g['id_number'] ?? '', (v) => g['id_number'] = v)),
        ]),
      ]),
    );
  }

  Widget _mf(String h, String v, void Function(String) onChange, {TextInputType? kb}) => TextField(
    controller: TextEditingController(text: v), keyboardType: kb,
    style: const TextStyle(fontSize: 12), onChanged: onChange,
    decoration: InputDecoration(isDense: true, hintText: h,
        hintStyle: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.primary))),
  );
}