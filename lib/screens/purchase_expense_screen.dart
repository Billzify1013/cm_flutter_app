import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:dio/dio.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';

class PurchaseExpenseScreen extends StatefulWidget {
  const PurchaseExpenseScreen({super.key});
  @override State<PurchaseExpenseScreen> createState() => _PEState();
}

class _PEState extends State<PurchaseExpenseScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = true;
  String? _error;
  List _suppliers = [], _products = [], _purchases = [],
      _expenses = [], _expCats = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _load();
  }

  @override void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(
          AppConfig.purchaseExpenseData, {'user_id': uid});
      if (!mounted) return;
      setState(() {
        _suppliers = res.data['suppliers'] ?? [];
        _products  = res.data['products'] ?? [];
        _purchases = res.data['purchases'] ?? [];
        _expenses  = res.data['expenses'] ?? [];
        _expCats   = res.data['expense_categories'] ?? [];
        _loading   = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m),
      duration: const Duration(seconds: 2)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Purchase & Expense',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        leading: IconButton(icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
      ),
      body: Column(children: [
        Container(
          color: AppColors.card,
          child: TabBar(
            controller: _tabs,
            isScrollable: false,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
            tabs: const [
              Tab(text: 'Purchases'),
              Tab(text: 'Expenses'),
              Tab(text: 'Suppliers'),
              Tab(text: 'Products'),
              Tab(text: 'Stock log'),
            ],
          ),
        ),
        Expanded(child: _loading
            ? _skeleton()
            : _error != null
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ]))
            : TabBarView(controller: _tabs, children: [
          _purchasesTab(),
          _expensesTab(),
          _suppliersTab(),
          _productsTab(),
          _StockLogTab(),
        ])),
      ]),
      floatingActionButton: _loading ? null : _fab(),
    );
  }

  Widget _fab() => AnimatedBuilder(
      animation: _tabs,
      builder: (_, __) {
        final labels = ['Add purchase','Add expense','Add supplier','Add product',''];
        final label = labels[_tabs.index];
        if (label.isEmpty) return const SizedBox();
        return FloatingActionButton.extended(
          onPressed: () {
            if (_tabs.index == 0) _showPurchaseSheet();
            if (_tabs.index == 1) _showExpenseSheet();
            if (_tabs.index == 2) _showSupplierSheet();
            if (_tabs.index == 3) _showProductSheet();
          },
          backgroundColor: AppColors.primary,
          icon: const Icon(Icons.add, color: Colors.white),
          label: Text(label, style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
        );
      });

  // ── TABS ──
  Widget _purchasesTab() => _purchases.isEmpty
      ? _empty('No purchases yet')
      : RefreshIndicator(onRefresh: _load, color: AppColors.primary,
      child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16,12,16,80),
          itemCount: _purchases.length,
          itemBuilder: (_, i) => _purchaseCard(_purchases[i])));

  Widget _purchaseCard(Map p) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(p['supplier_name']?.toString() ?? '-',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          _statusBadge(p['payment_status']?.toString() ?? 'unpaid'),
          _popMenu([
            _popItem(Icons.edit_outlined, 'Edit', () => _editPurchase(p)),
            _popItem(Icons.delete_outline, 'Delete',
                    () => _confirmDelete('purchase', () => _deletePurchase(p['id'])),
                danger: true),
          ]),
        ]),
        Text('${p['bill_date']}  •  Bill: ${p['bill_number']?.toString().isNotEmpty == true ? p['bill_number'] : '-'}',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Row(children: [
          _amtCell('Total', p['grand_total']),
          _amtCell('Paid', p['paid_amount'], color: AppColors.success),
          _amtCell('Pending', p['pending_amount'],
              color: (p['pending_amount'] as num) > 0 ? const Color(0xFFB91C1C) : AppColors.success),
        ]),
      ]));

  Widget _expensesTab() => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(16,8,16,0),
        child: Align(alignment: Alignment.centerRight,
            child: TextButton.icon(onPressed: _showAddCategorySheet,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add category', style: TextStyle(fontSize: 12))))),
    Expanded(child: _expenses.isEmpty
        ? _empty('No expenses yet')
        : RefreshIndicator(onRefresh: _load, color: AppColors.primary,
        child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16,4,16,80),
            itemCount: _expenses.length,
            itemBuilder: (_, i) => _expenseCard(_expenses[i])))),
  ]);

  Widget _expenseCard(Map e) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(e['title']?.toString() ?? '-',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          _statusBadge(e['payment_status']?.toString() ?? 'unpaid'),
          _popMenu([
            _popItem(Icons.edit_outlined, 'Edit', () => _showExpenseSheet(data: e)),
            _popItem(Icons.delete_outline, 'Delete',
                    () => _confirmDelete('expense', () => _deleteExpense(e['id'])),
                danger: true),
          ]),
        ]),
        Row(children: [
          Text(e['category_name']?.toString() ?? '-',
              style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
          const Text('  •  ', style: TextStyle(color: AppColors.textSecondary)),
          Text(e['expense_date']?.toString() ?? '-',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ]),
        if ((e['supplier_name'] ?? '').toString().isNotEmpty)
          Text(e['supplier_name'].toString(),
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Row(children: [
          _amtCell('Amount', e['amount']),
          _amtCell('GST', e['gst_amount']),
          _amtCell('Total', e['total_amount'], bold: true),
          _amtCell('Pending', e['pending_amount'],
              color: (e['pending_amount'] as num) > 0 ? const Color(0xFFB91C1C) : AppColors.success),
        ]),
      ]));

  Widget _suppliersTab() => _suppliers.isEmpty
      ? _empty('No suppliers yet')
      : RefreshIndicator(onRefresh: _load, color: AppColors.primary,
      child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16,12,16,80),
          itemCount: _suppliers.length,
          itemBuilder: (_, i) => _supplierCard(_suppliers[i])));

  Widget _supplierCard(Map s) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(),
      child: Row(children: [
        Container(width: 40, height: 40,
            decoration: BoxDecoration(color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.store_outlined, color: AppColors.primary, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['name']?.toString() ?? '-',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          Text((s['phone']?.toString().isNotEmpty == true) ? s['phone'] : 'No phone',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (s['is_gst_registered'] == true)
            Text(s['gstnumber']?.toString() ?? '',
                style: const TextStyle(fontSize: 11, color: AppColors.primary)),
        ])),
        _popMenu([
          _popItem(Icons.edit_outlined, 'Edit', () => _showSupplierSheet(data: s)),
          _popItem(Icons.delete_outline, 'Delete',
                  () => _confirmDelete('supplier', () => _deleteSupplier(s['id'])),
              danger: true),
        ]),
      ]));

  Widget _productsTab() => _products.isEmpty
      ? _empty('No products')
      : RefreshIndicator(onRefresh: _load, color: AppColors.primary,
      child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16,12,16,80),
          itemCount: _products.length,
          itemBuilder: (_, i) {
            final p = _products[i];
            if (p == null) return const SizedBox();
            return _productCard(Map<String,dynamic>.from(p as Map));
          }));

  Widget _productCard(Map p) {
    final stock = (p['stock_quantity'] as num?)?.toInt() ?? 0;
    final low   = (p['low_stock_alert'] as num?)?.toInt() ?? 0;
    final isLow = stock <= low;
    return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isLow ? const Color(0xFFFCA5A5) : AppColors.border)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['name']?.toString() ?? '-',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Text('SKU: ${p['sku'] ?? '-'}  •  GST: ${p['gst_rate']}%  •  '
                'Base: ₹${p['base_price']}  •  Sell: ₹${p['selling_price']}',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Stock: $stock', style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isLow ? const Color(0xFFB91C1C) : AppColors.textPrimary)),
            if (isLow)
              Container(margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFFDE7E7),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('Low', style: TextStyle(fontSize: 9,
                      fontWeight: FontWeight.w700, color: Color(0xFFB91C1C)))),
            _popMenu([
              _popItem(Icons.edit_outlined, 'Edit', () => _showProductSheet(data: p)),
              _popItem(Icons.delete_outline, 'Delete',
                      () => _confirmDelete('product', () => _deleteProduct(p['id'])),
                  danger: true),
            ]),
          ]),
        ]));
  }

  // ── SHEET OPENERS ──
  void _showPurchaseSheet({Map? data}) {
    if (data != null) {
      _loadAndShowPurchase(data);
    } else {
      _openPurchaseSheet(null, const []);
    }
  }

  Future<void> _loadAndShowPurchase(Map data) async {
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(
          AppConfig.purchaseItems, {'user_id': uid, 'purchase_id': data['id']});
      if (!mounted) return;
      _openPurchaseSheet(
          Map<String,dynamic>.from(res.data['bill'] ?? {}),
          List.from(res.data['items'] ?? []));
    } catch (e) { _snack(friendlyError(e)); }
  }

  void _openPurchaseSheet(Map? billData, List items) {
    _openSheet(_PurchaseForm(
      suppliers: List<Map<String,dynamic>>.from(_suppliers),
      products:  List<Map<String,dynamic>>.from(_products),
      initialData: billData,
      initialItems: items,
      onSave: (p) async {
        final uid = await ApiService.instance.getUserId();
        final r = await ApiService.instance.postData(
            AppConfig.purchaseSave, {'user_id': uid, ...p});
        _snack(r.data['message'] ?? 'Saved'); _load();
      },
    ));
  }

  void _editPurchase(Map p) => _showPurchaseSheet(data: p);

  Future<void> _deletePurchase(dynamic id) async {
    try {
      final uid = await ApiService.instance.getUserId();
      final r = await ApiService.instance.postData(
          AppConfig.purchaseDelete, {'user_id': uid, 'purchase_id': id});
      _snack(r.data['message'] ?? 'Deleted'); _load();
    } catch (e) { _snack(friendlyError(e)); }
  }

  void _showExpenseSheet({Map? data}) => _openSheet(_ExpenseForm(
    categories: List<Map<String,dynamic>>.from(_expCats),
    suppliers:  List<Map<String,dynamic>>.from(_suppliers),
    initialData: data,
    onSave: (p) async {
      final uid = await ApiService.instance.getUserId();
      final r = await ApiService.instance.postData(
          AppConfig.expenseSave, {'user_id': uid, ...p});
      _snack(r.data['message'] ?? 'Saved'); _load();
    },
  ));

  Future<void> _deleteExpense(dynamic id) async {
    try {
      final uid = await ApiService.instance.getUserId();
      final r = await ApiService.instance.postData(
          AppConfig.expenseDelete, {'user_id': uid, 'expense_id': id});
      _snack(r.data['message'] ?? 'Deleted'); _load();
    } catch (e) { _snack(friendlyError(e)); }
  }

  void _showAddCategorySheet() {
    final ctrl = TextEditingController();
    _openSheet(Builder(builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Add category',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      const Text('Category name', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      const SizedBox(height: 4),
      TextField(controller: ctrl, decoration: const InputDecoration(isDense: true)),
      const SizedBox(height: 20),
      _fullBtn('Save category', () async {
        final name = ctrl.text.trim();
        if (name.isEmpty) { _snack('Enter name'); return; }
        Navigator.pop(ctx);
        try {
          final uid = await ApiService.instance.getUserId();
          final r = await ApiService.instance.postData(
              AppConfig.expenseCategorySave, {'user_id': uid, 'name': name});
          _snack(r.data['message'] ?? 'Saved'); _load();
        } catch (e) { _snack(friendlyError(e)); }
      }),
    ])));
  }

  void _showSupplierSheet({Map? data}) => _openSheet(_SupplierForm(
    initialData: data,
    onSave: (p) async {
      final uid = await ApiService.instance.getUserId();
      final r = await ApiService.instance.postData(
          AppConfig.supplierSave, {'user_id': uid, ...p});
      _snack(r.data['message'] ?? 'Saved'); _load();
    },
  ));

  Future<void> _deleteSupplier(dynamic id) async {
    try {
      final uid = await ApiService.instance.getUserId();
      final r = await ApiService.instance.postData(
          AppConfig.supplierDelete, {'user_id': uid, 'supplier_id': id});
      _snack(r.data['message'] ?? 'Deleted'); _load();
    } catch (e) { _snack(friendlyError(e)); }
  }

  void _showProductSheet({Map? data}) => _openSheet(_ProductForm(
    initialData: data,
    onSave: (p) async {
      final uid = await ApiService.instance.getUserId();
      final endpoint = data != null ? AppConfig.productEdit : AppConfig.productCreate;
      final r = await ApiService.instance.postData(endpoint, {'user_id': uid, ...p});
      _snack(r.data['message'] ?? 'Saved'); _load();
    },
  ));

  Future<void> _deleteProduct(dynamic id) async {
    try {
      final uid = await ApiService.instance.getUserId();
      final r = await ApiService.instance.postData(
          AppConfig.productDelete, {'user_id': uid, 'product_id': id});
      _snack(r.data['message'] ?? 'Deleted'); _load();
    } catch (e) { _snack(friendlyError(e)); }
  }

  // ── SHEET WRAPPER ──
  void _openSheet(Widget child) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(
            viewInsets: MediaQuery.of(ctx).viewInsets),
        child: Container(
          decoration: const BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border,
                    borderRadius: BorderRadius.circular(2))),
            Align(alignment: Alignment.centerRight,
                child: IconButton(
                    icon: Container(width: 30, height: 30,
                        decoration: BoxDecoration(color: AppColors.background,
                            borderRadius: BorderRadius.circular(20)),
                        child: const Icon(Icons.close, size: 16, color: AppColors.textSecondary)),
                    onPressed: () => Navigator.pop(ctx))),
            Flexible(child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 0, 20,
                    MediaQuery.of(ctx).viewInsets.bottom + 24),
                child: child)),
          ]),
        ),
      ),
    );
  }

  void _confirmDelete(String label, VoidCallback fn) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('Delete $label'),
      content: const Text('Are you sure?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC0392B)),
            onPressed: () { Navigator.pop(context); fn(); },
            child: const Text('Delete', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  // ── HELPERS ──
  BoxDecoration _cardDeco() => BoxDecoration(color: AppColors.card,
      borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border),
      boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0,3))]);

  Widget _amtCell(String l, dynamic v, {Color? color, bool bold = false}) =>
      Expanded(child: Column(children: [
        Text(l, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        Text('₹${(v as num).toStringAsFixed(0)}', style: TextStyle(
            fontSize: 12, fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: color ?? AppColors.textPrimary)),
      ]));

  Widget _statusBadge(String s) {
    Color bg, fg; String label;
    switch (s) {
      case 'paid': bg = AppColors.successSoft; fg = AppColors.success; label = 'Paid'; break;
      case 'partial': bg = const Color(0xFFFEF6DC); fg = const Color(0xFF9A7B0A); label = 'Partial'; break;
      default: bg = const Color(0xFFFDE7E7); fg = const Color(0xFFC0392B); label = 'Unpaid';
    }
    return Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)));
  }

  PopupMenuButton _popMenu(List<PopupMenuEntry> items) => PopupMenuButton(
      icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textSecondary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => items);

  PopupMenuItem _popItem(IconData icon, String label, VoidCallback fn,
      {bool danger = false}) => PopupMenuItem(onTap: fn,
      child: Row(children: [
        Icon(icon, size: 16, color: danger ? const Color(0xFFC0392B) : AppColors.textPrimary),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 13,
            color: danger ? const Color(0xFFC0392B) : AppColors.textPrimary)),
      ]));

  Widget _empty(String msg) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.inbox_outlined, size: 48, color: AppColors.textSecondary.withOpacity(0.4)),
    const SizedBox(height: 8),
    Text(msg, style: const TextStyle(color: AppColors.textSecondary)),
  ]));

  Widget _skeleton() => Shimmer.fromColors(
      baseColor: const Color(0xFFE8E8E8), highlightColor: const Color(0xFFF5F5F5),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        ...List.generate(5, (_) => Container(margin: const EdgeInsets.only(bottom: 12),
            height: 90, decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(16)))),
      ]));

  static Widget _fullBtn(String label, VoidCallback fn, {bool danger = false}) =>
      SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: fn,
          style: ElevatedButton.styleFrom(
              backgroundColor: danger ? const Color(0xFFC0392B) : AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))));
}

