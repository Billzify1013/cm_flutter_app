import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';
import '../widgets/channel_avatar.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'booking_room_select_screen.dart';
import 'bookings_screen.dart';
import 'inventory_screen.dart';
import 'bulk_update_screen.dart';
import 'booking_detail_screen.dart';
import 'purchase_expense_screen.dart';
import 'sales_report_screen.dart';
import 'ota_commission_screen.dart';
import 'detailed_sales_report_screen.dart';
import 'profile_screen.dart';
import 'accounts_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'stay_view_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  DateTime _selectedDate = DateTime.now();
  late final DateTime _firstDate;
  bool _checkingAvail = false;

  String _hotelName = 'Loading...';

  static const int _stripDays = 90;
  static const double _itemExtent = 66;
  final ScrollController _dateCtrl = ScrollController();

  bool _loading = false;
  bool _netError = false;
  List<dynamic> _arrivals = [];
  List<dynamic> _departures = [];
  int _available = 0;
  int _filter = 0;

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];
  static const _weekdays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

  String _apiDate(DateTime d) =>
      '${d.year.toString().padLeft(4,'0')}-'
          '${d.month.toString().padLeft(2,'0')}-'
          '${d.day.toString().padLeft(2,'0')}';

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  int _indexOf(DateTime d) => d.difference(_firstDate).inDays;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _firstDate = DateTime.now().subtract(const Duration(days: 30));
    _load();
    _loadHotelName();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  Future<void> _loadHotelName() async {
    try {
      final name = await ApiService.instance.getHotelName();
      print('DASHBOARD LOADING: $name');  // ✅ DEBUG
      if (mounted) {
        setState(() => _hotelName = name ?? 'Hotel');
      }
    } catch (e) {
      print('DASHBOARD ERROR: $e');  // ✅ DEBUG
      if (mounted) {
        setState(() => _hotelName = 'Hotel');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dateCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ApiService.instance.isSessionExpired().then((expired) {
        if (expired && mounted) {
          ApiService.instance.clearTokens();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
                (r) => false,
          );
        }
      });
    }
  }

  void _scrollToSelected() {
    if (!_dateCtrl.hasClients) return;
    final target = (_indexOf(_selectedDate) * _itemExtent) - 120;
    _dateCtrl.animateTo(
      target.clamp(0.0, _dateCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  void _selectDate(DateTime d) {
    final idx = _indexOf(d);
    if (idx < 0 || idx >= _stripDays) return;
    setState(() => _selectedDate = d);
    _load();
    _scrollToSelected();
  }

  Future<List<dynamic>> _safeList(String path, String? uid, String dateStr) async {
    try {
      final res = await ApiService.instance
          .postData(path, {'user_id': uid, 'date': dateStr});
      return (res.data['arrivals'] as List?) ?? [];
    } catch (e) {
      if (isNetworkError(e)) _netError = true;
      return [];
    }
  }

  Future<int> _fetchAvailable(String? uid, String dateStr) async {
    try {
      final res = await ApiService.instance.getData(
        AppConfig.inventory,
        query: {'user_id': uid, 'start_date': dateStr, 'end_date': dateStr},
      );
      int total = 0;
      final updates = (res.data['updates'] as List?) ?? [];
      for (final u in updates) {
        for (final r in (u['rooms'] as List?) ?? []) {
          total += (r['available'] as num?)?.toInt() ?? 0;
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _netError = false; });
    final uid = await ApiService.instance.getUserId();
    final dateStr = _apiDate(_selectedDate);
    final results = await Future.wait([
      _safeList(AppConfig.todayArrivals, uid, dateStr),
      _safeList(AppConfig.departures, uid, dateStr),
      _fetchAvailable(uid, dateStr),
    ]);
    if (!mounted) return;
    setState(() {
      _arrivals = results[0] as List;
      _departures = results[1] as List;
      _available = results[2] as int;
      _loading = false;
    });
  }

  Future<void> _logout() async {
    await ApiService.instance.clearTokens();

    // ✅ Hotel name bhi clear kar
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('hotel_name');

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (r) => false,
    );
  }

  Future<void> _call(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (clean.isEmpty) return;
    try { await launchUrl(Uri(scheme: 'tel', path: clean)); } catch (_) {}
  }

  void _openDetail(dynamic g) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BookingDetailScreen(
          booking: Map<String, dynamic>.from(g as Map)),
    ));
  }

  // ── Booking picker ──
  String _fmtBookDate(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')} ${_months[d.month - 1]}';

  String _apiBookDate(DateTime d) =>
      '${d.year}-'
          '${d.month.toString().padLeft(2,'0')}-'
          '${d.day.toString().padLeft(2,'0')}';

  Future<void> _openBookingPicker() async {
    void Function(void Function())? _setDialog;

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          _setDialog = setDialog;
          return _BookingPickerDialog(
            loading: _checkingAvail,
            onConfirm: (ci, co) async {
              _setDialog?.call(() => _checkingAvail = true);
              setState(() => _checkingAvail = true);
              try {
                final uid = await ApiService.instance.getUserId();
                final res = await ApiService.instance.postData(
                  AppConfig.checkBookingDates,
                  {'user_id': uid, 'checkin': _apiBookDate(ci), 'checkout': _apiBookDate(co)},
                );
                if (!mounted) return;
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => BookingRoomSelectScreen(
                    bookingData: Map<String, dynamic>.from(res.data as Map),
                    checkin: ci, checkout: co,
                  ),
                ));
              } catch (e) {
                if (!mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(friendlyError(e))));
              } finally {
                if (mounted) {
                  setState(() => _checkingAvail = false);
                  _setDialog?.call(() => _checkingAvail = false);
                }
              }
            },
          );
        },
      ),
    );
  }

  Future<void> _doCheckAvail(DateTime ci, DateTime co) async {
    setState(() => _checkingAvail = true);
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(
        AppConfig.checkBookingDates,
        {'user_id': uid, 'checkin': _apiBookDate(ci), 'checkout': _apiBookDate(co)},
      );
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BookingRoomSelectScreen(
          bookingData: Map<String, dynamic>.from(res.data as Map),
          checkin: ci,
          checkout: co,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _checkingAvail = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.asset('assets/images/plogo.png', width: 120),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 140,
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 10),  // ✅ 30 kar diya
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: AppColors.accentSoft,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(
                                  Icons.person_rounded,
                                  size: 14,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _hotelName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: IconButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const NotificationsScreen())),
                      icon: const Icon(Icons.notifications_none_rounded,
                          color: AppColors.textPrimary, size: 26),
                    ),
                  ),
                ],
              ),
            ),
            _dateStrip(),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(children: [
                _statCard(
                    icon: Icons.flight_land,
                    label: 'Arrivals',
                    value: _loading ? '–' : '${_arrivals.length}',
                    active: _filter == 1,
                    accentColor: const Color(0xFF9B8FE8), // Lavender
                    onTap: () => setState(() => _filter = _filter == 1 ? 0 : 1)),
                const SizedBox(width: 10),
                _statCard(
                    icon: Icons.flight_takeoff,
                    label: 'Departures',
                    value: _loading ? '–' : '${_departures.length}',
                    active: _filter == 2,
                    accentColor: const Color(0xFFF4A5A5), // Coral
                    onTap: () => setState(() => _filter = _filter == 2 ? 0 : 2)),
                const SizedBox(width: 10),
                _statCard(
                    icon: Icons.bed_outlined,
                    label: 'Available',
                    value: _loading ? '–' : '$_available',
                    accentColor: const Color(0xFF4FB8A1)), // Mint green
              ]),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: AppColors.primary,
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _bottomNav(),
    );
  }

  List<dynamic> _rows() {
    final rows = <dynamic>[];
    final showA = _filter == 0 || _filter == 1;
    final showD = _filter == 0 || _filter == 2;
    if (showA) {
      rows.add({'_h': 'Arrivals', '_c': _arrivals.length});
      if (_arrivals.isEmpty) {
        rows.add({'_e': _netError ? 'net' : 'No arrivals on this date'});
      } else {
        rows.addAll(_arrivals);
      }
    }
    if (showD) {
      rows.add({'_h': 'Departures', '_c': _departures.length});
      if (_departures.isEmpty) {
        rows.add({'_e': _netError ? 'net' : 'No departures on this date'});
      } else {
        rows.addAll(_departures);
      }
    }
    return rows;
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(
          color: AppColors.primary, strokeWidth: 2.5));
    }
    final rows = _rows();
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      itemCount: rows.length,
      itemBuilder: (ctx, i) {
        final r = rows[i];
        if (r is Map && r.containsKey('_h')) {
          return _sectionHeader(r['_h'] as String, r['_c'] as int);
        }
        if (r is Map && r.containsKey('_e')) {
          final v = r['_e'] as String;
          return _emptyRow(v == 'net'
              ? 'No internet connection. Please check your network.'
              : v);
        }
        return _guestCard(r);
      },
    );
  }

  Widget _sectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Row(children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(20)),
          child: Text('$count', style: const TextStyle(fontSize: 11,
              fontWeight: FontWeight.w600, color: AppColors.primary)),
        ),
      ]),
    );
  }

  Widget _emptyRow(String msg) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Text(msg, style: const TextStyle(
          color: AppColors.textSecondary, fontSize: 13)));

  Widget _dateStrip() {
    return SizedBox(
      height: 80,
      child: Row(children: [
        _stripArrow(Icons.chevron_left,
                () => _selectDate(_selectedDate.subtract(const Duration(days: 1)))),
        Expanded(
          child: ListView.builder(
            controller: _dateCtrl,
            scrollDirection: Axis.horizontal,
            itemExtent: _itemExtent,
            itemCount: _stripDays,
            itemBuilder: (ctx, i) {
              final d = _firstDate.add(Duration(days: i));
              return _dateCard(d, _sameDay(d, _selectedDate));
            },
          ),
        ),
        _stripArrow(Icons.chevron_right,
                () => _selectDate(_selectedDate.add(const Duration(days: 1)))),
      ]),
    );
  }

  Widget _stripArrow(IconData icon, VoidCallback onTap) => InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(width: 34, height: 80,
          child: Icon(icon, color: AppColors.primary, size: 26)));

  Widget _dateCard(DateTime d, bool sel) {
    return Center(
      child: GestureDetector(
        onTap: () => _selectDate(d),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 54, height: 72,
          decoration: BoxDecoration(
            color: sel ? AppColors.accentSoft : AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: sel ? AppColors.primary : AppColors.border,
                width: sel ? 1.5 : 1),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(_weekdays[d.weekday - 1],
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 3),
            Text(d.day.toString().padLeft(2, '0'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(_months[d.month - 1],
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ]),
        ),
      ),
    );
  }

  Widget _statCard({required IconData icon, required String label,
    required String value, bool active = false, VoidCallback? onTap,
    Color? accentColor}) {
    final color = accentColor ?? AppColors.primary;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: active
                    ? [color.withOpacity(0.20), color.withOpacity(0.06)]
                    : [color.withOpacity(0.10), color.withOpacity(0.02)],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                    color: color.withOpacity(active ? 0.18 : 0.08),
                    blurRadius: active ? 16 : 10,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [color, color.withOpacity(0.75)]),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(
                          color: color.withOpacity(0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2))],
                    ),
                    child: Icon(icon, size: 16, color: Colors.white)),
                const SizedBox(height: 12),
                Text(value, style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary, letterSpacing: -0.5)),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500, letterSpacing: 0.2)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _guestCard(dynamic g) {
    final name = (g['guest_name'] ?? '-').toString();
    final channel = (g['channel_name'] ?? '').toString();
    final phone = (g['phone'] ?? '').toString();
    final amount = g['amount']?.toString() ?? '0';
    final status = (g['payment_status'] ?? '').toString();
    final room = (g['room_category'] ?? '').toString();
    final id = (g['booking_ref'] ?? '').toString();
    final ci = _fmtDate(g['check_in_date']?.toString());
    final co = _fmtDate(g['check_out_date']?.toString());
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final hasPhone = cleanPhone.isNotEmpty &&
        cleanPhone.replaceAll(RegExp(r'[0+]'), '').isNotEmpty;
    final dateRange = (ci.isNotEmpty || co.isNotEmpty) ? '$ci → $co' : '';
    final sub = [if (room.isNotEmpty) room, if (dateRange.isNotEmpty) dateRange].join('  ·  ');

    return GestureDetector(
      onTap: () => _openDetail(g),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Color(0x0A000000),
              blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Row(children: [
          ChannelAvatar(channel: channel, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(name, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                if (id.isNotEmpty)
                  Text('#$id', style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
              ]),
              const SizedBox(height: 3),
              Text(sub.isEmpty ? channel : sub, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('\u20B9$amount', style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            if (status.isNotEmpty) _paymentBadge(status),
          ]),
          if (hasPhone) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: () => _call(phone),
              customBorder: const CircleBorder(),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: AppColors.accentSoft,
                    shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
                child: const Icon(Icons.call, color: AppColors.primary, size: 18),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _paymentBadge(String status) {
    final s = status.toLowerCase();
    Color bg, fg;
    if (s.contains('partial')) { bg = const Color(0xFFE0F7F7); fg = const Color(0xFF0E8A8A); }
    else if (s.contains('post')) { bg = const Color(0xFFFEF6DC); fg = const Color(0xFF9A7B0A); }
    else if (s.contains('pre') || s.contains('paid') || s.contains('full')) {
      bg = AppColors.successSoft; fg = AppColors.success;
    } else { bg = AppColors.accentSoft; fg = AppColors.primary; }
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(status, style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600, color: fg)));
  }

  Widget _bottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, -2))],
      ),
      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _navItem(Icons.home_rounded, 'Home', true, () {}),
        _navItem(Icons.add_circle_outline_rounded, 'Create', false, _openBookingPicker),
        _navItem(Icons.calendar_month_rounded, 'Bookings', false, () {
          Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BookingsScreen()));
        }),
        _navItem(Icons.person_rounded, 'Profile', false, _openProfile),
      ]),
    );
  }

  void _openProfile() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(children: [
          // Drag handle
          Container(
              margin: const EdgeInsets.only(top: 12, bottom: 6),
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.grid_view_rounded,
                      color: AppColors.primary, size: 20)),
              const SizedBox(width: 12),
              const Text('More',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // ── Inventory Section ──
                _menuSection('Inventory'),
                _menuGrid([
                  _menuItem(Icons.tune, 'Inventory\n& Rates', const Color(0xFF6C5CE7), () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const InventoryScreen()));
                  }),
                  _menuItem(Icons.layers_outlined, 'Bulk\nUpdate', const Color(0xFF4F8DF5), () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const BulkUpdateScreen()));
                  }),
                ]),
                const SizedBox(height: 16),


                _menuSection('Room Management'),
                _menuGrid([
                  _menuItem(Icons.calendar_view_week, 'Stay\nView', const Color(0xFF1A2540), () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const StayViewScreen()));
                  }),
                ]),
                const SizedBox(height: 16),

                // ── Finance Section ──
                _menuSection('Finance'),
                _menuGrid([
                  _menuItem(Icons.shopping_bag_outlined, 'Purchase\n& Expense', const Color(0xFFF59E0B), () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const PurchaseExpenseScreen()));
                  }),
                  _menuItem(Icons.account_balance_outlined, 'Accounts\n& GST', const Color(0xFF10B981), () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const AccountsScreen()));
                  }),
                ]),
                const SizedBox(height: 16),

                // ── Reports Section ──
                _menuSection('Reports'),
                _menuGrid([
                  _menuItem(Icons.bar_chart_outlined, 'Sales\nReport', const Color(0xFF8B5CF6), () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => SalesReportScreen()));
                  }),
                  _menuItem(Icons.percent_outlined, 'OTA\nCommission', const Color(0xFFEC4899), () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => OtaCommissionScreen()));
                  }),
                  _menuItem(Icons.assessment_outlined, 'Business\nReport', const Color(0xFF14B8A6), () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => DetailedSalesReportScreen()));
                  }),
                ]),
                const SizedBox(height: 16),

                // ── Settings Section ──
                _menuSection('Settings'),
                _menuGrid([
                  _menuItem(Icons.business_outlined, 'Hotel\nProfile', const Color(0xFF64748B), () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const ProfileScreen()));
                  }),
                ]),
                const SizedBox(height: 24),

                // ── Logout ──
                GestureDetector(
                  onTap: () { Navigator.pop(context); _logout(); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(14)),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout, color: Color(0xFFDC2626), size: 18),
                          SizedBox(width: 8),
                          Text('Logout', style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600,
                              color: Color(0xFFDC2626))),
                        ]),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _menuSection(String title) => Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(title, style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary, letterSpacing: 0.3)));

  Widget _menuGrid(List<Widget> items) => Wrap(
      spacing: 10, runSpacing: 10, children: items);

  Widget _menuItem(IconData icon, String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 80,  // ✅ Fixed narrow width
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          decoration: BoxDecoration(
              color: color.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.12))),
          child: Column(children: [
            Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: Icon(icon, color: color, size: 14)),
            const SizedBox(height: 3),
            Text(label, textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 8,  // ✅ Better text
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary, height: 1.1)),
          ]),
        ),
      );

  Widget _navItem(IconData icon, String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon,
              color: active ? AppColors.primary : AppColors.textSecondary, size: 23),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? AppColors.primary : AppColors.textSecondary)),
      ]),
    );
  }

  String _fmtDate(String? s) {
    if (s == null || s.isEmpty) return '';
    try {
      final part = s.split('T')[0].split('-');
      final m = int.parse(part[1]);
      final d = int.parse(part[2]);
      return '${d.toString().padLeft(2,'0')} ${_months[m - 1]}';
    } catch (_) { return s; }
  }
}

