import 'package:flutter/material.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';
import 'booking_detail_screen.dart';

// ============================================================
// AI ASSISTANT CHAT SCREEN — COMPLETE
// ============================================================

class _ChatMessage {
  final String text;
  final bool isUser;
  final String? resultType;
  final dynamic data;
  final DateTime time;
  bool actionDone;

  _ChatMessage({
    required this.text,
    required this.isUser,
    this.resultType,
    this.data,
    this.actionDone = false,
    DateTime? time,
  }) : time = time ?? DateTime.now();
}

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<_ChatMessage> _messages = [];

  bool _sending = false;
  int? _selectedChipIndex;

  static const List<String> _defaultChips = [
    "Today's arrivals",
    "Today's departures",
    'Check inventory',
    'No show list',
    'Rate suggestion',
  ];

  List<String> _frequentChips = [];
  int? _quotaUsed;
  int? _quotaLimit;

  @override
  void initState() {
    super.initState();
    _messages.add(_ChatMessage(
      text:
      "Hi! I'm your Billzify assistant.\nI can help with arrivals, departures, booking search, inventory/rates, no-shows, reports, and rate suggestions.",
      isUser: false,
    ));
    _loadFrequentQuestions();
    _loadUsageStatus();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFrequentQuestions() async {
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.getData(
        AppConfig.aiFrequent,
        query: {'user_id': uid, 'limit': '5'},
      );
      final list = (res.data['questions'] as List?) ?? [];
      if (!mounted) return;
      setState(() => _frequentChips = list.map((e) => e.toString()).toList());
    } catch (_) {}
  }

  Future<void> _loadUsageStatus() async {
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.getData(
        AppConfig.aiUsage,
        query: {'user_id': uid},
      );
      if (!mounted) return;
      setState(() {
        _quotaUsed = res.data['used'] as int?;
        _quotaLimit = res.data['limit'] as int?;
      });
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send([String? presetText]) async {
    final text = (presetText ?? _inputCtrl.text).trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _sending = true;
      _inputCtrl.clear();
    });
    _scrollToBottom();

    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(
        AppConfig.aiChat,
        {'user_id': uid, 'message': text},
      );

      final reply = (res.data['reply'] ?? '').toString();
      final resultType = res.data['result_type']?.toString();
      final data = res.data['data'];
      final source = res.data['source']?.toString();

      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          text: reply.isEmpty ? 'Something went wrong.' : reply,
          isUser: false,
          resultType: resultType,
          data: data,
        ));
        _sending = false;
      });

      _loadFrequentQuestions();
      if (source != null && source.startsWith('gemini')) {
        _loadUsageStatus();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(text: friendlyError(e), isUser: false));
        _sending = false;
      });
    }
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              margin: const EdgeInsets.only(left: 4, right: 10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.smart_toy_outlined, color: AppColors.primary, size: 20),
            ),
            const Expanded(
              child: Text(
                'AI Assistant',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
            ),
            if (_quotaUsed != null && _quotaLimit != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$_quotaUsed/$_quotaLimit AI',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary),
                  ),
                ),
              ),
          ],
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                itemCount: _messages.length + (_sending ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i == _messages.length && _sending) return _typingBubble();
                  return _messageBubble(_messages[i]);
                },
              ),
            ),
            _disclaimerBanner(),
            _suggestionRow(),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _disclaimerBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: AppColors.background,
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 12, color: AppColors.textSecondary.withOpacity(0.7)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'AI can make mistakes — please double-check important responses.',
              style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary.withOpacity(0.8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionRow() {
    final allChips = [
      ..._defaultChips,
      if (_frequentChips.isNotEmpty) '__divider__',
      ..._frequentChips,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: allChips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (ctx, i) {
            final chip = allChips[i];

            if (chip == '__divider__') {
              return Center(child: Container(width: 1, height: 22, color: AppColors.border));
            }

            final isFrequent = i > _defaultChips.length;
            final selected = _selectedChipIndex == i;

            return InkWell(
              onTap: () {
                setState(() => _selectedChipIndex = i);
                _send(chip);
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : (isFrequent ? AppColors.successSoft : AppColors.accentSoft),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: selected ? AppColors.primary : AppColors.border),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isFrequent && !selected)
                      const Padding(
                        padding: EdgeInsets.only(right: 5),
                        child: Icon(Icons.history_rounded, size: 13, color: AppColors.success),
                      ),
                    Text(
                      chip,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: selected ? Colors.white : (isFrequent ? AppColors.success : AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, -2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _inputCtrl,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Type your message…',
                  hintStyle: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _sending ? null : () => _send(),
            customBorder: const CircleBorder(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _sending ? AppColors.border : AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_upward_rounded,
                  color: _sending ? AppColors.textSecondary : Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 60),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: const SizedBox(width: 30, height: 14, child: _TypingDots()),
      ),
    );
  }

  Widget _messageBubble(_ChatMessage msg) {
    final isUser = msg.isUser;
    final isApology = msg.resultType == 'angry_user_handled';

    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: EdgeInsets.only(bottom: 6, left: isUser ? 60 : 0, right: isUser ? 0 : 60),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUser ? AppColors.primary : (isApology ? AppColors.accentSoft : AppColors.card),
              borderRadius: BorderRadius.circular(16),
              border: isUser ? null : Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isApology)
                  const Padding(
                    padding: EdgeInsets.only(right: 8, top: 1),
                    child: Icon(Icons.favorite, size: 14, color: AppColors.primary),
                  ),
                Flexible(
                  child: Text(
                    msg.text,
                    style: TextStyle(fontSize: 13.5, height: 1.4, color: isUser ? Colors.white : AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!isUser && msg.data != null && _hasContent(msg.data))
          Padding(
            padding: const EdgeInsets.only(bottom: 14, right: 40),
            child: _resultCard(msg),
          )
        else
          const SizedBox(height: 6),
      ],
    );
  }

  bool _hasContent(dynamic data) {
    if (data is List) return data.isNotEmpty;
    if (data is Map) return data.isNotEmpty;
    return false;
  }

  Widget _resultCard(_ChatMessage msg) {
    switch (msg.resultType) {
      case 'booking_list':
        return _bookingListCard(List<dynamic>.from(msg.data));
      case 'inventory_list':
        return _inventoryListCard(List<dynamic>.from(msg.data));
      case 'noshow_list':
        return _noshowListCard(List<dynamic>.from(msg.data));
      case 'sales_report':
        return _channelTableCard(List<dynamic>.from(msg.data), valueKey: 'sales', valueLabel: 'Sales');
      case 'commission_report':
        return _channelTableCard(List<dynamic>.from(msg.data), valueKey: 'commission', valueLabel: 'Commission');
      case 'accounts_report':
        return _receivablesCard(List<dynamic>.from(msg.data));
      case 'rate_suggestion':
        return _rateSuggestionCard(Map<String, dynamic>.from(msg.data as Map));
      case 'rate_suggestion_range':
        return _rateSuggestionRangeCard(List<dynamic>.from(msg.data));
      case 'action_confirm':
        return _actionConfirmCard(msg);
      case 'open_booking_wizard':
        return _BookingWizardCard(onClosed: () {});
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _bookingListCard(List<dynamic> items) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: items.take(10).map((g) {
          final name = (g['guest_name'] ?? '-').toString();
          final phone = (g['phone'] ?? '').toString();
          final amount = g['amount']?.toString() ?? '0';
          final status = (g['payment_status'] ?? '').toString();
          final ref = (g['booking_ref'] ?? '').toString();
          final channel = (g['channel_name'] ?? '').toString();

          return InkWell(
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BookingDetailScreen(booking: Map<String, dynamic>.from(g as Map)),
              ));
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: g != items.last ? const BorderSide(color: AppColors.border) : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
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
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                            if (ref.isNotEmpty)
                              Text('#$ref', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [channel, phone].where((s) => s.isNotEmpty).join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('₹$amount', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      if (status.isNotEmpty)
                        Text(status, style: const TextStyle(fontSize: 10, color: AppColors.primary)),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _inventoryListCard(List<dynamic> items) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: items.map((r) {
          final name = (r['roomCode'] ?? '-').toString();
          final available = r['available']?.toString() ?? '0';
          final price = r['price']?.toString() ?? '0';
          final stopSell = (r['restrictions']?['stopSell'] ?? false) == true;

          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                bottom: r != items.last ? const BorderSide(color: AppColors.border) : BorderSide.none,
              ),
            ),
            child: Row(
              children: [
                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                Text('$available avail', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(width: 10),
                Text('₹$price', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                if (stopSell) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration:
                    BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(6)),
                    child: const Text('Stop',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFFDC2626))),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _noshowListCard(List<dynamic> items) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: items.take(10).map((g) {
          final name = (g['guest_name'] ?? '-').toString();
          final phone = (g['guest_phone'] ?? '').toString();
          final ref = (g['booking_ref'] ?? '').toString();
          final amount = g['amount']?.toString() ?? '0';

          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                bottom: g != items.last ? const BorderSide(color: AppColors.border) : BorderSide.none,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(
                        [phone, if (ref.isNotEmpty) '#$ref'].where((s) => s.isNotEmpty).join('  ·  '),
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Text('₹$amount', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _channelTableCard(List<dynamic> items, {required String valueKey, required String valueLabel}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: items.take(10).map((c) {
          final channel = (c['channel'] ?? '-').toString();
          final value = c[valueKey]?.toString() ?? '0';
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                bottom: c != items.last ? const BorderSide(color: AppColors.border) : BorderSide.none,
              ),
            ),
            child: Row(
              children: [
                Expanded(child: Text(channel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                Text('₹$value $valueLabel', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _receivablesCard(List<dynamic> items) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: items.take(10).map((r) {
          final guest = (r['guest'] ?? '-').toString();
          final pending = r['pending']?.toString() ?? '0';
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                bottom: r != items.last ? const BorderSide(color: AppColors.border) : BorderSide.none,
              ),
            ),
            child: Row(
              children: [
                Expanded(child: Text(guest, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                Text('₹$pending pending',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFFDC2626))),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _rateSuggestionCard(Map<String, dynamic> d) {
    final direction = (d['direction'] ?? 'hold').toString();
    final color = direction == 'increase'
        ? AppColors.success
        : direction == 'decrease'
        ? const Color(0xFFEF4444)
        : AppColors.primary;
    final icon = direction == 'increase'
        ? Icons.trending_up
        : direction == 'decrease'
        ? Icons.trending_down
        : Icons.trending_flat;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                direction == 'increase'
                    ? 'Consider raising rates'
                    : direction == 'decrease'
                    ? 'Consider holding rates competitive'
                    : 'Rates look stable',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _statPill('${d['total_bookings_30d']}', 'bookings (30d)'),
              _statPill('${d['last_minute_pct']}%', 'last-minute'),
              _statPill('${d['avg_lead_days']}d', 'avg lead time'),
              _statPill('${d['trend_pct']}%', '7-day trend'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statPill(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }

  // ── Rate suggestion for a DATE RANGE — grouped by date, each row
  // has its own Apply button (reuses the same confirm-inventory-
  // update endpoint as the single-date flow). ──
  Widget _rateSuggestionRangeCard(List<dynamic> items) {
    final byDate = <String, List<dynamic>>{};
    for (final item in items) {
      final date = (item['date'] ?? '').toString();
      byDate.putIfAbsent(date, () => []).add(item);
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: byDate.entries.map((entry) {
          final date = entry.key;
          final rows = entry.value;
          final isLast = entry.key == byDate.keys.last;

          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(bottom: isLast ? BorderSide.none : const BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                ...rows.map((r) => _RateRangeRow(data: Map<String, dynamic>.from(r as Map))),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _actionConfirmCard(_ChatMessage msg) {
    final data = Map<String, dynamic>.from(msg.data as Map);
    final action = data['action']?.toString();

    if (action == 'inventory_update') {
      return _InventoryUpdateConfirmCard(
        data: data,
        done: msg.actionDone,
        onConfirmed: () => setState(() => msg.actionDone = true),
      );
    }
    if (action == 'noshow_mark') {
      return _NoShowConfirmCard(
        data: data,
        done: msg.actionDone,
        onConfirmed: () => setState(() => msg.actionDone = true),
      );
    }
    if (action == 'booking_cancel') {
      return _BookingCancelConfirmCard(
        data: data,
        done: msg.actionDone,
        onConfirmed: () => setState(() => msg.actionDone = true),
      );
    }
    if (action == 'invoice_generate') {
      return _InvoiceGenerateConfirmCard(
        data: data,
        done: msg.actionDone,
        onConfirmed: () => setState(() => msg.actionDone = true),
      );
    }
    return const SizedBox.shrink();
  }
}

// ============================================================
// INVENTORY UPDATE CONFIRM CARD
// ============================================================
class _InventoryUpdateConfirmCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool done;
  final VoidCallback onConfirmed;

  const _InventoryUpdateConfirmCard({required this.data, required this.done, required this.onConfirmed});

  @override
  State<_InventoryUpdateConfirmCard> createState() => _InventoryUpdateConfirmCardState();
}

class _InventoryUpdateConfirmCardState extends State<_InventoryUpdateConfirmCard> {
  late TextEditingController _priceCtrl;
  late TextEditingController _availCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(
        text: (widget.data['suggested_price'] ?? widget.data['current_price'] ?? 0).toString().replaceAll('.0', ''));
    _availCtrl =
        TextEditingController(text: (widget.data['suggested_available'] ?? widget.data['current_available'] ?? 0).toString());
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _availCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      await ApiService.instance.postData(
        AppConfig.aiConfirmInventoryUpdate,
        {
          'user_id': uid,
          'room_category_id': widget.data['room_category_id'],
          'date': widget.data['date'],
          'new_price': int.tryParse(_priceCtrl.text.trim()) ?? widget.data['current_price'],
          'new_available': int.tryParse(_availCtrl.text.trim()) ?? widget.data['current_available'],
        },
      );
      if (!mounted) return;
      widget.onConfirmed();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomName = (widget.data['room_category_name'] ?? '').toString();
    final dateStr = (widget.data['date'] ?? '').toString();

    if (widget.done) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.successSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.success),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text('$roomName rate updated for $dateStr.',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(child: Text('$roomName · $dateStr', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _confirmField('Price (₹)', _priceCtrl)),
              const SizedBox(width: 10),
              Expanded(child: _confirmField('Available rooms', _availCtrl)),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626))),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _confirmField(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(border: InputBorder.none, isCollapsed: true),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// NO-SHOW MARK CONFIRM CARD
// ============================================================
class _NoShowConfirmCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool done;
  final VoidCallback onConfirmed;

  const _NoShowConfirmCard({required this.data, required this.done, required this.onConfirmed});

  @override
  State<_NoShowConfirmCard> createState() => _NoShowConfirmCardState();
}

class _NoShowConfirmCardState extends State<_NoShowConfirmCard> {
  bool _saving = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() { _saving = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      await ApiService.instance.postData(
        AppConfig.aiConfirmNoshow,
        {'user_id': uid, 'booking_id': widget.data['booking_id']},
      );
      if (!mounted) return;
      widget.onConfirmed();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final guestName = (widget.data['guest_name'] ?? '').toString();
    final ref = (widget.data['booking_ref'] ?? '').toString();
    final amount = widget.data['amount']?.toString() ?? '0';

    if (widget.done) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.successSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.success),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text('$guestName marked as no-show.',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEF4444), width: 1.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_busy_outlined, size: 16, color: Color(0xFFEF4444)),
              const SizedBox(width: 6),
              Expanded(child: Text(guestName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              if (ref.isNotEmpty) Text('#$ref', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 4),
          Text('₹$amount', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626))),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: _saving ? null : _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Confirm No-Show', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Simple animated typing dots ──
class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_ctrl.value - (i * 0.2)) % 1.0;
            final scale = 0.6 + 0.4 * (t < 0.5 ? t * 2 : (1 - t) * 2);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Transform.scale(
                scale: scale.clamp(0.6, 1.0),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ============================================================
// RATE RANGE ROW — single room-category row inside the date-range
// rate suggestion card, with its own Apply button.
// ============================================================
class _RateRangeRow extends StatefulWidget {
  final Map<String, dynamic> data;
  const _RateRangeRow({required this.data});

  @override
  State<_RateRangeRow> createState() => _RateRangeRowState();
}

class _RateRangeRowState extends State<_RateRangeRow> {
  bool _applying = false;
  bool _applied = false;
  String? _error;

  Future<void> _apply() async {
    setState(() { _applying = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      await ApiService.instance.postData(
        AppConfig.aiConfirmInventoryUpdate,
        {
          'user_id': uid,
          'room_category_id': widget.data['room_category_id'],
          'date': widget.data['date'],
          'new_price': widget.data['suggested_price'],
          'new_available': widget.data['available'],
        },
      );
      if (!mounted) return;
      setState(() => _applied = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.data['room_category_name'] ?? '').toString();
    final current = widget.data['current_price']?.toString() ?? '0';
    final suggested = widget.data['suggested_price']?.toString() ?? '0';
    final direction = (widget.data['direction'] ?? 'hold').toString();
    final color = direction == 'increase'
        ? AppColors.success
        : direction == 'decrease'
        ? const Color(0xFFEF4444)
        : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Text('₹$current', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(width: 6),
          Icon(Icons.arrow_forward, size: 11, color: color),
          const SizedBox(width: 6),
          Text('₹$suggested', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(width: 10),
          if (_applied)
            const Icon(Icons.check_circle, size: 18, color: AppColors.success)
          else
            SizedBox(
              height: 28,
              child: ElevatedButton(
                onPressed: _applying ? null : _apply,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: _applying
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Apply', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// BOOKING CANCEL CONFIRM CARD — highest-risk action. Permanent.
// Only fires on explicit button tap.
// ============================================================
class _BookingCancelConfirmCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool done;
  final VoidCallback onConfirmed;

  const _BookingCancelConfirmCard({required this.data, required this.done, required this.onConfirmed});

  @override
  State<_BookingCancelConfirmCard> createState() => _BookingCancelConfirmCardState();
}

class _BookingCancelConfirmCardState extends State<_BookingCancelConfirmCard> {
  bool _saving = false;
  String? _error;
  bool _checkedWarning = false;

  Future<void> _confirm() async {
    setState(() { _saving = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      await ApiService.instance.postData(
        AppConfig.aiConfirmCancelBooking,
        {'user_id': uid, 'booking_id': widget.data['booking_id']},
      );
      if (!mounted) return;
      widget.onConfirmed();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final guestName = (widget.data['guest_name'] ?? '').toString();
    final ref = (widget.data['booking_ref'] ?? '').toString();
    final amount = widget.data['amount']?.toString() ?? '0';
    final ci = (widget.data['check_in_date'] ?? '').toString();
    final co = (widget.data['check_out_date'] ?? '').toString();

    if (widget.done) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.successSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.success),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text('$guestName\'s booking cancelled.',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEF4444), width: 1.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFEF4444)),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('This will permanently cancel the booking',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Color(0xFFEF4444))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(guestName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                    if (ref.isNotEmpty) Text('#$ref', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
                if (ci.isNotEmpty || co.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('$ci → $co', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
                const SizedBox(height: 2),
                Text('₹$amount', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => setState(() => _checkedWarning = !_checkedWarning),
            child: Row(
              children: [
                Icon(
                  _checkedWarning ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 18,
                  color: _checkedWarning ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('I understand this cannot be undone',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626))),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: (_saving || !_checkedWarning) ? null : _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                disabledBackgroundColor: AppColors.border,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Confirm Cancel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// INVOICE GENERATE CONFIRM CARD
// ============================================================
class _InvoiceGenerateConfirmCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool done;
  final VoidCallback onConfirmed;

  const _InvoiceGenerateConfirmCard({required this.data, required this.done, required this.onConfirmed});

  @override
  State<_InvoiceGenerateConfirmCard> createState() => _InvoiceGenerateConfirmCardState();
}

class _InvoiceGenerateConfirmCardState extends State<_InvoiceGenerateConfirmCard> {
  bool _saving = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() { _saving = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      await ApiService.instance.postData(
        AppConfig.aiConfirmInvoiceGenerate,
        {'user_id': uid, 'booking_id': widget.data['booking_id']},
      );
      if (!mounted) return;
      widget.onConfirmed();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final guestName = (widget.data['guest_name'] ?? '').toString();
    final ref = (widget.data['booking_ref'] ?? '').toString();
    final amount = widget.data['amount']?.toString() ?? '0';

    if (widget.done) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.successSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.success),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Invoice generated for $guestName.',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(child: Text(guestName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              if (ref.isNotEmpty) Text('#$ref', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 4),
          Text('₹$amount', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626))),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: _saving ? null : _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Generate Invoice', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BOOKING CREATE WIZARD
// Multi-step, state held entirely on-device (Flutter). NOTHING is
// saved to the server until the final "Create Booking" button is
// tapped — that single tap calls api_ai_confirm_create_booking,
// which is a thin pass-through to the existing, battle-tested
// api_save_booking. No partial data is ever sent mid-wizard except
// the read-only date-availability check (step 1 -> 2).
// ============================================================
class _BookingWizardCard extends StatefulWidget {
  final VoidCallback onClosed;
  const _BookingWizardCard({required this.onClosed});

  @override
  State<_BookingWizardCard> createState() => _BookingWizardCardState();
}

enum _WizardStep { dates, rooms, guest, payment, confirm, done }

class _BookingWizardCardState extends State<_BookingWizardCard> {
  _WizardStep _step = _WizardStep.dates;
  bool _loading = false;
  String? _error;

  DateTime? _checkin;
  DateTime? _checkout;
  Map<String, dynamic>? _availabilityData; // raw response from wizard-check-dates
  Map<String, dynamic>? _selectedRoom; // chosen room entry from rooms list
  int _roomQty = 1;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _advanceCtrl = TextEditingController(text: '0');
  String _paymentMode = 'cash';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _advanceCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _checkin != null && _checkout != null
          ? DateTimeRange(start: _checkin!, end: _checkout!)
          : null,
    );
    if (range == null) return;
    setState(() {
      _checkin = range.start;
      _checkout = range.end;
    });
  }

  Future<void> _checkAvailability() async {
    if (_checkin == null || _checkout == null) {
      setState(() => _error = 'Please select check-in and check-out dates.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(
        AppConfig.aiWizardCheckDates,
        {'user_id': uid, 'checkin': _fmtDate(_checkin!), 'checkout': _fmtDate(_checkout!)},
      );
      if (!mounted) return;
      setState(() {
        _availabilityData = Map<String, dynamic>.from(res.data as Map);
        _step = _WizardStep.rooms;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectRoom(Map<String, dynamic> room) {
    setState(() {
      _selectedRoom = room;
      _roomQty = 1;
      _step = _WizardStep.guest;
    });
  }

  void _goToPayment() {
    if (_nameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Guest name and phone are required.');
      return;
    }
    setState(() { _error = null; _step = _WizardStep.payment; });
  }

  double get _nights {
    if (_checkin == null || _checkout == null) return 1;
    return _checkout!.difference(_checkin!).inDays.toDouble().clamp(1, 999);
  }

  double get _pricePerNight => (_selectedRoom?['price'] as num?)?.toDouble() ?? 0;
  double get _grandTotal => _pricePerNight * _nights * _roomQty;

  Future<void> _createBooking() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      final advance = double.tryParse(_advanceCtrl.text.trim()) ?? 0;
      final remaining = (_grandTotal - advance).clamp(0, double.infinity);

      await ApiService.instance.postData(
        AppConfig.aiConfirmCreateBooking,
        {
          'user_id': uid,
          'checkin': _fmtDate(_checkin!),
          'checkout': _fmtDate(_checkout!),
          'guest_name': _nameCtrl.text.trim(),
          'guest_contact': _phoneCtrl.text.trim(),
          'total_guests': 1,
          'payment_mode': _paymentMode,
          'advance_amount': advance,
          'grand_total': _grandTotal,
          'total_base': _grandTotal,
          'total_tax': 0,
          'remaining_amount': remaining,
          'special_request': '',
          'is_occupancy_based': false,
          'rate_plan': _selectedRoom?['rate_plan_name'] ?? '',
          'rooms_data': [
            {
              'cat_id': _selectedRoom?['id'],
              'qty': _roomQty,
              'settle_total': _grandTotal,
              'base': _grandTotal,
              'gst': 0,
            }
          ],
          'extra_charges': {},
        },
      );
      if (!mounted) return;
      setState(() => _step = _WizardStep.done);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_step == _WizardStep.done) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.successSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.success),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Booking created for ${_nameCtrl.text.trim()}.',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _wizardStepIndicator(),
          const SizedBox(height: 12),
          if (_step == _WizardStep.dates) _datesStep(),
          if (_step == _WizardStep.rooms) _roomsStep(),
          if (_step == _WizardStep.guest) _guestStep(),
          if (_step == _WizardStep.payment) _paymentStep(),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(fontSize: 11.5, color: Color(0xFFDC2626))),
          ],
        ],
      ),
    );
  }

  Widget _wizardStepIndicator() {
    final labels = ['Dates', 'Room', 'Guest', 'Payment'];
    final currentIndex = _step.index.clamp(0, 3);
    return Row(
      children: List.generate(labels.length, (i) {
        final active = i <= currentIndex;
        return Expanded(
          child: Row(
            children: [
              Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? AppColors.primary : AppColors.border,
                ),
              ),
              if (i < labels.length - 1)
                Expanded(child: Container(height: 1.5, color: active ? AppColors.primary : AppColors.border)),
            ],
          ),
        );
      }),
    );
  }

  Widget _datesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select check-in & check-out', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 10),
        InkWell(
          onTap: _pickDateRange,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  _checkin == null
                      ? 'Tap to select dates'
                      : '${_fmtDate(_checkin!)}  →  ${_fmtDate(_checkout!)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: ElevatedButton(
            onPressed: _loading ? null : _checkAvailability,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Check Availability', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _roomsStep() {
    final rooms = (_availabilityData?['rooms'] as List?) ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select a room category', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 10),
        if (rooms.isEmpty)
          const Text('No rooms available for these dates.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))
        else
          ...rooms.map((r) {
            final room = Map<String, dynamic>.from(r as Map);
            final available = (room['available'] as num?)?.toInt() ?? 0;
            final isAvailable = available > 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: isAvailable ? () => _selectRoom(room) : null,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isAvailable ? AppColors.background : AppColors.border.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(room['name']?.toString() ?? '-',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(
                              isAvailable ? '$available available' : 'Sold out',
                              style: TextStyle(
                                fontSize: 11,
                                color: isAvailable ? AppColors.textSecondary : const Color(0xFFDC2626),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text('₹${room['price']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      if (isAvailable) const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _guestStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_selectedRoom?['name'] ?? ''} · ${_fmtDate(_checkin!)} → ${_fmtDate(_checkout!)}',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        const Text('Guest details', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        _wizardTextField('Guest name', _nameCtrl),
        const SizedBox(height: 8),
        _wizardTextField('Phone number', _phoneCtrl, keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: ElevatedButton(
            onPressed: _goToPayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Next', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _paymentStep() {
    final advance = double.tryParse(_advanceCtrl.text.trim()) ?? 0;
    final remaining = (_grandTotal - advance).clamp(0, double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_nameCtrl.text.trim(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              Text('${_selectedRoom?['name'] ?? ''} · ${_nights.toInt()} night(s)',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text('Total: ₹${_grandTotal.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _wizardTextField('Advance amount (₹)', _advanceCtrl, keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 4),
        Text('Remaining: ₹${remaining.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Row(
          children: ['cash', 'online', 'card'].map((mode) {
            final selected = _paymentMode == mode;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => setState(() => _paymentMode = mode),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(mode,
                      style: TextStyle(fontSize: 11, color: selected ? Colors.white : AppColors.primary)),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 42,
          child: ElevatedButton(
            onPressed: _loading ? null : _createBooking,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Create Booking', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _wizardTextField(String label, TextEditingController ctrl,
      {TextInputType? keyboardType, void Function(String)? onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: TextField(
            controller: ctrl,
            keyboardType: keyboardType,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(border: InputBorder.none, isCollapsed: true),
          ),
        ),
      ],
    );
  }
}