// ══════════════════════════════════════════
// STOCK LOG TAB
// ══════════════════════════════════════════
class _StockLogTab extends StatefulWidget {
  const _StockLogTab();
  @override State<_StockLogTab> createState() => _StockLogTabState();
}

class _StockLogTabState extends State<_StockLogTab>
    with SingleTickerProviderStateMixin {
  late TabController _inner;
  bool _loading = true;
  List _stockLogs = [], _txnLogs = [];

  @override
  void initState() {
    super.initState();
    _inner = TabController(length: 2, vsync: this);
    _load();
  }

  @override void dispose() { _inner.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = await ApiService.instance.getUserId();
      final r1  = await ApiService.instance.postData(
          AppConfig.stockLogs, {'user_id': uid});
      final r2  = await ApiService.instance.postData(
          AppConfig.txnLogs, {'user_id': uid});
      if (!mounted) return;
      setState(() {
        _stockLogs = r1.data['logs'] ?? [];
        _txnLogs   = r2.data['logs'] ?? [];
        _loading   = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Shimmer.fromColors(
        baseColor: const Color(0xFFE8E8E8), highlightColor: const Color(0xFFF5F5F5),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          ...List.generate(6, (_) => Container(margin: const EdgeInsets.only(bottom: 10),
              height: 60, decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(12)))),
        ]));

    return Column(children: [
      Container(
        color: AppColors.card,
        child: TabBar(
          controller: _inner,
          isScrollable: false,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          tabs: const [Tab(text: 'Stock log'), Tab(text: 'Activity log')],
        ),
      ),
      Expanded(child: TabBarView(controller: _inner, children: [
        // ── Stock log ──
        _stockLogs.isEmpty
            ? const Center(child: Text('No stock movements',
            style: TextStyle(color: AppColors.textSecondary)))
            : RefreshIndicator(onRefresh: _load, color: AppColors.primary,
            child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16,12,16,16),
                itemCount: _stockLogs.length,
                itemBuilder: (_, i) {
                  final log = _stockLogs[i] as Map;
                  final isIn = log['type']?.toString().toUpperCase() == 'IN';
                  return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border)),
                      child: Row(children: [
                        Container(width: 36, height: 36,
                            decoration: BoxDecoration(
                                color: isIn ? AppColors.successSoft : const Color(0xFFFDE7E7),
                                borderRadius: BorderRadius.circular(8)),
                            child: Icon(isIn ? Icons.arrow_downward : Icons.arrow_upward,
                                size: 18,
                                color: isIn ? AppColors.success : const Color(0xFFC0392B))),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(log['product_name']?.toString() ?? '-',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(log['reference']?.toString() ?? '-',
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          Text(log['created_at']?.toString() ?? '',
                              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('${isIn ? '+' : '-'}${log['quantity']}',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                                  color: isIn ? AppColors.success : const Color(0xFFC0392B))),
                          Text(isIn ? 'IN' : 'OUT', style: TextStyle(fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isIn ? AppColors.success : const Color(0xFFC0392B))),
                        ]),
                      ]));
                })),

        // ── Activity log ──
        _txnLogs.isEmpty
            ? const Center(child: Text('No activity logs',
            style: TextStyle(color: AppColors.textSecondary)))
            : RefreshIndicator(onRefresh: _load, color: AppColors.primary,
            child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16,12,16,16),
                itemCount: _txnLogs.length,
                itemBuilder: (_, i) {
                  final log = _txnLogs[i] as Map;
                  return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border)),
                      child: Row(children: [
                        Container(width: 36, height: 36,
                            decoration: BoxDecoration(
                                color: AppColors.accentSoft,
                                borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.history, size: 18, color: AppColors.primary)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_logLabel(log['module']?.toString() ?? '', log['action']?.toString() ?? ''),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(log['description']?.toString() ?? '',
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          Text('${log['created_at']}  •  by ${log['by']}',
                              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                        ])),
                        _moduleBadge(log['module']?.toString() ?? ''),
                      ]));
                })),
      ])),
    ]);
  }

  String _logLabel(String module, String action) => '$action';

  Widget _moduleBadge(String m) {
    final colors = {
      'purchase': [const Color(0xFFE0F2FE), const Color(0xFF0284C7)],
      'expense':  [const Color(0xFFFEF3C7), const Color(0xFFD97706)],
      'supplier': [const Color(0xFFEDE9FE), const Color(0xFF7C3AED)],
    };
    final c = colors[m] ?? [AppColors.accentSoft, AppColors.primary];
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(20)),
        child: Text(m, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: c[1])));
  }
}



