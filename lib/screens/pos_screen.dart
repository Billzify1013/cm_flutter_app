import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:dio/dio.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';

class _Item {
  final int id;
  final String name;
  double rate;
  double gstRate;
  String gstMode;
  String note;
  int qty;
  _Item({required this.id, required this.name, required this.rate,
    required this.gstRate, this.gstMode = 'inclusive', this.note = '', this.qty = 1});
  double get total => gstMode == 'inclusive' ? rate * qty : rate * qty * (1 + gstRate / 100);
  double get base  => gstMode == 'inclusive' ? (rate * qty) / (1 + gstRate / 100) : rate * qty;
  double get gst   => total - base;
}

class PosScreen extends StatefulWidget {
  final String bookingId, guestName;
  const PosScreen({super.key, required this.bookingId, required this.guestName});
  @override State<PosScreen> createState() => _PosState();
}

class _PosState extends State<PosScreen> {
  bool _loading = true, _saving = false;
  List<Map<String, dynamic>> _products = [], _filtered = [];
  final Map<int, _Item> _cart = {};
  final _searchCtrl = TextEditingController();
  final _payCtrl = TextEditingController(text: '0');
  String _payMode = 'Cash';
  static const _modes = ['Cash', 'UPI', 'Card', 'Room Post'];

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _searchCtrl.dispose(); _payCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(AppConfig.posProducts, {'user_id': uid});
      if (!mounted) return;
      setState(() {
        _products = List<Map<String, dynamic>>.from(res.data['products']);
        _filtered = _products;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(friendlyError(e));
    }
  }

  void _search(String q) => setState(() =>
  _filtered = q.isEmpty ? _products
      : _products.where((p) => p['name'].toString().toLowerCase()
      .contains(q.toLowerCase())).toList());

  void _add(Map p) {
    final id = p['id'] as int;
    setState(() => _cart.containsKey(id) ? _cart[id]!.qty++ : _cart[id] = _Item(
      id: id, name: p['name'].toString(),
      rate: double.parse(p['selling_price'].toString()),
      gstRate: double.parse(p['gst_rate'].toString()),
    ));
  }

  int get _cartCount => _cart.values.fold(0, (s, i) => s + i.qty);
  double get _total => _cart.values.fold(0, (s, i) => s + i.total);
  double get _base  => _cart.values.fold(0, (s, i) => s + i.base);
  double get _gst   => _cart.values.fold(0, (s, i) => s + i.gst);
  double get _paid  => double.tryParse(_payCtrl.text) ?? 0;
  double get _rem   => _total - _paid;

