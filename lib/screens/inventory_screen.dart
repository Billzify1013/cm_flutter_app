import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late DateTime _start;
  late DateTime _end;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  int _rev = 0;

  final Map<String, Map<String, dynamic>> _data = {};
  List<String> _categories = [];

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];
  static const _weekdays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _start = DateTime(n.year, n.month, n.day);
    _end = _start; // default: single day
    _load();
  }

  List<DateTime> get _days {
    final days = <DateTime>[];
    var d = _start;
    while (!d.isAfter(_end)) {
      days.add(d);
      d = d.add(const Duration(days: 1));
    }
    return days;
  }

  String _apiDate(DateTime d) =>
      '${d.year.toString().padLeft(4,'0')}-'
          '${d.month.toString().padLeft(2,'0')}-'
          '${d.day.toString().padLeft(2,'0')}';

  String _pretty(DateTime d) =>
      '${_weekdays[d.weekday-1]}, '
          '${d.day.toString().padLeft(2,'0')} ${_months[d.month-1]}';

  String _key(DateTime d, String cat) => '${_apiDate(d)}|$cat';

  int get _rangeSize => _end.difference(_start).inDays + 1;

  void _moveWindow(int days) {
    setState(() {
      _start = _start.add(Duration(days: days));
      _end = _end.add(Duration(days: days));
    });
    _load();
  }

  Future<void> _pickRange() async {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) => _InventoryDatePicker(
        initialStart: _start,
        initialEnd: _end,
        onConfirm: (start, end) {
          Navigator.pop(ctx);
          setState(() { _start = start; _end = end; });
          _load();
        },
      ),
    );
  }

  bool get _isSingleDay => _apiDate(_start) == _apiDate(_end);

  bool _isStopSell(DateTime d) {
    if (_categories.isEmpty) return false;
    return _data[_key(d, _categories.first)]?['stopSell'] == true;
  }

  void _setStopSell(DateTime d, bool val) {
    setState(() {
      for (final c in _categories) {
        _data[_key(d, c)]?['stopSell'] = val;
      }
    });
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.getData(
        AppConfig.inventory,
        query: {
          'user_id': uid,
          'start_date': _apiDate(_days.first),
          'end_date': _apiDate(_days.last),
        },
      );

      _data.clear();
      final cats = <String>{};
      final updates = (res.data['updates'] as List?) ?? [];
      for (final u in updates) {
        final dateStr = (u['date'] ?? '').toString();
        final rooms = (u['rooms'] as List?) ?? [];
        for (final r in rooms) {
          final code = (r['roomCode'] ?? '').toString();
          if (code.isEmpty) continue;
          cats.add(code);
          _data['$dateStr|$code'] = {
            'available': (r['available'] as num?)?.toInt() ?? 0,
            'price': (r['price'] ?? '0').toString(),
            'stopSell': (r['restrictions']?['stopSell'] ?? false) == true,
          };
        }
      }

      print('LOAD RESPONSE >>> ${res.data}');
      _categories = cats.toList()..sort();
      for (final d in _days) {
        for (final c in _categories) {
          _data.putIfAbsent(
            _key(d, c),
                () => {'available': 0, 'price': '0', 'stopSell': false},
          );
        }
      }

      if (!mounted) return;
      setState(() { _rev++; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final uid = await ApiService.instance.getUserId();
      final updates = <Map<String, dynamic>>[];
      for (final d in _days) {
        final ds = _apiDate(d);
        final rooms = <Map<String, dynamic>>[];
        for (final c in _categories) {
          final v = _data[_key(d, c)]!;
          rooms.add({
            'roomCode': c,
            'available': v['available'],
            'price': v['price'],
            'restrictions': {'stopSell': v['stopSell']},
          });
        }
        if (rooms.isNotEmpty) {
          updates.add({'startDate': ds, 'endDate': ds, 'rooms': rooms});
        }
      }
      final res = await ApiService.instance.postData(
        AppConfig.inventory,
        {'user_id': uid, 'hotelCode': uid, 'updates': updates},
      );
      print('SAVE RESPONSE >>> ${res.data}');
      final status = (res.data['status'] ?? '').toString();
      final count = res.data['updated_records'] ?? 0;
      final warnings = (res.data['warnings'] as List?)?.join(', ') ?? '';
      if (!mounted) return;
      if (status == 'failed') {
        _msg('Save failed. $warnings');
      } else if (warnings.isNotEmpty) {
        _msg('Saved $count records. Warning: $warnings');
      } else {
        _msg('Inventory updated ✓ ($count records)');
      }
      _load();
    } catch (e) {
      if (e is DioException) {
        print('SAVE DETAIL >>> ${e.response?.data}');
      }
      print('SAVE ERROR >>> $e');
      if (!mounted) return;
      _msg(friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _msg(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory & Rate update',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          _windowBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: _body(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _saveBar(),
    );
  }

  Widget _windowBar() {
    final dateText = _start == _end || _apiDate(_start) == _apiDate(_end)
        ? _pretty(_start)
        : '${_pretty(_start)}  –  ${_pretty(_end)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            InkWell(
              onTap: () => _moveWindow(-_rangeSize),
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 36, height: 36,
                child: Icon(Icons.chevron_left,
                    color: AppColors.primary, size: 24),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: _pickRange,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(dateText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.date_range_outlined,
                        size: 14, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: () => _moveWindow(_rangeSize),
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 36, height: 36,
                child: Icon(Icons.chevron_right,
                    color: AppColors.primary, size: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 2.5));
    }
    if (_error != null) {
      return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
          ));
    }
    if (_categories.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No inventory data for these dates.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        for (final d in _days) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Row(
              children: [
                Text(_pretty(d),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                if (_isSingleDay) ...[
                  const Spacer(),
                  const Text('Stop sell',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(width: 4),
                  Switch(
                    value: _isStopSell(d),
                    activeColor: AppColors.primary,
                    onChanged: (val) => _setStopSell(d, val),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ],
            ),
          ),
          for (final c in _categories) _categoryCard(d, c),
        ],
      ],
    );
  }

  Widget _categoryCard(DateTime d, String cat) {
    final v = _data[_key(d, cat)]!;
    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(cat,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('a|$_rev|${_key(d, cat)}'),
                  initialValue: v['available'].toString(),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Available',
                    isDense: true,
                  ),
                  onChanged: (val) {
                    _data[_key(d, cat)]!['available'] = int.tryParse(val) ?? 0;
                  },
                  onFieldSubmitted: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  key: ValueKey('p|$_rev|${_key(d, cat)}'),
                  initialValue: v['price'].toString(),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Price ₹',
                    isDense: true,
                  ),
                  onChanged: (val) {
                    _data[_key(d, cat)]!['price'] = val.trim().isEmpty ? '0' : val.trim();
                  },
                  onFieldSubmitted: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _saveBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: ElevatedButton(
          onPressed: (_saving || _categories.isEmpty) ? null : _save,
          child: _saving
              ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: Colors.white))
              : const Text('Save changes'),
        ),
      ),
    );
  }
}