// ══════════════════════════════════════════
// SHARED FORM HELPERS
// ══════════════════════════════════════════
Widget _field(TextEditingController c, String label,
    {TextInputType type = TextInputType.text, ValueChanged<String>? onChanged}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      const SizedBox(height: 4),
      TextField(controller: c, keyboardType: type, onChanged: onChanged,
          decoration: const InputDecoration(isDense: true)),
    ]);

Widget _drop<T>(String label, T? val, List<DropdownMenuItem<T>> items,
    ValueChanged<T?> cb, {String hint = 'Select'}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      const SizedBox(height: 4),
      Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border)),
          child: DropdownButtonHideUnderline(child: DropdownButton<T>(
              value: val, isExpanded: true,
              hint: Text(hint, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              items: items, onChanged: cb))),
    ]);

Widget _datePicker(BuildContext context, DateTime date, ValueChanged<DateTime> onChanged) =>
    GestureDetector(
        onTap: () async {
          final p = await showDatePicker(context: context,
              initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2030));
          if (p != null) onChanged(p);
        },
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Date', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border)),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text('${date.day}/${date.month}/${date.year}',
                    style: const TextStyle(fontSize: 13)),
              ])),
        ]));

Widget _saveBtn(String label, VoidCallback? fn) =>
    SizedBox(width: double.infinity, child: ElevatedButton(
        onPressed: fn,
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        child: fn == null
            ? const SizedBox(height: 20, width: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w700))));


