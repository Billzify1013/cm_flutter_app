// OTA Messages — conversation list (same look as the web inbox).
// API: /chat/api/bootstrap/ and /chat/api/conversations/
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_service.dart';
import 'chat_common.dart';
import 'chat_thread_screen.dart';

const _channelChips = ['airbnb', 'booking.com', 'expedia', 'agoda', 'goibibo', 'makemytrip'];

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> with WidgetsBindingObserver {
  // bootstrap
  bool _booting = true;
  String? _bootError;
  bool _canChat = false;
  bool _enabled = false;
  List<Map<String, dynamic>> _properties = [];
  List<Map<String, dynamic>> _listings = [];
  bool _showPropertyFilter = false;

  // list
  final List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _listError;

  // filters
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  bool _unreadOnly = false;
  String? _channel;          // chip row
  String _kind = 'all';      // all | booked | inquiry (filters sheet)
  int? _propertyId;
  int? _listingId;
  String _sort = 'recent';
  DateTime? _date;
  String _dateType = 'staying';

  Timer? _poll;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
    });
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Pause polling while the app is in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh(silent: true);
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _poll?.cancel();
    }
  }

  void _startPolling() {
    _poll?.cancel();
    if (!_enabled) return;
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh(silent: true));
  }

  List<Map<String, dynamic>> _rows(dynamic list) =>
      List<Map<String, dynamic>>.from((list as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));

  Future<void> _boot() async {
    setState(() {
      _booting = true;
      _bootError = null;
    });
    try {
      final res = await ApiService.instance.getData(ChatApi.bootstrap);
      final d = Map<String, dynamic>.from(res.data as Map);
      _canChat = d['can_chat'] == true;
      _enabled = d['enabled'] == true;
      _properties = _rows(d['properties']);
      _listings = _rows(d['listings']);
      _showPropertyFilter = d['show_property_filter'] == true;
      if (!mounted) return;
      setState(() => _booting = false);
      if (_canChat && _enabled) {
        await _refresh();
        _startPolling();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _bootError = chatError(e);
      });
    }
  }

  Map<String, dynamic> _query(int page) {
    final q = <String, dynamic>{'page': page, 'sort': _sort};
    if (_unreadOnly) q['unread'] = 1;
    if (_kind != 'all') q['kind'] = _kind;
    if (_propertyId != null) q['property'] = _propertyId;
    if (_listingId != null) q['listing'] = _listingId;
    if (_channel != null) q['channel'] = _channel;
    final s = _searchCtrl.text.trim();
    if (s.isNotEmpty) q['q'] = s;
    if (_date != null) {
      q['date'] = isoDate(_date!);
      q['date_type'] = _dateType;
    }
    return q;
  }

  /// Reloads page 1. Silent = background refresh (no spinner, keeps errors quiet).
  Future<void> _refresh({bool silent = false}) async {
    if (!_enabled || _loading) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _listError = null;
      });
    }
    try {
      final res = await ApiService.instance.getData(ChatApi.conversations, query: _query(1));
      final d = Map<String, dynamic>.from(res.data as Map);
      final rows = _rows(d['results']);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(rows);
        _page = 1;
        _hasMore = d['has_more'] == true;
        _listError = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) setState(() => _listError = chatError(e));
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final res = await ApiService.instance.getData(ChatApi.conversations, query: _query(_page + 1));
      final d = Map<String, dynamic>.from(res.data as Map);
      final rows = _rows(d['results']);
      if (!mounted) return;
      final seen = _items.map((e) => e['id']).toSet();
      setState(() {
        _items.addAll(rows.where((r) => !seen.contains(r['id'])));
        _page += 1;
        _hasMore = d['has_more'] == true;
      });
    } catch (_) {
      // keep what we have; the user can scroll again
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), _refresh);
    setState(() {});
  }

  /// Filters set in the sheet (the chip row is not counted).
  int get _activeFilterCount {
    var n = 0;
    if (_propertyId != null) n++;
    if (_listingId != null) n++;
    if (_kind != 'all') n++;
    if (_date != null) n++;
    if (_sort != 'recent') n++;
    return n;
  }

  bool get _hasFilters =>
      _activeFilterCount > 0 || _unreadOnly || _channel != null || _searchCtrl.text.trim().isNotEmpty;

  Future<void> _openChat(Map<String, dynamic> c) async {
    // Clear the badge right away; the thread screen marks it read on the server.
    setState(() => c['unread_count'] = 0);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatThreadScreen(conversationId: c['id'] as int, preview: c)),
    );
    if (mounted) _refresh(silent: true);
  }

  // ------------------------------------------------------------ filters sheet
  Future<void> _openFilters() async {
    int? property = _propertyId;
    int? listing = _listingId;
    String kind = _kind;
    String sort = _sort;
    DateTime? day = _date;
    String dateType = _dateType;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Theme(
        data: chatTheme(ctx),
        child: StatefulBuilder(builder: (ctx, setSheet) {
          final listingsShown =
          _listings.where((l) => property == null || l['vendor_id'] == property).toList();
          Widget label(String t) => Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 8),
            child: Text(t,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ChatColors.ink)),
          );
          Widget chip(String text, bool on, VoidCallback tap) => Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 8),
            child: _Pill(text: text, selected: on, onTap: tap),
          );

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(color: ChatColors.line, borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      const Expanded(
                        child: Text('Filters',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ChatColors.ink)),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: ChatColors.ink2),
                        onPressed: () => setSheet(() {
                          property = null;
                          listing = null;
                          kind = 'all';
                          sort = 'recent';
                          day = null;
                          dateType = 'staying';
                        }),
                        child: const Text('Clear all'),
                      ),
                    ]),
                    if (_showPropertyFilter && _properties.length > 1) ...[
                      label('Property'),
                      Wrap(children: [
                        chip('All', property == null, () => setSheet(() {
                          property = null;
                          listing = null;
                        })),
                        for (final p in _properties)
                          chip('${p['name'] ?? 'Property'}', property == p['id'], () => setSheet(() {
                            property = p['id'] as int;
                            listing = null;
                          })),
                      ]),
                    ],
                    if (listingsShown.isNotEmpty) ...[
                      label('Listing'),
                      Wrap(children: [
                        chip('All listings', listing == null, () => setSheet(() => listing = null)),
                        for (final l in listingsShown)
                          chip('${l['label'] ?? 'Listing'}', listing == l['id'],
                                  () => setSheet(() => listing = l['id'] as int)),
                      ]),
                    ],
                    label('Type'),
                    Wrap(children: [
                      chip('All', kind == 'all', () => setSheet(() => kind = 'all')),
                      chip('Booked', kind == 'booked', () => setSheet(() => kind = 'booked')),
                      chip('Inquiries', kind == 'inquiry', () => setSheet(() => kind = 'inquiry')),
                    ]),
                    label('Stay date'),
                    Wrap(children: [
                      chip('Staying', dateType == 'staying', () => setSheet(() => dateType = 'staying')),
                      chip('Check-in', dateType == 'checkin', () => setSheet(() => dateType = 'checkin')),
                      chip('Check-out', dateType == 'checkout', () => setSheet(() => dateType = 'checkout')),
                    ]),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today_outlined, size: 17),
                          label: Text(day == null ? 'Pick a date' : dayLabel(day!)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ChatColors.ink,
                            side: const BorderSide(color: ChatColors.line),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: day ?? now,
                              firstDate: DateTime(now.year - 1),
                              lastDate: DateTime(now.year + 2),
                            );
                            if (picked != null) setSheet(() => day = picked);
                          },
                        ),
                      ),
                      if (day != null)
                        IconButton(
                          tooltip: 'Remove date',
                          icon: const Icon(Icons.close, color: ChatColors.ink3),
                          onPressed: () => setSheet(() => day = null),
                        ),
                    ]),
                    label('Sort by'),
                    Wrap(children: [
                      chip('Newest', sort == 'recent', () => setSheet(() => sort = 'recent')),
                      chip('Oldest', sort == 'oldest', () => setSheet(() => sort = 'oldest')),
                      chip('Unread first', sort == 'unread', () => setSheet(() => sort = 'unread')),
                    ]),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: ChatColors.ink,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Show results', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );

    if (applied == true) {
      setState(() {
        _propertyId = property;
        _listingId = listing;
        _kind = kind;
        _sort = sort;
        _date = day;
        _dateType = dateType;
      });
      _refresh();
    }
  }

  String? get _listingLabel {
    if (_listingId == null) return null;
    for (final l in _listings) {
      if (l['id'] == _listingId) return '${l['label'] ?? 'Listing'}';
    }
    return null;
  }

  /// Quick listing switcher (vacation rentals with many listings).
  Future<void> _pickListing() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Theme(
        data: chatTheme(ctx),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Choose listing',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: ChatColors.ink)),
                ),
              ),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  ListTile(
                    leading: const Icon(Icons.apps_rounded, color: ChatColors.ink2),
                    title: const Text('All listings',
                        style: TextStyle(fontWeight: FontWeight.w600, color: ChatColors.ink)),
                    trailing: _listingId == null ? const Icon(Icons.check_rounded, color: ChatColors.ink) : null,
                    onTap: () => Navigator.pop(ctx, -1),
                  ),
                  for (final l in _listings)
                    ListTile(
                      leading: const Icon(Icons.home_outlined, color: ChatColors.ink2),
                      title: Text('${l['label'] ?? 'Listing'}',
                          style: const TextStyle(fontWeight: FontWeight.w600, color: ChatColors.ink)),
                      subtitle: _showPropertyFilter && '${l['property_name'] ?? ''}'.isNotEmpty
                          ? Text('${l['property_name']}', style: const TextStyle(color: ChatColors.ink3))
                          : null,
                      trailing:
                      _listingId == l['id'] ? const Icon(Icons.check_rounded, color: ChatColors.ink) : null,
                      onTap: () => Navigator.pop(ctx, l['id'] as int),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _listingId = picked == -1 ? null : picked);
    _refresh();
  }

  // ------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: chatTheme(context),
      child: Builder(builder: (context) {
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            foregroundColor: ChatColors.ink,
            leading: IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 32),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            titleSpacing: 0,
            title: const Text('Messages',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: ChatColors.ink)),
            actions: [
              if (_enabled)
                const Padding(
                  padding: EdgeInsets.only(right: 18),
                  child: Row(children: [
                    Icon(Icons.circle, size: 9, color: ChatColors.live),
                    SizedBox(width: 6),
                    Text('Live', style: TextStyle(fontSize: 15, color: ChatColors.ink3)),
                  ]),
                ),
            ],
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: Divider(height: 1, color: ChatColors.line),
            ),
          ),
          body: _body(),
        );
      }),
    );
  }

  Widget _body() {
    if (_booting) return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    if (_bootError != null) return _errorView(_bootError!, _boot);
    if (!_canChat) {
      return const ChatEmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'No access to messages',
        message: 'Ask the property owner to turn on OTA Messages for you in Manage Staff.',
      );
    }
    if (!_enabled) {
      return const ChatEmptyState(
        icon: Icons.forum_outlined,
        title: 'OTA Messages is off',
        message:
        'Guest messages from Airbnb, Booking.com and other channels will appear here once it is set up for your property. Contact Billzify support to turn it on.',
      );
    }

    return Column(children: [
      // search + filters
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 15, color: ChatColors.ink),
              decoration: InputDecoration(
                hintText: 'Search guest or booking ID',
                hintStyle: const TextStyle(color: ChatColors.ink3, fontSize: 15),
                prefixIcon: const Icon(Icons.search_rounded, color: ChatColors.ink3),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                  icon: const Icon(Icons.close_rounded, color: ChatColors.ink3),
                  onPressed: () {
                    _searchCtrl.clear();
                    _refresh();
                    setState(() {});
                  },
                ),
                filled: true,
                fillColor: ChatColors.field,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: _activeFilterCount > 0 ? ChatColors.ink : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: _activeFilterCount > 0 ? ChatColors.ink : ChatColors.line),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _openFilters,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Icon(Icons.filter_list_rounded,
                      size: 20, color: _activeFilterCount > 0 ? Colors.white : ChatColors.ink2),
                  const SizedBox(width: 6),
                  Text(_activeFilterCount > 0 ? 'Filters · $_activeFilterCount' : 'Filters',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _activeFilterCount > 0 ? Colors.white : ChatColors.ink)),
                ]),
              ),
            ),
          ),
        ]),
      ),
      // chips: listing · All · Unread · channels
      SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            if (_listings.length > 1)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Pill(
                  text: _listingLabel ?? 'All listings',
                  selected: _listingId != null,
                  icon: Icons.home_outlined,
                  trailingArrow: true,
                  onTap: _pickListing,
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Pill(
                text: 'All',
                selected: !_unreadOnly && _channel == null,
                onTap: () {
                  setState(() {
                    _unreadOnly = false;
                    _channel = null;
                  });
                  _refresh();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Pill(
                text: 'Unread',
                selected: _unreadOnly,
                onTap: () {
                  setState(() => _unreadOnly = !_unreadOnly);
                  _refresh();
                },
              ),
            ),
            for (final k in _channelChips)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Pill(
                  text: ChannelInfo.of(k).label,
                  selected: _channel == k,
                  logo: k,
                  onTap: () {
                    setState(() => _channel = _channel == k ? null : k);
                    _refresh();
                  },
                ),
              ),
          ],
        ),
      ),
      if (_date != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 16, 0),
          child: Row(children: [
            const Icon(Icons.event_outlined, size: 16, color: ChatColors.ink2),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${_dateType == 'checkin' ? 'Check-in' : _dateType == 'checkout' ? 'Check-out' : 'Staying'} on ${dayLabel(_date!)}',
                style: const TextStyle(fontSize: 13.5, color: ChatColors.ink2, fontWeight: FontWeight.w600),
              ),
            ),
            InkWell(
              onTap: () {
                setState(() => _date = null);
                _refresh();
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 17, color: ChatColors.ink3),
              ),
            ),
          ]),
        ),
      const SizedBox(height: 6),
      Expanded(child: _list()),
    ]);
  }

  Widget _list() {
    if (_loading && _items.isEmpty) return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    if (_listError != null && _items.isEmpty) return _errorView(_listError!, _refresh);

    return RefreshIndicator(
      color: ChatColors.ink,
      onRefresh: _refresh,
      child: _items.isEmpty
          ? ListView(children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.12),
        ChatEmptyState(
          icon: Icons.chat_bubble_outline_rounded,
          title: _hasFilters ? 'No matching chats' : 'No messages yet',
          message: _hasFilters
              ? 'Try changing or clearing the filters.'
              : 'When a guest writes to you on an OTA, the chat will show up here.',
        ),
      ])
          : ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= _items.length) {
            return const Padding(
              padding: EdgeInsets.all(18),
              child: Center(
                  child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          return _tile(_items[i]);
        },
      ),
    );
  }

  Widget _tile(Map<String, dynamic> c) {
    final channel = c['channel']?.toString();
    final name = guestNameOf(c);
    final unread = (c['unread_count'] as num?)?.toInt() ?? 0;
    final hasUnread = unread > 0;
    final stay = c['stay'] is Map ? Map<String, dynamic>.from(c['stay'] as Map) : null;
    final listing = (c['listing_label'] ?? '').toString();
    final property = (c['property_name'] ?? '').toString();
    final where = [
      if (_showPropertyFilter && property.isNotEmpty && property != listing) property,
      if (listing.isNotEmpty) listing,
    ].join(' › ');
    final preview = (c['last_message_preview'] ?? '').toString();
    final dates = stay != null ? stayText(stay) : '';

    return InkWell(
      onTap: () => _openChat(c),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GuestAvatar(name: name, channel: channel, size: 50),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // name · time
              Row(children: [
                Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w700,
                          color: ChatColors.ink)),
                ),
                const SizedBox(width: 8),
                Text(fmtListTime(parseTs(c['last_message_at'])),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w400,
                        color: hasUnread ? ChatColors.ink : ChatColors.ink3)),
              ]),
              const SizedBox(height: 5),
              // channel tag · listing
              Row(children: [
                ChannelTag(channel),
                if (where.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(where,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, color: ChatColors.ink3)),
                  ),
                ],
              ]),
              // stay dates · status
              if (stay != null) ...[
                const SizedBox(height: 5),
                Row(children: [
                  if (dates.isNotEmpty)
                    Flexible(
                      child: Text(dates,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, color: ChatColors.ink2)),
                    ),
                  const SizedBox(width: 8),
                  StatusPill('${stay['status']}'),
                ]),
              ],
              const SizedBox(height: 5),
              // last message · unread
              Row(children: [
                Expanded(
                  child: Text(preview.isEmpty ? 'No text' : preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontStyle: preview.isEmpty ? FontStyle.italic : FontStyle.normal,
                          color: hasUnread ? ChatColors.ink : ChatColors.ink3,
                          fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400)),
                ),
                if (hasUnread) ...[
                  const SizedBox(width: 8),
                  UnreadBadge(unread),
                ],
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _errorView(String msg, Future<void> Function() retry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, size: 40, color: ChatColors.ink3),
          const SizedBox(height: 12),
          Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: ChatColors.ink2, fontSize: 14.5)),
          const SizedBox(height: 14),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: ChatColors.ink),
            onPressed: retry,
            child: const Text('Try again'),
          ),
        ]),
      ),
    );
  }
}

/// Rounded chip like the web inbox: outlined when off, dark when on.
class _Pill extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final String? logo;          // channel name -> shows the OTA logo
  final bool trailingArrow;
  const _Pill({
    required this.text,
    required this.selected,
    required this.onTap,
    this.icon,
    this.logo,
    this.trailingArrow = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : ChatColors.ink;
    return Material(
      color: selected ? ChatColors.ink : Colors.white,
      shape: StadiumBorder(side: BorderSide(color: selected ? ChatColors.ink : ChatColors.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(logo != null || icon != null ? 10 : 16, 8, 16, 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (logo != null) ...[ChannelLogo(logo, size: 18), const SizedBox(width: 7)],
            if (icon != null) ...[Icon(icon, size: 17, color: fg), const SizedBox(width: 5)],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: fg)),
            ),
            if (trailingArrow) ...[
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: fg),
            ],
          ]),
        ),
      ),
    );
  }
}