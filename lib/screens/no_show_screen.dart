import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';

class NoShowScreen extends StatefulWidget {
  const NoShowScreen({super.key});

  @override
  State<NoShowScreen> createState() => _NoShowScreenState();
}

class _NoShowScreenState extends State<NoShowScreen> {
  bool _loading = true;
  String _errorMsg = '';
  List<dynamic> _data = [];
  String _dateLabel = '';
  final Set<int> _processingIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMsg = '';
    });
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.getData(
        AppConfig.noShowList,
        query: {'user_id': uid},
      );
      if (!mounted) return;
      setState(() {
        _data = (res.data['data'] as List?) ?? [];
        _dateLabel = (res.data['date'] ?? '').toString();
        _loading = false;
      });
    } catch (e) {
      print('NOSHOW ERROR >>> $e');
      if (e is DioException) {
        print('NOSHOW RESPONSE >>> ${e.response?.data}');
        print('NOSHOW STATUS >>> ${e.response?.statusCode}');
      }
      if (!mounted) return;
      setState(() {
        _data = [];
        _errorMsg = friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _markNoShow(dynamic booking) async {
    final id = booking['id'] as int;
    if (_processingIds.contains(id)) return;

    setState(() => _processingIds.add(id));
    try {
      final res = await ApiService.instance
          .postData('${AppConfig.markNoShow}$id/', {});
      final success = res.data['success'] == true;
      final message = (res.data['message'] ?? '').toString();

      if (!mounted) return;
      if (success) {
        setState(() {
          booking['is_noshow'] = true;
          booking['action'] = 'cancel';
        });
        _msg(message.isNotEmpty ? message : 'Marked as no-show ✓');
      } else {
        _msg(message.isNotEmpty ? message : 'Failed to mark no-show');
      }
    } catch (e) {
      if (!mounted) return;
      _msg(friendlyError(e));
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }

  void _msg(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('No Show',
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
          : RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: Column(
          children: [
            if (_dateLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 15, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'Showing bookings for $_dateLabel',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _data.isEmpty
                  ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 80),
                  Center(
                    child: Text(
                      _errorMsg.isNotEmpty
                          ? _errorMsg
                          : 'No bookings found',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.textSecondary),
                    ),
                  ),
                ],
              )
                  : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                itemCount: _data.length,
                itemBuilder: (ctx, i) =>
                    _bookingCard(_data[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bookingCard(dynamic g) {
    final name = (g['guest_name'] ?? '-').toString();
    final phone = (g['guest_phone'] ?? '').toString();
    final channel = (g['channel_name'] ?? '').toString();
    final bookingRef = (g['booking_id'] ?? '').toString();
    final action = (g['action'] ?? '').toString();
    final isNoShow = g['is_noshow'] == true;
    final checkIn = (g['booking_date'] ?? '').toString();
    final checkOut = (g['checkout_date'] ?? '').toString();
    final stayDays = g['stay_days'];
    final amount = (g['total_amount'] ?? '0').toString();
    final payment = (g['payment_type'] ?? '').toString();
    final roomSummary = (g['room_categories_summary'] ?? '').toString();
    final id = g['id'] as int;
    final isProcessing = _processingIds.contains(id);
    final isCancelled = action == 'cancel';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        decoration:
                        isCancelled ? TextDecoration.lineThrough : null,
                        color: isCancelled
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (phone.isNotEmpty)
                      Text(phone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            decoration: isCancelled
                                ? TextDecoration.lineThrough
                                : null,
                          )),
                  ],
                ),
              ),
              if (bookingRef.isNotEmpty)
                Text('#$bookingRef',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 6),
          Text('$channel  ·  $bookingRef',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _badge('$checkIn to $checkOut (D: $stayDays)',
                  AppColors.accentSoft, AppColors.primary),
              if (payment.isNotEmpty) _paymentBadge(payment),
              _statusBadge(action),
            ],
          ),
          if (roomSummary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(roomSummary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Text('\u20B9$amount',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const Spacer(),
              if (isNoShow)
                _badge('No Show Done', AppColors.successSoft, AppColors.success)
              else
                SizedBox(
                  height: 34,
                  child: ElevatedButton(
                    onPressed: isProcessing ? null : () => _markNoShow(g),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: isProcessing
                        ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                        : const Text('No Show',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
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
}