  void _openCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, set) =>
          DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (_, ctrl) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(children: [
                Container(margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: AppColors.border,
                        borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(children: [
                    const Text('Cart', style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (_cart.isNotEmpty)
                      TextButton(
                          onPressed: () { setState(() => _cart.clear()); set(() {}); },
                          child: const Text('Clear all',
                              style: TextStyle(color: Color(0xFFC0392B)))),
                  ]),
                ),
                const Divider(height: 1),
                Expanded(child: _cart.isEmpty
                    ? const Center(child: Text('Cart is empty',
                    style: TextStyle(color: AppColors.textSecondary)))
                    : ListView(
                  controller: ctrl,
                  padding: const EdgeInsets.all(16),
                  children: _cart.values.map((c) =>
                      _cartTile(c, () => set(() => setState(() {})))).toList(),
                )),
                if (_cart.isNotEmpty) _checkoutPanel(set),
              ]),
            ),
          )),
    );
  }

  Widget _cartTile(_Item c, VoidCallback refresh) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header: name + qty controls + price ──
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            // Qty controls
            Container(
              decoration: BoxDecoration(color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _qBtn('−', () {
                  setState(() { if (c.qty > 1) c.qty--; else _cart.remove(c.id); });
                  refresh();
                }),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('${c.qty}', style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700))),
                _qBtn('+', () { setState(() => c.qty++); refresh(); }),
              ]),
            ),
            const SizedBox(width: 10),
            // Name
            Expanded(child: Text(c.name, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            const SizedBox(width: 8),
            // Price
            Text('₹${c.total.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
          ]),
        ),

        // ── Expandable details ──
        _CartItemDetails(item: c, onChanged: refresh, onDelete: () {
          setState(() => _cart.remove(c.id));
          refresh();
        }),
      ]),
    );
  }

  Widget _checkoutPanel(StateSetter set) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000),
            blurRadius: 10, offset: Offset(0, -4))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: _totBox('Base', '₹${_base.toStringAsFixed(2)}')),
          const SizedBox(width: 8),
          Expanded(child: _totBox('GST', '₹${_gst.toStringAsFixed(2)}')),
          const SizedBox(width: 8),
          Expanded(child: _totBox('Total', '₹${_total.toStringAsFixed(2)}', bold: true)),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border)),
          child: DropdownButtonHideUnderline(child: DropdownButton<String>(
            value: _payMode, isExpanded: true,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
            items: _modes.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
            onChanged: (v) { setState(() => _payMode = v ?? 'Cash'); set(() {}); },
          )),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(
            controller: _payCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) { setState(() {}); set(() {}); },
            decoration: const InputDecoration(
                labelText: 'Paid amount ₹', isDense: true,
                prefixIcon: Icon(Icons.currency_rupee, size: 16,
                    color: AppColors.textSecondary)),
          )),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
                color: _rem > 0 ? const Color(0xFFFEE2E2)
                    : _rem < 0 ? AppColors.accentSoft : AppColors.successSoft,
                borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text(_rem > 0 ? 'Remaining' : _rem < 0 ? 'Advance' : 'Fully paid',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                      color: _rem > 0 ? const Color(0xFFB91C1C)
                          : _rem < 0 ? AppColors.primary : AppColors.success)),
              Text('₹${_rem.abs().toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                      color: _rem > 0 ? const Color(0xFFB91C1C)
                          : _rem < 0 ? AppColors.primary : AppColors.success)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _saving ? null : () async {
            Navigator.pop(context);
            await _save();
          },
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14)),
          child: _saving
              ? const SizedBox(height: 20, width: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text('Confirm & save  •  ₹${_total.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        )),
      ]),
    );
  }

  Future<void> _save() async {
    if (_cart.isEmpty) { _snack('Cart is empty'); return; }
    setState(() => _saving = true);
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(AppConfig.posSave, {
        'user_id': uid, 'booking_id': widget.bookingId,
        'payment_mode': _payMode.toLowerCase(),
        'paid_amount': _payCtrl.text.trim(),
        'items': _cart.values.map((c) => {
          'product_id': c.id, 'qty': c.qty, 'rate': c.rate,
          'gst_rate': c.gstRate, 'gst_mode': c.gstMode, 'note': c.note,
        }).toList(),
      });
      if (!mounted) return;
      _snack(res.data['message'] ?? 'Bill saved!');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      if (e is DioException) {
        _snack(e.response?.data?['error']?.toString() ?? friendlyError(e));
      } else { _snack(friendlyError(e)); }
    } finally { if (mounted) setState(() => _saving = false); }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Add product bill',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          Text(widget.guestName,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ]),
        leading: IconButton(icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
        actions: [
          if (_cartCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _openCart,
                icon: const Icon(Icons.shopping_cart_outlined, size: 20),
                label: Text('$_cartCount item${_cartCount > 1 ? 's' : ''}'),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
            ),
        ],
      ),
      body: _loading ? _skeleton() : Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchCtrl, onChanged: _search,
            decoration: const InputDecoration(
              hintText: 'Search products...',
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textSecondary),
            ),
          ),
        ),
        Expanded(child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.2,
          ),
          itemCount: _filtered.length,
          itemBuilder: (_, i) => _productCard(_filtered[i]),
        )),
      ]),
      floatingActionButton: _cartCount > 0
          ? FloatingActionButton.extended(
        onPressed: _openCart,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.shopping_cart, color: Colors.white),
        label: Text('$_cartCount  •  ₹${_total.toStringAsFixed(0)}',
            style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700)),
      )
          : null,
    );
  }

  Widget _productCard(Map p) {
    final id = p['id'] as int;
    final inCart = _cart.containsKey(id);
    final qty = inCart ? _cart[id]!.qty : 0;
    return GestureDetector(
      onTap: () => _add(p),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: inCart ? AppColors.accentSoft : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: inCart ? AppColors.primary : AppColors.border,
              width: inCart ? 1.5 : 1),
          boxShadow: const [BoxShadow(color: Color(0x06000000),
              blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Row(children: [
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(p['name'].toString(), maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: inCart ? AppColors.primary : AppColors.textPrimary)),
            const SizedBox(height: 3),
            Text('₹${p['selling_price']}  •  ${p['gst_rate']}% GST',
                style: TextStyle(fontSize: 11,
                    color: inCart ? AppColors.primary : AppColors.textSecondary)),
          ])),
          if (inCart)
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('$qty', style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
        ]),
      ),
    );
  }

  Widget _totBox(String l, String v, {bool bold = false}) => Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
          color: bold ? AppColors.accentSoft : AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: bold ? AppColors.primary : AppColors.border,
              width: bold ? 1.5 : 1)),
      child: Column(children: [
        Text(l, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        Text(v, style: TextStyle(fontSize: bold ? 14 : 12,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: bold ? AppColors.primary : AppColors.textPrimary)),
      ]));

  Widget _qBtn(String l, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: SizedBox(width: 36, height: 36,
          child: Center(child: Text(l, style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w600,
              color: AppColors.textPrimary)))));

  Widget _skeleton() => Shimmer.fromColors(
      baseColor: const Color(0xFFE8E8E8),
      highlightColor: const Color(0xFFF5F5F5),
      child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 10,
              mainAxisSpacing: 10, childAspectRatio: 2.2),
          itemCount: 8,
          itemBuilder: (_, __) => Container(
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(14)))));
}