// ── Booking date picker dialog ──
class _BookingPickerDialog extends StatefulWidget {
  final bool loading;
  final void Function(DateTime ci, DateTime co) onConfirm;
  const _BookingPickerDialog({required this.loading, required this.onConfirm});
  @override State<_BookingPickerDialog> createState() => _BookingPickerDialogState();
}

class _BookingPickerDialogState extends State<_BookingPickerDialog> {
  DateTime? _start, _end;
  bool _pickingEnd = false;
  late DateTime _viewMonth;

  static const _months = ['Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'];
  static const _days = ['Mo','Tu','We','Th','Fr','Sa','Su'];

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _viewMonth = DateTime(n.year, n.month, 1);
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')} ${_months[d.month-1]} ${d.year}';

  void _onDay(DateTime day) {
    final today = DateTime.now();
    final todayClean = DateTime(today.year, today.month, today.day);
    if (day.isBefore(todayClean)) return;

    setState(() {
      if (!_pickingEnd) {
        _start = day; _end = null; _pickingEnd = true;
      } else {
        if (day.isBefore(_start!)) {
          _start = day; _end = null;
        } else if (day.isAtSameMomentAs(_start!)) {
          // same day = reset
          _end = null; _pickingEnd = false;
        } else {
          _end = day;
          Future.microtask(() => widget.onConfirm(_start!, _end!));
          _pickingEnd = false;
        }
      }
    });
  }

