// OTA Messages — one conversation.
// Loads latest messages, polls for new ones every 4 s, sends replies,
// retries failed ones, quick replies + suggestions.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_service.dart';
import 'chat_common.dart';

class ChatThreadScreen extends StatefulWidget {
  final int conversationId;

  /// Row from the list screen (optional) so the header shows instantly.
  final Map<String, dynamic>? preview;

  const ChatThreadScreen({super.key, required this.conversationId, this.preview});

  /// Used by the push-notification tap.
  static Route<void> route(int conversationId) =>
      MaterialPageRoute(builder: (_) => ChatThreadScreen(conversationId: conversationId));

  /// The chat currently on screen. Push notifications for this chat are not shown.
  static int? openConversationId;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _conv;
  final List<Map<String, dynamic>> _msgs = [];
  bool _loading = true;
  String? _error;
  bool _hasOlder = false;
  bool _loadingOlder = false;
  bool _sending = false;
  List<Map<String, dynamic>> _suggestions = [];

  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  bool _polling = false;

  int get _id => widget.conversationId;

  @override
  void initState() {
    super.initState();
    _conv = widget.preview == null ? null : Map<String, dynamic>.from(widget.preview!);
    ChatThreadScreen.openConversationId = _id;
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(() {
      // reversed list: maxScrollExtent = top (older messages)
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _loadOlder();
    });
    _input.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    if (ChatThreadScreen.openConversationId == _id) ChatThreadScreen.openConversationId = null;
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ChatThreadScreen.openConversationId = _id;
      _pollNew();
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      ChatThreadScreen.openConversationId = null;
      _poll?.cancel();
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _pollNew());
  }

  List<Map<String, dynamic>> _rows(dynamic list) =>
      List<Map<String, dynamic>>.from((list as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));

  void _applyConversation(Map d) {
    if (d['conversation'] is Map) {
      _conv = Map<String, dynamic>.from(d['conversation'] as Map);
      _suggestions = _rows(_conv!['suggestions']);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.instance.getData(ChatApi.messages(_id));
      final d = Map<String, dynamic>.from(res.data as Map);
      if (!mounted) return;
      setState(() {
        _applyConversation(d);
        _msgs
          ..clear()
          ..addAll(_rows(d['results']));
        _hasOlder = d['has_more'] == true;
        _loading = false;
      });
      _markRead();
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = chatError(e);
      });
    }
  }

  int? get _lastServerId {
    for (var i = _msgs.length - 1; i >= 0; i--) {
      final id = _msgs[i]['id'];
      if (id is int) return id;
    }
    return null;
  }

  Future<void> _pollNew() async {
    if (_polling || _loading || _error != null) return;
    final after = _lastServerId;
    if (after == null) return;
    _polling = true;
    try {
      final res = await ApiService.instance.getData(ChatApi.messages(_id), query: {'after': after});
      final d = Map<String, dynamic>.from(res.data as Map);
      final rows = _rows(d['results']);
      if (!mounted) return;
      final known = _msgs.map((m) => m['id']).toSet();
      final fresh = rows.where((r) => !known.contains(r['id'])).toList();
      setState(() {
        _applyConversation(d);
        _msgs.addAll(fresh);
      });
      if (fresh.any((m) => m['direction'] == 'in')) _markRead();
    } catch (_) {
      // network blip: try again on the next tick
    } finally {
      _polling = false;
    }
  }

  Future<void> _loadOlder() async {
    if (!_hasOlder || _loadingOlder || _msgs.isEmpty) return;
    final first = _msgs.firstWhere((m) => m['id'] is int, orElse: () => {});
    if (first['id'] == null) return;
    setState(() => _loadingOlder = true);
    try {
      final res = await ApiService.instance.getData(ChatApi.messages(_id), query: {'before': first['id']});
      final d = Map<String, dynamic>.from(res.data as Map);
      if (!mounted) return;
      setState(() {
        _msgs.insertAll(0, _rows(d['results']));
        _hasOlder = d['has_more'] == true;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _markRead() async {
    try {
      await ApiService.instance.postData(ChatApi.read(_id), {});
    } catch (_) {}
  }

  // ------------------------------------------------------------ send
  Future<void> _send([String? textOverride, Map<String, dynamic>? retryOf]) async {
    final text = (textOverride ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    if (text.length > 2000) {
      _toast('Message cannot exceed 2000 characters');
      return;
    }

    // Show it straight away as "sending".
    final local = <String, dynamic>{
      'id': 'local_${DateTime.now().microsecondsSinceEpoch}',
      'direction': 'out',
      'text': text,
      'status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    setState(() {
      _sending = true;
      if (retryOf != null) _msgs.remove(retryOf);
      _msgs.add(local);
      if (textOverride == null) _input.clear();
    });
    _scrollToBottom();

    try {
      final res = await ApiService.instance.postData(ChatApi.send(_id), {'text': text});
      final d = Map<String, dynamic>.from(res.data as Map);
      final saved = d['message'] is Map ? Map<String, dynamic>.from(d['message'] as Map) : null;
      if (!mounted) return;
      setState(() {
        final i = _msgs.indexOf(local);
        if (saved != null && i >= 0) {
          // the poller may already have added it
          if (_msgs.any((m) => m['id'] == saved['id'])) {
            _msgs.removeAt(i);
          } else {
            _msgs[i] = saved;
          }
        }
      });
      if (d['success'] != true) _toast('Not delivered. Tap ↻ to try again.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        local['status'] = 'failed';
        local['error'] = chatError(e);
      });
      _toast(chatError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  void _useText(String text) {
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
  }

  // ------------------------------------------------------------ quick replies
  Future<void> _openQuickReplies() async {
    final vendorId = _conv?['vendor_id'];
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Theme(
        data: chatTheme(ctx),
        child: _QuickRepliesSheet(
          vendorId: vendorId is int ? vendorId : null,
          guestName: (_conv?['guest_name'] ?? '').toString(),
        ),
      ),
    );
    if (picked != null && picked.isNotEmpty) _useText(picked);
  }

  void _showGuestDetails() {
    final c = _conv;
    if (c == null) return;
    final stay = c['stay'] is Map ? Map<String, dynamic>.from(c['stay'] as Map) : null;
    final rows = <List<String>>[
      ['Channel', ChannelInfo.of(c['channel']?.toString()).label],
      if ((c['booking_id'] ?? '').toString().isNotEmpty) ['Booking ID', '${c['booking_id']}'],
      if (stay != null && stayText(stay).isNotEmpty) ['Stay', stayText(stay)],
      if (stay != null && stayStatusLabels[stay['status']] != null) ['Status', stayStatusLabels[stay['status']]!],
      if (stay != null && (stay['rooms'] ?? 0) != 0) ['Rooms', '${stay['rooms']}'],
      if (stay != null && '${stay['guests'] ?? ''}'.isNotEmpty) ['Guests', '${stay['guests']}'],
      if ((c['guest_phone'] ?? '').toString().isNotEmpty) ['Phone', '${c['guest_phone']}'],
      if ((c['guest_email'] ?? '').toString().isNotEmpty) ['Email', '${c['guest_email']}'],
      if ((c['property_name'] ?? '').toString().isNotEmpty) ['Property', '${c['property_name']}'],
      if ((c['listing_label'] ?? '').toString().isNotEmpty) ['Listing', '${c['listing_label']}'],
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Theme(
        data: chatTheme(ctx),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(guestNameOf(c),
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: ChatColors.ink)),
              const SizedBox(height: 12),
              for (final r in rows)
                InkWell(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: r[1]));
                    Navigator.pop(ctx);
                    _toast('${r[0]} copied');
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: 96,
                        child: Text(r[0], style: const TextStyle(color: ChatColors.ink3, fontSize: 13.5)),
                      ),
                      Expanded(
                        child: Text(r[1],
                            style: const TextStyle(
                                color: ChatColors.ink, fontSize: 14.5, fontWeight: FontWeight.w500)),
                      ),
                    ]),
                  ),
                ),
              const SizedBox(height: 4),
              const Text('Long-press a row to copy it.', style: TextStyle(fontSize: 12, color: ChatColors.ink3)),
            ]),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ call / email
  Future<void> _call() async {
    final phone = (_conv?['guest_phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {}
  }

  Future<void> _email() async {
    final email = (_conv?['guest_email'] ?? '').toString().trim();
    if (email.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'mailto', path: email));
    } catch (_) {}
  }

  // ------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: chatTheme(context),
      child: Builder(builder: (context) {
        return Scaffold(
          backgroundColor: ChatColors.thread,
          appBar: _header(),
          body: _loading && _msgs.isEmpty
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
              : _error != null && _msgs.isEmpty
              ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: ChatColors.ink2)),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: ChatColors.ink),
                  onPressed: _load,
                  child: const Text('Try again'),
                ),
              ]),
            ),
          )
              : Column(children: [
            Expanded(child: _messageList()),
            _composer(),
          ]),
        );
      }),
    );
  }

  PreferredSizeWidget _header() {
    final c = _conv ?? {};
    final channel = c['channel']?.toString();
    final name = _conv == null ? 'Chat' : guestNameOf(c);
    final stay = c['stay'] is Map ? Map<String, dynamic>.from(c['stay'] as Map) : null;
    final listing = (c['listing_label'] ?? '').toString();
    final dates = stay != null ? stayDatesShort(stay) : '';
    final phone = (c['guest_phone'] ?? '').toString();
    final hasPhone = phone.replaceAll(RegExp(r'[^0-9]'), '').length >= 6 && !phone.contains('*');
    final hasEmail = (c['guest_email'] ?? '').toString().contains('@');

    Widget roundBtn(IconData icon, VoidCallback onTap, String tip) => Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(side: BorderSide(color: ChatColors.line)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Tooltip(
            message: tip,
            child: SizedBox(width: 42, height: 42, child: Icon(icon, size: 20, color: ChatColors.ink)),
          ),
        ),
      ),
    );

    return PreferredSize(
      preferredSize: const Size.fromHeight(76),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: ChatColors.line)),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 75,
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 32, color: ChatColors.ink),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: InkWell(
                  onTap: _showGuestDetails,
                  child: Row(children: [
                    GuestAvatar(name: name, channel: channel, size: 44),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ChatColors.ink)),
                          const SizedBox(height: 5),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [
                              if (_conv != null) ChannelTag(channel),
                              if (listing.isNotEmpty) ...[const SizedBox(width: 6), GreyChip(listing, maxWidth: 150)],
                              if (dates.isNotEmpty) ...[const SizedBox(width: 6), GreyChip(dates)],
                              if (_conv != null && stay == null && (c['booking_id'] ?? '').toString().isEmpty) ...[
                                const SizedBox(width: 6),
                                const GreyChip('Inquiry'),
                              ],
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
              if (hasPhone) roundBtn(Icons.call_outlined, _call, 'Call guest'),
              if (hasEmail) roundBtn(Icons.mail_outline_rounded, _email, 'Email guest'),
              if (!hasPhone && !hasEmail) roundBtn(Icons.info_outline_rounded, _showGuestDetails, 'Guest details'),
              const SizedBox(width: 14),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _messageList() {
    if (_msgs.isEmpty) {
      return const ChatEmptyState(
          icon: Icons.chat_bubble_outline_rounded, title: 'No messages', message: 'Say hello to your guest.');
    }
    // Newest first for a reversed ListView (keeps the view pinned to the bottom).
    final items = <Widget>[];
    for (var i = _msgs.length - 1; i >= 0; i--) {
      final m = _msgs[i];
      items.add(_bubble(m));
      final d = parseTs(m['created_at']);
      final prev = i > 0 ? parseTs(_msgs[i - 1]['created_at']) : null;
      if (d != null && (prev == null || !sameDay(prev, d))) items.add(_dayChip(d));
    }
    if (_loadingOlder) {
      items.add(const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      ));
    }
    return ListView(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: items,
    );
  }

  Widget _dayChip(DateTime d) => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 1))],
      ),
      child: Text(dayLabel(d),
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: ChatColors.ink3)),
    ),
  );

  Widget _bubble(Map<String, dynamic> m) {
    final out = m['direction'] == 'out';
    final status = '${m['status'] ?? ''}';
    final failed = status == 'failed';
    final pending = status == 'pending';
    final text = '${m['text'] ?? ''}';
    final attachments = m['attachments'] is List ? (m['attachments'] as List) : const [];
    final time = fmtTime(parseTs(m['created_at']));

    final bg = out ? (failed ? ChatColors.failed : ChatColors.out) : Colors.white;
    final fg = out && !failed ? Colors.white : ChatColors.ink;
    final soft = out && !failed ? Colors.white70 : ChatColors.ink3;

    // Content: text, attachment note, or a quiet placeholder (never an empty bubble)
    final children = <Widget>[];
    if (text.isNotEmpty) {
      children.add(Text(text, style: TextStyle(fontSize: 16, height: 1.35, color: fg)));
    }
    if (attachments.isNotEmpty) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 6));
      children.add(Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.attach_file_rounded, size: 16, color: soft),
        const SizedBox(width: 4),
        Text('${attachments.length} attachment${attachments.length == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 14, color: soft, fontWeight: FontWeight.w500)),
      ]));
    }
    if (children.isEmpty) {
      children.add(Text('Message without text',
          style: TextStyle(fontSize: 14.5, fontStyle: FontStyle.italic, color: soft)));
    }

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(22),
        boxShadow: out ? null : const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
    );

    final meta = Padding(
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 0),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(time, style: const TextStyle(fontSize: 12.5, color: ChatColors.ink3)),
        if (out) ...[
          const SizedBox(width: 6),
          if (pending)
            const Icon(Icons.schedule_rounded, size: 15, color: ChatColors.ink3)
          else if (failed)
            const Text('Not delivered', style: TextStyle(fontSize: 12.5, color: ChatColors.ink3))
          else
            const Icon(Icons.done_rounded, size: 16, color: ChatColors.ink),
        ],
      ]),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: out ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: out ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (failed)
                IconButton(
                  tooltip: 'Try again',
                  icon: const Icon(Icons.refresh_rounded, color: ChatColors.ink2),
                  onPressed: _sending ? null : () => _send(text, m),
                ),
              Flexible(
                child: GestureDetector(
                  onLongPress: () {
                    if (text.isEmpty) return;
                    Clipboard.setData(ClipboardData(text: text));
                    _toast(failed && (m['error'] ?? '').toString().isNotEmpty
                        ? 'Copied. Not delivered: ${m['error']}'
                        : 'Message copied');
                  },
                  child: bubble,
                ),
              ),
            ],
          ),
          meta,
        ],
      ),
    );
  }

  Widget _composer() {
    final canReply = _conv?['can_reply'] != false;
    final reason = (_conv?['reply_block_reason'] ?? '').toString();
    final empty = _input.text.trim().isEmpty;
    final guest = (_conv?['guest_name'] ?? '').toString().trim();
    final firstName = guest.isEmpty ? 'guest' : guest.split(RegExp(r'\s+')).first;

    if (!canReply) {
      return SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 6, 14, 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, size: 18, color: ChatColors.ink3),
            const SizedBox(width: 8),
            Expanded(
              child: Text(reason.isEmpty ? 'Replies are not available for this chat.' : reason,
                  style: const TextStyle(fontSize: 14, color: ChatColors.ink2)),
            ),
          ]),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_suggestions.isNotEmpty && empty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
              children: [
                for (final s in _suggestions)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Material(
                      color: Colors.white,
                      shape: const StadiumBorder(side: BorderSide(color: ChatColors.line)),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () => _useText('${s['filled_text'] ?? s['text'] ?? ''}'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.bolt_rounded, size: 16, color: ChatColors.ink2),
                            const SizedBox(width: 4),
                            Text('${s['title']}',
                                style: const TextStyle(
                                    fontSize: 13.5, fontWeight: FontWeight.w600, color: ChatColors.ink)),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Container(
          margin: const EdgeInsets.fromLTRB(14, 2, 14, 12),
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 14, offset: Offset(0, 3))],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(
              tooltip: 'Quick replies',
              icon: const Icon(Icons.bolt_rounded, color: ChatColors.ink2, size: 24),
              onPressed: _openQuickReplies,
            ),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 16, color: ChatColors.ink),
                decoration: InputDecoration(
                  hintText: 'Write a reply to $firstName…',
                  hintStyle: const TextStyle(color: ChatColors.ink3, fontSize: 16),
                  counterText: '',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Material(
              color: empty || _sending ? const Color(0xFFE4E4EC) : ChatColors.out,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: empty || _sending ? null : () => _send(),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: _sending
                      ? const Padding(
                    padding: EdgeInsets.all(13),
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ================================================================ quick replies sheet
class _QuickRepliesSheet extends StatefulWidget {
  final int? vendorId;
  final String guestName;
  const _QuickRepliesSheet({required this.vendorId, required this.guestName});

  @override
  State<_QuickRepliesSheet> createState() => _QuickRepliesSheetState();
}

class _QuickRepliesSheetState extends State<_QuickRepliesSheet> {
  bool _loading = true;
  String? _error;
  bool _canManage = false;
  List<Map<String, dynamic>> _items = [];

  Map<String, dynamic> get _q => widget.vendorId == null ? {} : {'property': widget.vendorId};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.instance.getData(ChatApi.quickReplies, query: _q);
      final d = Map<String, dynamic>.from(res.data as Map);
      if (!mounted) return;
      setState(() {
        _canManage = d['can_manage'] == true;
        _items = List<Map<String, dynamic>>.from(
            (d['results'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = chatError(e);
      });
    }
  }

  String _fill(String text) {
    final first = widget.guestName.trim().split(RegExp(r'\s+')).first;
    return text.replaceAll('{guest}', first.isEmpty ? 'there' : first);
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final title = TextEditingController(text: item?['title']?.toString() ?? '');
    final text = TextEditingController(text: item?['text']?.toString() ?? '');
    final keywords = TextEditingController(text: item?['keywords']?.toString() ?? '');
    String? err;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> save() async {
          if (title.text.trim().isEmpty || text.text.trim().isEmpty) {
            setD(() => err = 'Title and message are required');
            return;
          }
          setD(() {
            saving = true;
            err = null;
          });
          final body = {
            'title': title.text.trim(),
            'text': text.text.trim(),
            'keywords': keywords.text.trim(),
            if (widget.vendorId != null) 'property': widget.vendorId,
          };
          try {
            if (item == null) {
              await ApiService.instance.postData(ChatApi.quickReplies, body);
            } else {
              await ApiService.instance.postData(ChatApi.quickReply(item['id'] as int), body);
            }
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          } catch (e) {
            setD(() {
              saving = false;
              err = chatError(e);
            });
          }
        }

        InputDecoration deco(String label, [String? hint]) => InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          isDense: true,
        );

        return AlertDialog(
          title: Text(item == null ? 'New quick reply' : 'Edit quick reply'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, maxLength: 60, decoration: deco('Title', 'e.g. Check-in time')),
              const SizedBox(height: 6),
              TextField(
                controller: text,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
                decoration: deco('Message', 'Use {guest} for the guest\'s first name'),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: keywords,
                decoration: deco('Keywords (optional)', 'checkin, arrival, time'),
              ),
              const SizedBox(height: 4),
              const Text('Keywords help suggest this reply when a guest uses those words.',
                  style: TextStyle(fontSize: 12, color: ChatColors.ink3)),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err!, style: const TextStyle(color: Color(0xFF8A3E38), fontSize: 13)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ChatColors.ink),
              onPressed: saving ? null : save,
              child: Text(saving ? 'Saving…' : 'Save'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete quick reply?'),
        content: Text('"${item['title']}" will be removed for everyone on this property.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.instance.postData(ChatApi.quickReply(item['id'] as int), {'delete': true});
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(chatError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(color: ChatColors.line, borderRadius: BorderRadius.circular(4)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
            child: Row(children: [
              const Expanded(
                child: Text('Quick replies',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: ChatColors.ink)),
              ),
              if (_canManage)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: ChatColors.ink),
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: const Text('New'),
                ),
            ]),
          ),
          Flexible(
            child: _loading
                ? const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
            )
                : _error != null
                ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: ChatColors.ink2)),
            )
                : _items.isEmpty
                ? Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 30),
              child: Text(
                _canManage
                    ? 'Save replies you send often — check-in time, directions, Wi-Fi — and send them in one tap.'
                    : 'No quick replies yet. The property owner can add them.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: ChatColors.ink3, fontSize: 14, height: 1.4),
              ),
            )
                : ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final q = _items[i];
                final filled = _fill('${q['text'] ?? ''}');
                return Material(
                  color: ChatColors.field,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(context, filled),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 4, 12),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${q['title']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14.5, color: ChatColors.ink)),
                            const SizedBox(height: 3),
                            Text(filled,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13.5, color: ChatColors.ink2, height: 1.35)),
                          ]),
                        ),
                        if (_canManage)
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded, color: ChatColors.ink3, size: 20),
                            onSelected: (v) => v == 'edit' ? _edit(q) : _delete(q),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}