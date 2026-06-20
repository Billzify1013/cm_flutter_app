import 'package:flutter/material.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';

class SubuserScreen extends StatefulWidget {
  const SubuserScreen({super.key});

  @override
  State<SubuserScreen> createState() => _SubuserScreenState();
}

class _SubuserScreenState extends State<SubuserScreen> {
  bool _loading = true;
  String _errorMsg = '';
  List<dynamic> _subusers = [];

  static const Map<String, String> _pageLabels = {
    'mobile_dashboard': 'Dashboard',
    'mobile_inventory': 'Inventory & Rates',
    'mobile_bulk_update': 'Bulk Update',
    'mobile_stay_view': 'Stay View',
    'mobile_purchase_expense': 'Purchase & Expense',
    'mobile_accounts': 'Accounts & GST',
    'mobile_sales_report': 'Sales Report',
    'mobile_ota_commission': 'OTA Commission',
    'mobile_business_report': 'Business Report',
    'mobile_hotel_profile': 'Hotel Profile',
    'mobile_no_show': 'No Show',
  };

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
      final res = await ApiService.instance.getData(AppConfig.subuserList);
      if (!mounted) return;
      setState(() {
        _subusers = (res.data['subusers'] as List?) ?? [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _subusers = [];
        _errorMsg = friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _createSubuser() async {
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final nameCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add staff member'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: usernameCtrl,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result != true) return;

    final username = usernameCtrl.text.trim();
    final password = passwordCtrl.text.trim();
    final fullName = nameCtrl.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _msg('Username and password required');
      return;
    }

    try {
      final res = await ApiService.instance.postData(
        AppConfig.subuserCreate,
        {
          'username': username,
          'password': password,
          'full_name': fullName,
        },
      );
      final success = res.data['success'] == true;
      final message = (res.data['message'] ?? '').toString();
      if (!mounted) return;
      if (success) {
        _msg('Staff member created \u2713');
        _load();
      } else {
        _msg(message.isNotEmpty ? message : 'Failed to create');
      }
    } catch (e) {
      if (!mounted) return;
      _msg(friendlyError(e));
    }
  }

  Future<void> _togglePermission(
      Map<String, dynamic> subuser, String pageKey, bool value) async {
    final id = subuser['id'] as int;
    final perms = Map<String, dynamic>.from(subuser['permissions'] ?? {});
    perms[pageKey] = value;

    setState(() {
      subuser['permissions'] = perms;
    });

    try {
      await ApiService.instance.postData(
        '${AppConfig.subuserPermissions}$id/',
        {'permissions': {pageKey: value}},
      );
    } catch (e) {
      if (!mounted) return;
      _msg(friendlyError(e));
      setState(() {
        perms[pageKey] = !value;
        subuser['permissions'] = perms;
      });
    }
  }

  Future<void> _deleteSubuser(Map<String, dynamic> subuser) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove staff member?'),
        content: Text('Remove ${subuser['full_name'] ?? subuser['username']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final id = subuser['id'] as int;
    try {
      await ApiService.instance.postData('${AppConfig.subuserDelete}$id/', {});
      if (!mounted) return;
      _msg('Removed \u2713');
      _load();
    } catch (e) {
      if (!mounted) return;
      _msg(friendlyError(e));
    }
  }

  void _msg(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Staff',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createSubuser,
          ),
        ],
      ),
      body: _loading
          ? const Center(
          child: CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 2.5))
          : RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: _subusers.isEmpty
            ? ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            Center(
              child: Text(
                _errorMsg.isNotEmpty
                    ? _errorMsg
                    : 'No staff members yet.\nTap + to add one.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        )
            : ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          itemCount: _subusers.length,
          itemBuilder: (ctx, i) => _subuserCard(_subusers[i]),
        ),
      ),
    );
  }

  Widget _subuserCard(Map<String, dynamic> su) {
    final username = (su['username'] ?? '').toString();
    final fullName = (su['full_name'] ?? '').toString();
    final perms = Map<String, dynamic>.from(su['permissions'] ?? {});

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          title: Text(fullName.isNotEmpty ? fullName : username,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text('@$username',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
            onPressed: () => _deleteSubuser(su),
          ),
          children: [
            const Divider(height: 1),
            ..._pageLabels.entries.map((entry) {
              final pageKey = entry.key;
              final label = entry.value;
              final enabled = perms[pageKey] != false;
              return SwitchListTile(
                dense: true,
                title: Text(label, style: const TextStyle(fontSize: 13)),
                value: enabled,
                activeColor: AppColors.primary,
                onChanged: (val) => _togglePermission(su, pageKey, val),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}