// ══════════════════════════════════════════
// PURCHASE FORM
// ══════════════════════════════════════════
class _PurchaseForm extends StatefulWidget {
  final List<Map<String,dynamic>> suppliers, products;
  final Map? initialData;
  final List initialItems;
  final Future<void> Function(Map) onSave;
  const _PurchaseForm({required this.suppliers, required this.products,
    this.initialData, required this.initialItems, required this.onSave});
  @override State<_PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends State<_PurchaseForm> {
  int? _suppId;
  final _billNo = TextEditingController();
  final _note   = TextEditingController();
  final _paid   = TextEditingController(text: '0');
  DateTime _date = DateTime.now();
  List<Map<String,dynamic>> _items = [];
  int? _selProd;
  final _qty  = TextEditingController(text: '1');
  final _rate = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      final d = widget.initialData!;
      _suppId = d['supplier_id'] is int ? d['supplier_id'] : null;
      _billNo.text = d['bill_number'] ?? '';
      _note.text   = d['note'] ?? '';
      _paid.text   = d['paid_amount']?.toString() ?? '0';
      if (d['bill_date'] != null) { try { _date = DateTime.parse(d['bill_date']); } catch (_) {} }
    }
    _items = widget.initialItems.map((i) => Map<String,dynamic>.from(i as Map)).toList();
  }

  double get _total => _items.fold(0, (s, i) {
    final b = (i['rate'] as num) * (i['quantity'] as num);
    return s + b + b * (i['gst_rate'] as num) / 100;
  });

  void _addItem() {
    if (_selProd == null) { _s('Select product'); return; }
    final qty  = int.tryParse(_qty.text) ?? 0;
    final rate = double.tryParse(_rate.text) ?? 0;
    if (qty <= 0 || rate <= 0) { _s('Enter valid qty and rate'); return; }
    final prod = widget.products.firstWhere((p) => p['id'] == _selProd, orElse: () => {});
    if (prod.isEmpty) return;
    setState(() {
      _items.add({'product_id': _selProd, 'product_name': prod['name'],
        'quantity': qty, 'rate': rate, 'gst_rate': prod['gst_rate'] ?? 0});
      _selProd = null; _qty.text = '1'; _rate.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialData != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(isEdit ? 'Edit purchase' : 'Add purchase',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      _drop('Supplier *', _suppId,
          widget.suppliers.map((s) => DropdownMenuItem<int>(
              value: s['id'] as int,
              child: Text(s['name'].toString(), overflow: TextOverflow.ellipsis))).toList(),
              (v) => setState(() => _suppId = v)),
      const SizedBox(height: 12),
      _field(_billNo, 'Bill number'),
      const SizedBox(height: 12),
      StatefulBuilder(builder: (ctx, set) => _datePicker(ctx, _date, (d) {
        setState(() => _date = d);
        set(() {});
      })),
      const SizedBox(height: 16),
      const Text('Add products', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      _drop('Product', _selProd,
          widget.products.map((p) => DropdownMenuItem<int>(
              value: p['id'] as int,
              child: Text(p['name'].toString(), overflow: TextOverflow.ellipsis))).toList(),
              (v) {
            setState(() {
              _selProd = v;
              final prod = widget.products.firstWhere((p) => p['id'] == v, orElse: () => {});
              if (prod.isNotEmpty) _rate.text = prod['base_price']?.toString() ?? '';
            });
          }, hint: 'Select product'),
      const SizedBox(height: 8),
      _field(_qty, 'Quantity', type: TextInputType.number),
      const SizedBox(height: 8),
      _field(_rate, 'Rate ₹', type: TextInputType.number),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity,
          child: OutlinedButton(onPressed: _addItem,
              child: const Text('+ Add to list'))),
      const SizedBox(height: 10),
      ..._items.asMap().entries.map((e) {
        final item  = e.value;
        final base  = (item['rate'] as num) * (item['quantity'] as num);
        final total = base + base * (item['gst_rate'] as num) / 100;
        return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border)),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item['product_name']?.toString() ?? '-',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text('Qty: ${item['quantity']}  •  ₹${item['rate']}  •  GST: ${item['gst_rate']}%',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ])),
              Text('₹${total.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
              const SizedBox(width: 8),
              GestureDetector(onTap: () => setState(() => _items.removeAt(e.key)),
                  child: const Icon(Icons.close, size: 16, color: Color(0xFFC0392B))),
            ]));
      }),
      if (_items.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Grand total', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('₹${_total.toStringAsFixed(2)}', style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 15)),
            ])),
        const SizedBox(height: 12),
        _field(_paid, 'Paid amount ₹', type: TextInputType.number),
        const SizedBox(height: 8),
        _field(_note, 'Note (optional)'),
      ],
      const SizedBox(height: 20),
      _saveBtn(isEdit ? 'Update purchase' : 'Save purchase', _saving ? null : _save),
    ]);
  }

  Future<void> _save() async {
    if (_suppId == null) { _s('Select supplier'); return; }
    if (_items.isEmpty) { _s('Add at least one product'); return; }
    setState(() => _saving = true);
    try {
      final d = _date;
      Navigator.pop(context);
      await widget.onSave({
        if (widget.initialData?['id'] != null) 'purchase_id': widget.initialData!['id'],
        'supplier_id': _suppId,
        'bill_number': _billNo.text.trim(),
        'bill_date': '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}',
        'paid_amount': _paid.text.trim(),
        'note': _note.text.trim(),
        'items': _items,
      });
    } catch (e) { _s(friendlyError(e)); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  void _s(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
}


// ══════════════════════════════════════════
// EXPENSE FORM
// ══════════════════════════════════════════
class _ExpenseForm extends StatefulWidget {
  final List<Map<String,dynamic>> categories, suppliers;
  final Map? initialData;
  final Future<void> Function(Map) onSave;
  const _ExpenseForm({required this.categories, required this.suppliers,
    this.initialData, required this.onSave});
  @override State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  final _title  = TextEditingController();
  final _amt    = TextEditingController();
  final _paid   = TextEditingController(text: '0');
  final _note   = TextEditingController();
  int? _catId, _supId;
  double _gstRate = 0; String _mode = 'cash';
  DateTime _date = DateTime.now();
  bool _saving = false;
  static const _gstRates = [0.0,5.0,12.0,18.0,28.0];
  static const _modes = ['cash','upi','bank','card','cheque'];

  double get _a    => double.tryParse(_amt.text) ?? 0;
  double get _gstA => _a * _gstRate / 100;
  double get _tot  => _a + _gstA;
  double get _p    => double.tryParse(_paid.text) ?? 0;
  double get _pend => (_tot - _p).clamp(0, double.infinity);

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      final d = widget.initialData!;
      _title.text = d['title'] ?? '';
      _amt.text   = d['amount']?.toString() ?? '';
      _paid.text  = d['paid_amount']?.toString() ?? '0';
      _note.text  = d['note'] ?? '';
      _catId = d['category_id'] is int ? d['category_id'] : null;
      _supId = (d['supplier_id'] != null && d['supplier_id'] != '')
          ? (d['supplier_id'] is int ? d['supplier_id'] : null) : null;
      final raw = double.tryParse(d['gst_rate']?.toString() ?? '0') ?? 0;
      const valid = [0.0, 5.0, 12.0, 18.0, 28.0];
      _gstRate = valid.contains(raw) ? raw : 0.0;
      _mode = d['payment_mode'] ?? 'cash';
      if (d['expense_date_raw'] != null) { try { _date = DateTime.parse(d['expense_date_raw']); } catch (_) {} }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialData != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(isEdit ? 'Edit expense' : 'Add expense',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      _field(_title, 'Title *'),
      const SizedBox(height: 12),
      _drop('Category *', _catId,
          widget.categories.map((c) => DropdownMenuItem<int>(
              value: c['id'] as int,
              child: Text(c['name'].toString(), overflow: TextOverflow.ellipsis))).toList(),
              (v) => setState(() => _catId = v)),
      const SizedBox(height: 12),
      _drop('Supplier (optional)', _supId,
          [const DropdownMenuItem<int>(value: null, child: Text('None')),
            ...widget.suppliers.map((s) => DropdownMenuItem<int>(
                value: s['id'] as int,
                child: Text(s['name'].toString(), overflow: TextOverflow.ellipsis)))],
              (v) => setState(() => _supId = v), hint: 'None'),
      const SizedBox(height: 12),
      StatefulBuilder(builder: (ctx, set) => _datePicker(ctx, _date, (d) {
        setState(() => _date = d); set(() {});
      })),
      const SizedBox(height: 12),
      _drop('Payment mode', _modes.indexOf(_mode),
          _modes.asMap().entries.map((e) => DropdownMenuItem<int>(
              value: e.key, child: Text(e.value.toUpperCase()))).toList(),
              (v) => setState(() => _mode = _modes[v ?? 0])),
      const SizedBox(height: 12),
      _field(_amt, 'Amount ₹ *', type: TextInputType.number,
          onChanged: (_) => setState((){})),
      const SizedBox(height: 12),
      _drop('GST %', _gstRate,
          _gstRates.map((r) => DropdownMenuItem<double>(
              value: r, child: Text('$r%'))).toList(),
              (v) => setState(() => _gstRate = v ?? 0)),
      const SizedBox(height: 12),
      _field(_paid, 'Paid amount ₹', type: TextInputType.number,
          onChanged: (_) => setState((){})),
      if (_a > 0) ...[
        const SizedBox(height: 8),
        Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('GST ₹${_gstA.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              Text('Total ₹${_tot.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
              Text('Pending ₹${_pend.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 12,
                      color: _pend > 0 ? const Color(0xFFB91C1C) : AppColors.success)),
            ])),
      ],
      const SizedBox(height: 12),
      _field(_note, 'Note (optional)'),
      const SizedBox(height: 20),
      _saveBtn(isEdit ? 'Update expense' : 'Save expense', _saving ? null : _save),
    ]);
  }

  Future<void> _save() async {
    if (_catId == null) { _s('Select category'); return; }
    if (_title.text.trim().isEmpty) { _s('Enter title'); return; }
    if (_a <= 0) { _s('Enter amount'); return; }
    setState(() => _saving = true);
    try {
      final d = _date;
      Navigator.pop(context);
      await widget.onSave({
        if (widget.initialData?['id'] != null) 'expense_id': widget.initialData!['id'],
        'category_id': _catId,
        if (_supId != null) 'supplier_id': _supId,
        'title': _title.text.trim(),
        'expense_date': '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}',
        'amount': _amt.text.trim(), 'gst_rate': _gstRate,
        'paid_amount': _paid.text.trim(), 'payment_mode': _mode,
        'note': _note.text.trim(),
      });
    } catch (e) { _s(friendlyError(e)); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  void _s(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
}


// ══════════════════════════════════════════
// SUPPLIER FORM
// ══════════════════════════════════════════
class _SupplierForm extends StatefulWidget {
  final Map? initialData;
  final Future<void> Function(Map) onSave;
  const _SupplierForm({this.initialData, required this.onSave});
  @override State<_SupplierForm> createState() => _SupplierFormState();
}

class _SupplierFormState extends State<_SupplierForm> {
  final _name  = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _gstn  = TextEditingController();
  final _state = TextEditingController();
  final _addr  = TextEditingController();
  bool _isGst = false, _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      final d = widget.initialData!;
      _name.text  = d['name'] ?? '';
      _phone.text = d['phone'] ?? '';
      _email.text = d['email'] ?? '';
      _gstn.text  = d['gstnumber'] ?? '';
      _state.text = d['state'] ?? '';
      _addr.text  = d['address'] ?? '';
      _isGst = d['is_gst_registered'] == true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialData != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(isEdit ? 'Edit supplier' : 'Add supplier',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      _field(_name, 'Name *'),
      const SizedBox(height: 12),
      _field(_phone, 'Phone', type: TextInputType.phone),
      const SizedBox(height: 12),
      _field(_email, 'Email', type: TextInputType.emailAddress),
      const SizedBox(height: 12),
      _field(_addr, 'Address'),
      const SizedBox(height: 12),
      GestureDetector(
          onTap: () => setState(() => _isGst = !_isGst),
          child: Row(children: [
            AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44, height: 24,
                decoration: BoxDecoration(
                    color: _isGst ? AppColors.primary : AppColors.border,
                    borderRadius: BorderRadius.circular(12)),
                child: AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    alignment: _isGst ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(width: 20, height: 20, margin: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)))),
            const SizedBox(width: 10),
            const Text('GST Registered', style: TextStyle(fontSize: 13)),
          ])),
      if (_isGst) ...[
        const SizedBox(height: 12),
        _field(_gstn, 'GST Number'),
        const SizedBox(height: 12),
        _field(_state, 'State'),
      ],
      const SizedBox(height: 20),
      _saveBtn(isEdit ? 'Update supplier' : 'Save supplier', _saving ? null : _save),
    ]);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) { _s('Enter name'); return; }
    setState(() => _saving = true);
    try {
      Navigator.pop(context);
      await widget.onSave({
        if (widget.initialData?['id'] != null) 'supplier_id': widget.initialData!['id'],
        'name': _name.text.trim(), 'phone': _phone.text.trim(),
        'email': _email.text.trim(), 'is_gst_registered': _isGst,
        'gstnumber': _gstn.text.trim(), 'state': _state.text.trim(),
        'address': _addr.text.trim(),
      });
    } catch (e) { _s(friendlyError(e)); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  void _s(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
}


// ══════════════════════════════════════════
// PRODUCT FORM
// ══════════════════════════════════════════
class _ProductForm extends StatefulWidget {
  final Map? initialData;
  final Future<void> Function(Map) onSave;
  const _ProductForm({this.initialData, required this.onSave});
  @override State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  final _name  = TextEditingController();
  final _sku   = TextEditingController();
  final _hsn   = TextEditingController();
  final _base  = TextEditingController();
  final _sell  = TextEditingController();
  final _stock = TextEditingController(text: '0');
  final _low   = TextEditingController(text: '5');
  double _gstRate = 0; bool _saving = false;
  static const _gstRates = [0.0,5.0,12.0,18.0,28.0];

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      final d = widget.initialData!;
      _name.text  = d['name'] ?? '';
      _sku.text   = d['sku'] ?? '';
      _hsn.text   = d['hsn_code'] ?? '';
      _base.text  = d['base_price']?.toString() ?? '';
      _sell.text  = d['selling_price']?.toString() ?? '';
      _stock.text = d['stock_quantity']?.toString() ?? '0';
      _low.text   = d['low_stock_alert']?.toString() ?? '5';
      final rawGst = double.tryParse(d['gst_rate']?.toString() ?? '0') ?? 0;
      const validGst = [0.0, 5.0, 12.0, 18.0, 28.0];
      _gstRate = validGst.contains(rawGst) ? rawGst : 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialData != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(isEdit ? 'Edit product' : 'Add product',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      _field(_name, 'Product name *'),
      const SizedBox(height: 12),
      _field(_sku, 'SKU *'),
      const SizedBox(height: 12),
      _field(_hsn, 'HSN code'),
      const SizedBox(height: 12),
      _drop('GST %', _gstRate,
          _gstRates.map((r) => DropdownMenuItem<double>(
              value: r, child: Text('$r%'))).toList(),
              (v) => setState(() => _gstRate = v ?? 0)),
      const SizedBox(height: 12),
      _field(_base, 'Base price ₹', type: TextInputType.number),
      const SizedBox(height: 12),
      _field(_sell, 'Selling price ₹', type: TextInputType.number),
      const SizedBox(height: 12),
      _field(_stock, 'Opening stock', type: TextInputType.number),
      const SizedBox(height: 12),
      _field(_low, 'Low stock alert', type: TextInputType.number),
      const SizedBox(height: 20),
      _saveBtn(isEdit ? 'Update product' : 'Save product', _saving ? null : _save),
    ]);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) { _s('Enter product name'); return; }
    if (_sku.text.trim().isEmpty) { _s('Enter SKU'); return; }
    setState(() => _saving = true);
    try {
      Navigator.pop(context);
      await widget.onSave({
        if (widget.initialData?['id'] != null) 'product_id': widget.initialData!['id'],
        'name': _name.text.trim(), 'sku': _sku.text.trim(),
        'hsn_code': _hsn.text.trim(), 'gst_rate': _gstRate,
        'base_price': _base.text.trim(), 'selling_price': _sell.text.trim(),
        'stock_quantity': _stock.text.trim(), 'low_stock_alert': _low.text.trim(),
      });
    } catch (e) { _s(friendlyError(e)); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  void _s(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
}