// ── Inventory date range picker dialog ──
class _InventoryDatePicker extends StatefulWidget {
  final DateTime initialStart, initialEnd;
  final void Function(DateTime start, DateTime end) onConfirm;
  const _InventoryDatePicker({
    required this.initialStart,
    required this.initialEnd,
    required this.onConfirm,
  });
  @override
  State<_InventoryDatePicker> createState() => _InventoryDatePickerState();
}

class _InventoryDatePickerState extends State<_InventoryDatePicker> {
  DateTime? _start, _end;
  bool _pickingEnd = false;
  late DateTime _viewMonth;

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];
  static const _days = ['Mo','Tu','We','Th','Fr','Sa','Su'];

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _viewMonth = DateTime(_start!.year, _start!.month, 1);
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';

  void _onDay(DateTime day) {
    setState(() {
      if (!_pickingEnd) {
        _start = day;
        _end = null;
        _pickingEnd = true;
      } else {
        if (day.isBefore(_start!)) {
          _start = day;
          _end = null;
        } else if (day.isAtSameMomentAs(_start!)) {
          // Same day = single day range
          _end = day;
          _pickingEnd = false;
        } else {
          _end = day;
          _pickingEnd = false;
        }
      }
    });
  }

  bool _inRange(DateTime d) =>
      _start != null &&
          _end != null &&
          d.isAfter(_start!) &&
          d.isBefore(_end!);

  bool _isStart(DateTime d) =>
      _start != null && DateUtils.isSameDay(d, _start!);
  bool _isEnd(DateTime d) =>
      _end != null && DateUtils.isSameDay(d, _end!);

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final daysInMonth =
    DateUtils.getDaysInMonth(_viewMonth.year, _viewMonth.month);
    final firstWd = _viewMonth.weekday;

    String instruction;
    if (_start != null && _end != null) {
      final nights = _end!.difference(_start!).inDays;
      instruction = '${_fmt(_start!)}  →  ${_fmt(_end!)}  ($nights ${nights == 1 ? 'day' : 'days'})';
    } else if (_start != null) {
      instruction = 'Now select end date';
    } else {
      instruction = 'Select start date';
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Row(children: [
            Expanded(
                child: Text(
                    '${_months[_viewMonth.month - 1]} ${_viewMonth.year}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700))),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _viewMonth =
                  DateTime(_viewMonth.year, _viewMonth.month - 1, 1)),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() => _viewMonth =
                  DateTime(_viewMonth.year, _viewMonth.month + 1, 1)),
            ),
          ]),

          // Instruction
          Container(
            width: double.infinity,
            padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: (_start != null && _end != null)
                  ? AppColors.accentSoft
                  : AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (_start != null && _end != null)
                    ? AppColors.primary
                    : AppColors.border,
              ),
            ),
            child: Text(instruction,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: (_start != null && _end != null)
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: (_start != null && _end != null)
                      ? AppColors.primary
                      : AppColors.textSecondary,
                )),
          ),
          const SizedBox(height: 12),

          // Day labels
          Row(
              children: _days
                  .map((d) => Expanded(
                child: Center(
                    child: Text(d,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary))),
              ))
                  .toList()),
          const SizedBox(height: 6),

          // Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 3,
                crossAxisSpacing: 3),
            itemCount: (firstWd - 1) + daysInMonth,
            itemBuilder: (ctx, i) {
              if (i < firstWd - 1) return const SizedBox();
              final day = DateTime(
                  _viewMonth.year, _viewMonth.month, i - (firstWd - 2));
              final isToday = DateUtils.isSameDay(day, today);
              final isSt = _isStart(day);
              final isEn = _isEnd(day);
              final inR = _inRange(day);

              return GestureDetector(
                onTap: () => _onDay(day),
                child: Container(
                  decoration: BoxDecoration(
                    color: (isSt || isEn)
                        ? AppColors.primary
                        : inR
                        ? AppColors.accentSoft
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('${day.day}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: (isSt || isEn || isToday)
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: (isSt || isEn)
                              ? Colors.white
                              : isToday
                              ? AppColors.primary
                              : AppColors.textPrimary,
                        )),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          // Confirm button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_start != null && _end != null)
                  ? () => widget.onConfirm(_start!, _end!)
                  : null,
              child: const Text('Apply'),
            ),
          ),
        ]),
      ),
    );
  }
}