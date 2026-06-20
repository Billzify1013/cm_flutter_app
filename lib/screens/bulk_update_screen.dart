import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';

class BulkUpdateScreen extends StatefulWidget {
  const BulkUpdateScreen({super.key});

  @override
  State<BulkUpdateScreen> createState() => _BulkUpdateScreenState();
}

class _BulkUpdateScreenState extends State<BulkUpdateScreen> {
  // 0 = Rate update, 1 = Inventory update
  int _mode = 0;

  late DateTime _start;
  late DateTime _end;

  // Selected weekdays (DateTime.weekday: 1=Mon ... 7=Sun)
  final Set<int> _selectedDays = {1, 2, 3, 4, 5, 6, 7};

  // Categories
  bool _loadingCats = true;
  List<String> _categories = [];
  final Set<String> _selectedCats = {};

  bool _saving = false;
  final _valueCtrl = TextEditingController(); // backup (summary ke liye)
  final Map<String, TextEditingController> _catControllers = {};

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _start = DateTime(n.year, n.month, n.day);
    _end = _start.add(const Duration(days: 1)); // default 2 din
    _loadCategories();
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    for (final c in _catControllers.values) c.dispose();
    super.dispose();
  }

  String _apiDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  String _prettyDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';

  // Date range pe weekday filter laga ke affected dates nikalo
  List<DateTime> get _affectedDates {
    final dates = <DateTime>[];
    var d = _start;
    while (!d.isAfter(_end)) {
      if (_selectedDays.contains(d.weekday)) dates.add(d);
      d = d.add(const Duration(days: 1));
    }
    return dates;
  }

  Future<void> _loadCategories() async {
    setState(() => _loadingCats = true);
    try {
      final uid = await ApiService.instance.getUserId();
      // Agle 30 din ka GET karo taaki max categories mile
      final res = await ApiService.instance.getData(
        AppConfig.inventory,
        query: {
          'user_id': uid,
          'start_date': _apiDate(_start),
          'end_date': _apiDate(_start.add(const Duration(days: 30))),
        },
      );
      final cats = <String>{};
      final updates = (res.data['updates'] as List?) ?? [];
      for (final u in updates) {
        final rooms = (u['rooms'] as List?) ?? [];
        for (final r in rooms) {
          final code = (r['roomCode'] ?? '').toString();
          if (code.isNotEmpty) cats.add(code);
        }
      }
      if (!mounted) return;
      setState(() {
        _categories = cats.toList()..sort();
        _selectedCats.addAll(_categories);
        // har category ka controller banao
        for (final c in _categories) {
          _catControllers.putIfAbsent(c, () => TextEditingController());
        }
        _loadingCats = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCats = false);
    }
  }

  Future<void> _pickRange() async {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) => _BulkDatePicker(
        initialStart: _start,
        initialEnd: _end,
        onConfirm: (start, end) {
          Navigator.pop(ctx);
          setState(() { _start = start; _end = end; });
        },
      ),
    );
  }

  Future<void> _apply() async {
    final hasAnyValue = _selectedCats.any(
            (c) => (_catControllers[c]?.text.trim() ?? '').isNotEmpty);
    if (!hasAnyValue) {
      _msg('Enter value for at least one category');
      return;
    }
    final valStr = ''; // per-category use hoga
    if (_selectedDays.isEmpty) {
      _msg('Select at least one day');
      return;
    }
    if (_selectedCats.isEmpty) {
      _msg('Select at least one category');
      return;
    }
    final affected = _affectedDates;
    if (affected.isEmpty) {
      _msg('No matching dates in this range');
      return;
    }

    // Confirm dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_mode == 0 ? 'Bulk rate update' : 'Bulk inventory update'),
        content: Text(
          '${_selectedCats.length} categories will be updated '
              'on ${affected.length} dates.\n\n'
              'Confirm?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      final uid = await ApiService.instance.getUserId();

      // Har affected date ke liye update entry banao
      final updates = <Map<String, dynamic>>[];
      for (final d in affected) {
        final ds = _apiDate(d);
        final rooms = <Map<String, dynamic>>[];
        for (final c in _selectedCats) {
          final catVal = _catControllers[c]?.text.trim() ?? '';
          if (catVal.isEmpty) continue; // empty chhod do
          if (_mode == 0) {
            rooms.add({'roomCode': c, 'price': catVal});
          } else {
            rooms.add({'roomCode': c, 'available': int.tryParse(catVal) ?? 0});
          }
        }
        updates.add({'startDate': ds, 'endDate': ds, 'rooms': rooms});
      }

      final res = await ApiService.instance.postData(
        AppConfig.inventory,
        {'user_id': uid, 'hotelCode': uid, 'updates': updates},
      );

      final status = (res.data['status'] ?? '').toString();
      final count = res.data['updated_records'] ?? 0;
      final warnings = (res.data['warnings'] as List?)?.join(', ') ?? '';

      if (!mounted) return;
      if (status == 'failed') {
        _msg('Failed. $warnings');
      } else if (warnings.isNotEmpty) {
        _msg('Updated $count records. Warning: $warnings');
      } else {
        _msg('✓ $count records updated successfully!');
      }
    } catch (e) {
      if (e is DioException) {
        print('BULK ERROR >>> ${e.response?.data}');
      }
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
    final affected = _affectedDates;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Bulk update',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
        body: RefreshIndicator(
          onRefresh: _loadCategories,
          color: AppColors.primary,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
        children: [
          // ---- Mode toggle ----
          _card(
            child: Row(
              children: [
                Expanded(child: _modeChip(0, 'Rate update', Icons.currency_rupee)),
                const SizedBox(width: 10),
                Expanded(child: _modeChip(1, 'Inventory', Icons.bed_outlined)),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ---- Date range ----
          _sectionTitle('Date range'),
          _card(
            child: GestureDetector(
              onTap: _pickRange,
              child: Row(
                children: [
                  const Icon(Icons.date_range_outlined,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_prettyDate(_start)}  –  ${_prettyDate(_end)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down,
                      color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ---- Weekday selector ----
          _sectionTitle('Days'),
          _card(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(7, (i) {
                final day = i + 1; // 1=Mon...7=Sun
                final sel = _selectedDays.contains(day);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (sel) {
                      if (_selectedDays.length > 1) _selectedDays.remove(day);
                    } else {
                      _selectedDays.add(day);
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primary : AppColors.background,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? AppColors.primary : AppColors.border,
                      ),
                    ),
                    child: Text(_dayLabels[i],
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : AppColors.textPrimary)),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),

          // ---- Category selector ----
          _sectionTitle('Categories'),
          _card(
            child: _loadingCats
                ? const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2),
              ),
            )
                : _categories.isEmpty
                ? const Text('No categories found',
                style: TextStyle(color: AppColors.textSecondary))
                : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // All toggle
                GestureDetector(
                  onTap: () => setState(() {
                    if (_selectedCats.length == _categories.length) {
                      _selectedCats.clear();
                      _selectedCats.add(_categories.first);
                    } else {
                      _selectedCats.addAll(_categories);
                    }
                  }),
                  child: Text(
                    _selectedCats.length == _categories.length
                        ? 'Deselect all'
                        : 'Select all',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categories.map((c) {
                    final sel = _selectedCats.contains(c);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (sel) {
                          if (_selectedCats.length > 1) {
                            _selectedCats.remove(c);
                          }
                        } else {
                          _selectedCats.add(c);
                        }
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: sel
                              ? AppColors.primary
                              : AppColors.background,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: sel
                                ? AppColors.primary
                                : AppColors.border,
                          ),
                        ),
                        child: Text(c,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: sel
                                    ? Colors.white
                                    : AppColors.textPrimary)),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ---- Value input (har category ka alag) ----
          _sectionTitle(_mode == 0 ? 'Price per category' : 'Available per category'),
          if (_selectedCats.isEmpty)
            const SizedBox()
          else
            ..._selectedCats.map((cat) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _card(
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(cat,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _catControllers[cat],
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        onSubmitted: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        decoration: InputDecoration(
                          hintText: _mode == 0 ? 'Price ₹' : 'Available',
                          isDense: true,
                          prefixIcon: Icon(
                              _mode == 0 ? Icons.currency_rupee : Icons.bed_outlined,
                              color: AppColors.textSecondary, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )),
          const SizedBox(height: 16),

          // ---- Summary pill ----
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  '${affected.length} dates · ${_selectedCats.length} categories '
                      '= ${affected.length * _selectedCats.length} records',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ---- Apply button ----
          ElevatedButton(
            onPressed: _saving ? null : _apply,
            child: _saving
                ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white))
                : Text(
              _mode == 0
                  ? 'Apply bulk rate update'
                  : 'Apply bulk inventory update',
            ),
          ),

          const SizedBox(height: 12),
          const Center(
            child: Text(
              'Note: Stop sell status is not changed in bulk update.',
              style:
              TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
        ],
          ),
        ),
    );
  }

  // ---- Helpers ----

  Widget _modeChip(int mode, String label, IconData icon) {
    final sel = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: sel ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: sel ? AppColors.primary : AppColors.border,
              width: sel ? 1.5 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18, color: sel ? Colors.white : AppColors.textPrimary),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary)),
  );

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    margin: const EdgeInsets.only(bottom: 0),
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
    child: child,
  );
}

class _BulkDatePicker extends StatefulWidget {
  final DateTime initialStart, initialEnd;
  final void Function(DateTime start, DateTime end) onConfirm;
  const _BulkDatePicker({
    required this.initialStart,
    required this.initialEnd,
    required this.onConfirm,
  });
  @override State<_BulkDatePicker> createState() => _BulkDatePickerState();
}

class _BulkDatePickerState extends State<_BulkDatePicker> {
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
        _start = day; _end = null; _pickingEnd = true;
      } else {
        if (day.isBefore(_start!)) {
          _start = day; _end = null;
        } else if (day.isAtSameMomentAs(_start!)) {
          _end = day; _pickingEnd = false;
        } else {
          _end = day; _pickingEnd = false;
        }
      }
    });
  }

  bool _inRange(DateTime d) =>
      _start != null && _end != null && d.isAfter(_start!) && d.isBefore(_end!);
  bool _isStart(DateTime d) => _start != null && DateUtils.isSameDay(d, _start!);
  bool _isEnd(DateTime d) => _end != null && DateUtils.isSameDay(d, _end!);

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final daysInMonth = DateUtils.getDaysInMonth(_viewMonth.year, _viewMonth.month);
    final firstWd = _viewMonth.weekday;

    String instruction;
    if (_start != null && _end != null) {
      final days = _end!.difference(_start!).inDays + 1;
      instruction = '${_fmt(_start!)}  →  ${_fmt(_end!)}  ($days days)';
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
          Row(children: [
            Expanded(child: Text(
                '${_months[_viewMonth.month - 1]} ${_viewMonth.year}',
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: (_start != null && _end != null)
                  ? AppColors.accentSoft : AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: (_start != null && _end != null)
                      ? AppColors.primary : AppColors.border),
            ),
            child: Text(instruction,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12,
                    fontWeight: (_start != null && _end != null)
                        ? FontWeight.w600 : FontWeight.w400,
                    color: (_start != null && _end != null)
                        ? AppColors.primary : AppColors.textSecondary)),
          ),
          const SizedBox(height: 12),
          Row(children: _days.map((d) => Expanded(
            child: Center(child: Text(d,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary))),
          )).toList()),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7, mainAxisSpacing: 3, crossAxisSpacing: 3),
            itemCount: (firstWd - 1) + daysInMonth,
            itemBuilder: (ctx, i) {
              if (i < firstWd - 1) return const SizedBox();
              final day = DateTime(_viewMonth.year, _viewMonth.month, i - (firstWd - 2));
              final isToday = DateUtils.isSameDay(day, today);
              final isSt = _isStart(day);
              final isEn = _isEnd(day);
              final inR = _inRange(day);

              return GestureDetector(
                onTap: () => _onDay(day),
                child: Container(
                  decoration: BoxDecoration(
                    color: (isSt || isEn) ? AppColors.primary
                        : inR ? AppColors.accentSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(child: Text('${day.day}',
                      style: TextStyle(fontSize: 13,
                          fontWeight: (isSt || isEn || isToday)
                              ? FontWeight.w700 : FontWeight.w400,
                          color: (isSt || isEn) ? Colors.white
                              : isToday ? AppColors.primary
                              : AppColors.textPrimary))),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_start != null && _end != null)
                  ? () => widget.onConfirm(_start!, _end!) : null,
              child: const Text('Apply'),
            ),
          ),
        ]),
      ),
    );
  }
}