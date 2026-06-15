import 'package:flutter/material.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';
import '../widgets/channel_avatar.dart';
import 'booking_detail_screen.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});
  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  bool _searchMode = false;
  int _searchType = 0;
  final _searchCtrl = TextEditingController();
  DateTime? _dateFrom;
  DateTime? _dateTo;

  bool _loading     = false;
  bool _loadingMore = false;
  bool _hasMore     = false;
  int  _offset      = 0;
  Map<String, dynamic> _lastBody = {};

  List<dynamic> _results = [];
  String _subtitle       = '';
  String _filterChannel  = 'All';
  String _filterTag      = 'All';

  final ScrollController _scrollCtrl = ScrollController();

  static const _typeLabels = ['Guest', 'Phone', 'Booking ID', 'Date'];
  static const _typeKeys   = ['guest', 'phone', 'booking_id', 'date_range'];
  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  @override
  void initState() {
    super.initState();
    _loadDefault();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      if (_hasMore && !_loadingMore) _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final body = Map<String, dynamic>.from(_lastBody);
      body['offset'] = _offset;
      final res = await ApiService.instance.postData(
          AppConfig.searchBooking, body);
      if (!mounted) return;
      final newList = (res.data['bookings'] as List?) ?? [];
      setState(() {
        _results.addAll(newList);
        _offset  += newList.length;
        _hasMore  = newList.length == 50;
        _subtitle = '${_results.length}${_hasMore ? '+' : ''} results';
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _apiDate(DateTime d) =>
      '${d.year.toString().padLeft(4,'0')}-'
          '${d.month.toString().padLeft(2,'0')}-'
          '${d.day.toString().padLeft(2,'0')}';

  String _prettyDate(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')} ${_months[d.month-1]}';

  Future<void> _loadDefault() async {
    setState(() {
      _loading = true; _results = [];
      _filterChannel = 'All'; _filterTag = 'All';
      _offset = 0; _hasMore = false;
    });
    final now  = DateTime.now();
    final from = now.subtract(const Duration(days: 3));
    final to   = now.add(const Duration(days: 3));
    try {
      final uid = await ApiService.instance.getUserId();
      _lastBody = {
        'user_id':     uid,
        'search_type': 'date_range',
        'date_from':   _apiDate(from),
        'date_to':     _apiDate(to),
      };
      final res = await ApiService.instance.postData(
          AppConfig.searchBooking, _lastBody);
      if (!mounted) return;
      final list = (res.data['bookings'] as List?) ?? [];
      setState(() {
        _results  = list;
        _offset   = list.length;
        _hasMore  = list.length == 50;
        _subtitle = '${_prettyDate(from)} – ${_prettyDate(to)}'
            '  (${_results.length}${_hasMore ? '+' : ''} bookings)';
        _loading  = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _subtitle = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _search() async {
    FocusScope.of(context).unfocus();
    final uid  = await ApiService.instance.getUserId();
    final body = <String, dynamic>{'user_id': uid};

    if (_searchType == 3) {
      if (_dateFrom == null && _dateTo == null) {
        _msg('Pick at least one date'); return;
      }
      body['search_type'] = 'date_range';
      if (_dateFrom != null) body['date_from'] = _apiDate(_dateFrom!);
      if (_dateTo   != null) body['date_to']   = _apiDate(_dateTo!);
    } else {
      final q = _searchCtrl.text.trim();
      if (q.length < 2) { _msg('Type at least 2 characters'); return; }
      body['search_type']  = _typeKeys[_searchType];
      body['search_query'] = q;
    }

    setState(() {
      _loading = true; _filterChannel = 'All';
      _filterTag = 'All'; _offset = 0; _hasMore = false;
    });

    try {
      _lastBody = body;
      final res = await ApiService.instance.postData(
          AppConfig.searchBooking, body);
      if (!mounted) return;
      final list = (res.data['bookings'] as List?) ?? [];
      setState(() {
        _results  = list;
        _offset   = list.length;
        _hasMore  = list.length == 50;
        _subtitle = '${list.length}${list.length == 50 ? '+' : ''} results found';
        _loading  = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _subtitle = friendlyError(e); _loading = false; });
    }
  }

  void _toggleSearch() {
    setState(() {
      _searchMode = !_searchMode;
      if (!_searchMode) {
        _searchCtrl.clear();
        _dateFrom = null; _dateTo = null;
        _loadDefault();
      } else {
        _results = []; _offset = 0; _hasMore = false;
        _subtitle     = 'Search by guest, phone, booking ID or date';
        _filterChannel = 'All'; _filterTag = 'All';
      }
    });
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _dateFrom : _dateTo) ?? DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime(2030),
    );
    if (picked != null)
      setState(() => isFrom ? _dateFrom = picked : _dateTo = picked);
  }

  void _openDetail(dynamic g) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BookingDetailScreen(
            booking: Map<String, dynamic>.from(g as Map))));
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m)));

  Map<String, int> get _channelCounts {
    final m = <String, int>{};
    for (final b in _results) {
      final c = (b['channel_name'] ?? 'Unknown').toString();
      m[c] = (m[c] ?? 0) + 1;
    }
    return m;
  }

  Map<String, int> get _tagCounts {
    final m = <String, int>{};
    for (final b in _results) {
      final s = (b['status'] ?? '').toString().trim();
      final p = (b['payment_status'] ?? '').toString().trim();
      for (final t in {s, p}) {
        if (t.isNotEmpty) m[t] = (m[t] ?? 0) + 1;
      }
    }
    return m;
  }

  List<dynamic> get _filtered {
    return _results.where((b) {
      final c = (b['channel_name'] ?? 'Unknown').toString();
      final s = (b['status'] ?? '').toString();
      final p = (b['payment_status'] ?? '').toString();
      return (_filterChannel == 'All' || c == _filterChannel) &&
          (_filterTag == 'All' || s == _filterTag || p == _filterTag);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookings',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
              icon: Icon(_searchMode ? Icons.close : Icons.search,
                  color: AppColors.textPrimary),
              onPressed: _toggleSearch),
        ],
      ),
      body: Column(children: [

        // ── Search bar ──
        if (_searchMode) Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 0, 6),
            child: SizedBox(
              height: 34,
              child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _typeLabels.length,
                  itemBuilder: (ctx, i) => _typeChip(i)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: _searchType == 3
                ? Row(children: [
              Expanded(child: _dateBox(
                  'From', _dateFrom, () => _pickDate(true))),
              const SizedBox(width: 8),
              Expanded(child: _dateBox(
                  'To', _dateTo, () => _pickDate(false))),
              const SizedBox(width: 8),
              InkWell(
                onTap: _search,
                customBorder: const CircleBorder(),
                child: Container(
                    width: 42, height: 42,
                    decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle),
                    child: const Icon(Icons.search,
                        color: Colors.white, size: 20)),
              ),
            ])
                : TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              keyboardType: _searchType == 1
                  ? TextInputType.phone : TextInputType.text,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: _searchType == 1
                    ? 'Enter phone number'
                    : _searchType == 2
                    ? 'Enter booking ID'
                    : 'Enter guest name',
                isDense: true,
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textSecondary),
                suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward,
                        color: AppColors.primary),
                    onPressed: _search),
              ),
            ),
          ),
        ]),

        // ── Subtitle ──
        if (_subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(children: [
              if (!_searchMode) ...[
                Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(20)),
                    child: const Text('Recent & Upcoming',
                        style: TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary))),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(_subtitle,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary))),
            ]),
          ),

        // ── Filters ──
        if (_results.isNotEmpty) ...[
          _filterRow([
            _filterChip('All', _results.length, _filterChannel == 'All',
                    () => setState(() => _filterChannel = 'All')),
            ..._channelCounts.entries.map((e) => _filterChip(
                e.key, e.value, _filterChannel == e.key,
                    () => setState(() => _filterChannel = e.key))),
          ]),
          _filterRow([
            _filterChip('All', _results.length, _filterTag == 'All',
                    () => setState(() => _filterTag = 'All')),
            ..._tagCounts.entries.map((e) => _filterChip(
                e.key, e.value, _filterTag == e.key,
                    () => setState(() => _filterTag = e.key))),
          ]),
        ],

        // ── List ──
        Expanded(child: RefreshIndicator(
          onRefresh: _searchMode ? _search : _loadDefault,
          color: AppColors.primary,
          child: _loading
              ? const Center(child: CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 2.5))
              : filtered.isEmpty
              ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 60),
                Center(child: Text(
                    _searchMode
                        ? 'Search to see results'
                        : 'No bookings in this range',
                    style: const TextStyle(
                        color: AppColors.textSecondary))),
              ])
              : ListView.builder(
              controller: _scrollCtrl,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: filtered.length + (_loadingMore ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == filtered.length) {
                  return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary)));
                }
                return _bookingCard(filtered[i]);
              }),
        )),
      ]),
    );
  }

  Widget _filterRow(List<Widget> chips) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 0, 0),
      child: SizedBox(height: 34,
          child: ListView(scrollDirection: Axis.horizontal, children: chips)));

  Widget _filterChip(String label, int count, bool sel, VoidCallback onTap) =>
      Padding(
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
                          width: sel ? 1.4 : 1)),
                  child: Text('$label  $count',
                      style: const TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)))));

  Widget _typeChip(int i) {
    final sel = _searchType == i;
    return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
            onTap: () => setState(() => _searchType = i),
            child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                    color: sel ? AppColors.accentSoft : AppColors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: sel ? AppColors.primary : AppColors.border,
                        width: sel ? 1.4 : 1)),
                child: Text(_typeLabels[i],
                    style: TextStyle(fontSize: 12,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                        color: AppColors.textPrimary)))));
  }

  Widget _dateBox(String label, DateTime? value, VoidCallback onTap) =>
      GestureDetector(
          onTap: onTap,
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border)),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(
                    value == null ? label
                        : '${value.day.toString().padLeft(2,'0')} ${_months[value.month-1]}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12,
                        color: value == null
                            ? AppColors.textSecondary : AppColors.textPrimary))),
              ])));

  Widget _bookingCard(dynamic g) {
    final name    = (g['guest_name'] ?? '-').toString();
    final channel = (g['channel_name'] ?? '').toString();
    final amount  = g['amount']?.toString() ?? '0';
    final pay     = (g['payment_status'] ?? '').toString();
    final status  = (g['status'] ?? '').toString();
    final id      = (g['booking_ref'] ?? '').toString();
    final ci      = _fmtDate(g['check_in_date']?.toString());
    final co      = _fmtDate(g['check_out_date']?.toString());

    return GestureDetector(
      onTap: () => _openDetail(g),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Row(children: [
          ChannelAvatar(channel: channel, size: 44),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14))),
              if (id.isNotEmpty)
                Text('#$id', style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
            ]),
            const SizedBox(height: 2),
            Text('$ci  →  $co', style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (pay.isNotEmpty) _payBadge(pay),
              if (status.isNotEmpty) _statusBadge(status),
            ]),
          ])),
          const SizedBox(width: 8),
          Text('₹$amount', style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
      ),
    );
  }

  Widget _badge(String t, Color bg, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(t, style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.w600, color: fg)));

  Widget _payBadge(String s) {
    final l = s.toLowerCase();
    if (l.contains('partial'))
      return _badge(s, const Color(0xFFE0F7F7), const Color(0xFF0E8A8A));
    if (l.contains('post'))
      return _badge(s, const Color(0xFFFEF6DC), const Color(0xFF9A7B0A));
    if (l.contains('pre') || l.contains('paid') || l.contains('full'))
      return _badge(s, AppColors.successSoft, AppColors.success);
    return _badge(s, AppColors.accentSoft, AppColors.primary);
  }

  Widget _statusBadge(String s) {
    final l = s.toLowerCase();
    if (l.contains('cancel'))
      return _badge(s, const Color(0xFFFDE7E7), const Color(0xFFC0392B));
    if (l.contains('modif'))
      return _badge(s, const Color(0xFFE7EEFD), const Color(0xFF2A57C0));
    return _badge(s, AppColors.accentSoft, AppColors.primary);
  }

  String _fmtDate(String? s) {
    if (s == null || s.isEmpty) return '';
    try {
      final p = s.split('T')[0].split('-');
      return '${p[2].padLeft(2,'0')} ${_months[int.parse(p[1])-1]}';
    } catch (_) { return s; }
  }
}