  bool _inRange(DateTime d) => _start != null && _end != null &&
      d.isAfter(_start!) && d.isBefore(_end!);

  bool _isStart(DateTime d) => _start != null && DateUtils.isSameDay(d, _start!);
  bool _isEnd(DateTime d) => _end != null && DateUtils.isSameDay(d, _end!);

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayClean = DateTime(today.year, today.month, today.day);
    final daysInMonth = DateUtils.getDaysInMonth(_viewMonth.year, _viewMonth.month);
    final firstWd = _viewMonth.weekday; // 1=Mon

    String instruction;
    if (_start == null) instruction = 'Select check-in date';
    else if (_end == null) instruction = 'Now select check-out date';
    else instruction = '${_fmt(_start!)}  →  ${_fmt(_end!)}';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [

          // Header
          Row(children: [
            Expanded(child: Text(
                '${_months[_viewMonth.month-1]} ${_viewMonth.year}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() =>
              _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1, 1)),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() =>
              _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + 1, 1)),
            ),
          ]),

          // Instruction
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: widget.loading
                  ? AppColors.successSoft
                  : (_end != null) ? AppColors.accentSoft : AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.loading
                    ? AppColors.success
                    : (_end != null) ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (widget.loading) ...[
                SizedBox(height: 12, width: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.success)),
                const SizedBox(width: 8),
              ],
              Text(
                  widget.loading ? 'Searching...' : instruction,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: (widget.loading || _end != null)
                        ? FontWeight.w600 : FontWeight.w400,
                    color: widget.loading
                        ? AppColors.success
                        : (_end != null) ? AppColors.primary : AppColors.textSecondary,
                  )),
            ]),
          ),
          const SizedBox(height: 12),

          // Day labels
          Row(children: _days.map((d) => Expanded(
            child: Center(child: Text(d, style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: AppColors.textSecondary))),
          )).toList()),
          const SizedBox(height: 6),

          // Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7, mainAxisSpacing: 3, crossAxisSpacing: 3),
            itemCount: (firstWd - 1) + daysInMonth,
            itemBuilder: (ctx, i) {
              if (i < firstWd - 1) return const SizedBox();
              final day = DateTime(_viewMonth.year, _viewMonth.month, i - (firstWd - 2));
              final isPast = day.isBefore(todayClean);
              final isToday = DateUtils.isSameDay(day, today);
              final isSt = _isStart(day);
              final isEn = _isEnd(day);
              final inR = _inRange(day);

              return GestureDetector(
                onTap: () => _onDay(day),
                child: Container(
                  decoration: BoxDecoration(
                    color: (isSt || isEn) ? AppColors.primary
                        : inR ? AppColors.accentSoft
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('${day.day}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: (isSt || isEn || isToday)
                              ? FontWeight.w700 : FontWeight.w400,
                          color: (isSt || isEn)
                              ? Colors.white
                              : isPast
                              ? AppColors.textSecondary.withOpacity(0.3)
                              : isToday ? AppColors.primary
                              : AppColors.textPrimary,
                        )),
                  ),
                ),
              );
            },
          ),

          if (widget.loading) ...[
            const SizedBox(height: 12),
            const SizedBox(height: 20, width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: AppColors.primary)),
          ],
        ]),
      ),
    );
  }
}