// ── Cart item expandable details ──
class _CartItemDetails extends StatefulWidget {
  final _Item item;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  const _CartItemDetails({required this.item, required this.onChanged, required this.onDelete});
  @override State<_CartItemDetails> createState() => _CartItemDetailsState();
}

class _CartItemDetailsState extends State<_CartItemDetails> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.item;
    return Column(children: [
      // Toggle row
      GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _expanded ? AppColors.accentSoft : AppColors.background,
            borderRadius: _expanded
                ? BorderRadius.zero
                : const BorderRadius.vertical(bottom: Radius.circular(14)),
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(children: [
            Text('Base ₹${c.base.toStringAsFixed(0)}  •  GST ₹${c.gst.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const Spacer(),
            Text(_expanded ? 'Less' : 'Details',
                style: const TextStyle(fontSize: 11, color: AppColors.primary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.keyboard_arrow_down, size: 16,
                    color: AppColors.primary)),
          ]),
        ),
      ),

      // Expanded content
      if (_expanded)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // GST mode
            Row(children: [
              const Text('GST mode:', style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  setState(() => c.gstMode =
                  c.gstMode == 'inclusive' ? 'exclusive' : 'inclusive');
                  widget.onChanged();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: c.gstMode == 'inclusive'
                          ? AppColors.successSoft : AppColors.warningSoft,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(c.gstMode == 'inclusive' ? 'INCL' : 'EXCL',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: c.gstMode == 'inclusive'
                              ? AppColors.success : AppColors.warning)),
                ),
              ),
              const Spacer(),
              Text('${c.gstRate.toStringAsFixed(0)}% GST',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ]),
            const SizedBox(height: 10),

            // Note
            _NoteField(
              key: ValueKey('note_${c.id}'),
              initialNote: c.note,
              onChanged: (v) => c.note = v,
            ),
            const SizedBox(height: 10),

            // Delete
            GestureDetector(
              onTap: widget.onDelete,
              child: Row(children: const [
                Icon(Icons.delete_outline, size: 15, color: Color(0xFFC0392B)),
                SizedBox(width: 6),
                Text('Remove from cart', style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: Color(0xFFC0392B))),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

// ── Note field ──
class _NoteField extends StatefulWidget {
  final String initialNote;
  final ValueChanged<String> onChanged;
  const _NoteField({super.key, required this.initialNote, required this.onChanged});
  @override State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  bool _expanded = false;
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialNote);
    _expanded = widget.initialNote.isNotEmpty;
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return GestureDetector(
        onTap: () => setState(() => _expanded = true),
        child: Row(children: const [
          Icon(Icons.add, size: 13, color: AppColors.textSecondary),
          SizedBox(width: 4),
          Text('Add note', style: TextStyle(
              fontSize: 12, color: AppColors.textSecondary)),
        ]),
      );
    }
    return TextField(
      controller: _ctrl,
      autofocus: true,
      onChanged: widget.onChanged,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        hintText: 'Note (e.g. Room 101)',
        isDense: true,
        border: InputBorder.none,
        hintStyle: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        contentPadding: EdgeInsets.zero,
        suffixIcon: GestureDetector(
            onTap: () {
              _ctrl.clear();
              widget.onChanged('');
              setState(() => _expanded = false);
            },
            child: const Icon(Icons.close, size: 14, color: AppColors.textSecondary)),
      ),
    );
  }
}