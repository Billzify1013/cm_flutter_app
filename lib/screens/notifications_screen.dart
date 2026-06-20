import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';
import '../widgets/channel_avatar.dart';
import 'booking_detail_screen.dart';
import '../core/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  String _errorMsg = '';
  List<dynamic> _all = [];
  String _channel = 'All';
  String _tag = 'All';
  String _room = 'All';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  void initState() {
    super.initState();
    _load();
    NotificationService.instance.clearUnread();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMsg = '';
    });
    try {
      final uid = await ApiService.instance.getUserId();
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final res = await ApiService.instance
          .postData(AppConfig.notifyBookings, {'user_id': uid, 'date': today});
      if (!mounted) return;
      setState(() {
        _all = (res.data['arrivals'] as List?) ?? [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _all = [];
        _errorMsg = friendlyError(e);
        _loading = false;
      });
    }
  }

  Map<String, int> _countsBy(String Function(dynamic) keyOf) {
    final m = <String, int>{};
    for (final b in _all) {
      final k = keyOf(b);
      if (k.isNotEmpty) m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }

  Map<String, int> get _channelCounts =>
      _countsBy((b) => (b['channel_name'] ?? 'Unknown').toString());

  Map<String, int> get _roomCounts =>
      _countsBy((b) => (b['room_category'] ?? '').toString());

  Map<String, int> get _tagCounts {
    final m = <String, int>{};
    for (final b in _all) {
      final status = (b['status'] ?? '').toString().trim();
      final pay = (b['payment_status'] ?? '').toString().trim();
      for (final t in {status, pay}) {
        if (t.isNotEmpty) m[t] = (m[t] ?? 0) + 1;
      }
    }
    return m;
  }

  List<dynamic> get _filtered {
    return _all.where((b) {
      final c = (b['channel_name'] ?? 'Unknown').toString();
      final status = (b['status'] ?? '').toString();
      final pay = (b['payment_status'] ?? '').toString();
      final room = (b['room_category'] ?? '').toString();
      final cOk = _channel == 'All' || c == _channel;
      final tOk = _tag == 'All' || status == _tag || pay == _tag;
      final rOk = _room == 'All' || room == _room;
      return cOk && tOk && rOk;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final hasRooms = _roomCounts.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recent bookings',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(
          child: CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 2.5))
          : Column(
        children: [
          _filterRow('By channel', [
            _chip('All', _all.length, _channel == 'All',
                    () => setState(() => _channel = 'All')),
            ..._channelCounts.entries.map((e) => _chip(e.key, e.value,
                _channel == e.key, () => setState(() => _channel = e.key))),
          ]),
          if (hasRooms)
            _filterRow('Room category', [
              _chip('All', _all.length, _room == 'All',
                      () => setState(() => _room = 'All')),
              ..._roomCounts.entries.map((e) => _chip(e.key, e.value,
                  _room == e.key, () => setState(() => _room = e.key))),
            ]),
          _filterRow('Status / Payment', [
            _chip('All', _all.length, _tag == 'All',
                    () => setState(() => _tag = 'All')),
            ..._tagCounts.entries.map((e) => _chip(e.key, e.value,
                _tag == e.key, () => setState(() => _tag = e.key))),
          ]),
          const SizedBox(height: 6),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: _filtered.isEmpty
                  ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 60),
                  Center(
                      child: Text(
                          _errorMsg.isNotEmpty
                              ? _errorMsg
                              : 'No bookings found',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.textSecondary))),
                ],
              )
                  : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                itemCount: _filtered.length,
                itemBuilder: (ctx, i) => _bookingCard(_filtered[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterRow(String title, List<Widget> chips) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(scrollDirection: Axis.horizontal, children: chips),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, int count, bool sel, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: sel ? AppColors.accentSoft : AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: sel ? AppColors.primary : AppColors.border,
                width: sel ? 1.4 : 1),
          ),
          child: Text('$label  $count',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ),
      ),
    );
  }

  Widget _bookingCard(dynamic g) {
    final name = (g['guest_name'] ?? '-').toString();
    final channel = (g['channel_name'] ?? '').toString();
    final phone = (g['phone'] ?? '').toString();
    final amount = g['amount']?.toString() ?? '0';
    final pay = (g['payment_status'] ?? '').toString();
    final status = (g['status'] ?? '').toString();
    final room = (g['room_category'] ?? '').toString();
    final id = (g['booking_ref'] ?? '').toString();
    final ci = _fmtDate(g['check_in_date']?.toString());
    final co = _fmtDate(g['check_out_date']?.toString());

    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final hasPhone = cleanPhone.isNotEmpty &&
        cleanPhone.replaceAll(RegExp(r'[0+]'), '').isNotEmpty;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => BookingDetailScreen(
              booking: Map<String, dynamic>.from(g as Map)))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 12,
                offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChannelAvatar(channel: channel, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                      if (id.isNotEmpty)
                        Text('#$id',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('$ci  →  $co',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (room.isNotEmpty)
                        _badge(room, AppColors.accentSoft, AppColors.primary),
                      if (pay.isNotEmpty) _paymentBadge(pay),
                      if (status.isNotEmpty) _statusBadge(status),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('\u20B9$amount',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                if (hasPhone) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _call(phone),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(Icons.call,
                          color: AppColors.primary, size: 17),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
      BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style:
          TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _paymentBadge(String status) {
    final s = status.toLowerCase();
    if (s.contains('partial')) {
      return _badge(status, const Color(0xFFE0F7F7), const Color(0xFF0E8A8A));
    }
    if (s.contains('post')) {
      return _badge(status, const Color(0xFFFEF6DC), const Color(0xFF9A7B0A));
    }
    if (s.contains('pre') || s.contains('paid') || s.contains('full')) {
      return _badge(status, AppColors.successSoft, AppColors.success);
    }
    return _badge(status, AppColors.accentSoft, AppColors.primary);
  }

  Widget _statusBadge(String status) {
    final s = status.toLowerCase();
    if (s.contains('cancel')) {
      return _badge(status, const Color(0xFFFDE7E7), const Color(0xFFC0392B));
    }
    if (s.contains('modif')) {
      return _badge(status, const Color(0xFFE7EEFD), const Color(0xFF2A57C0));
    }
    return _badge(status, AppColors.accentSoft, AppColors.primary);
  }

  Future<void> _call(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (clean.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: clean));
    } catch (_) {}
  }

  String _fmtDate(String? s) {
    if (s == null || s.isEmpty) return '';
    try {
      final part = s.split('T')[0].split('-');
      final m = int.parse(part[1]);
      final d = int.parse(part[2]);
      return '${d.toString().padLeft(2, '0')} ${_months[m - 1]}';
    } catch (_) {
      return s;
    }
  }
}