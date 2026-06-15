import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading  = true;
  bool _saving   = false;
  bool _isSubuser = false;
  bool _notifEnabled = true;
  bool _notifLoading = false;
  String? _error;
  String? _imageUrl;
  File? _newImage;

  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _contactCtrl  = TextEditingController();
  final _addressCtrl  = TextEditingController();
  final _zipCtrl      = TextEditingController();
  final _countryCtrl  = TextEditingController();
  final _gstinCtrl    = TextEditingController();
  final _checkInCtrl  = TextEditingController();
  final _checkOutCtrl = TextEditingController();
  final _termsCtrl    = TextEditingController();

  static const _states = [
    'Andhra Pradesh','Arunachal Pradesh','Assam','Bihar','Chhattisgarh',
    'Goa','Gujarat','Haryana','Himachal Pradesh','Jharkhand','Karnataka',
    'Kerala','Madhya Pradesh','Maharashtra','Manipur','Meghalaya','Mizoram',
    'Nagaland','Odisha','Punjab','Rajasthan','Sikkim','Tamil Nadu','Telangana',
    'Tripura','Uttar Pradesh','Uttarakhand','West Bengal',
    'Andaman and Nicobar Islands','Chandigarh',
    'Dadra and Nagar Haveli and Daman and Diu',
    'Lakshadweep','Delhi','Puducherry','Ladakh','Jammu and Kashmir','Foreign',
  ];

  static const _countries = [
    'India','Australia','Bangladesh','Brazil','Canada','China','France',
    'Germany','Indonesia','Israel','Italy','Japan','Korea','Mexico',
    'Philippines','Russia','South Africa','Thailand','Turkey','UAE',
    'United Kingdom','United States',
  ];

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _contactCtrl.dispose();
    _addressCtrl.dispose(); _zipCtrl.dispose(); _countryCtrl.dispose();
    _gstinCtrl.dispose(); _checkInCtrl.dispose(); _checkOutCtrl.dispose();
    _termsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.getData(
        AppConfig.hotelProfile,
        query: {'user_id': uid},
      );
      if (!mounted) return;
      final data = Map<String, dynamic>.from(res.data);
      _isSubuser = data['is_subuser'] == true;

      if (data['exists'] == true) {
        final p = Map<String, dynamic>.from(data['profile']);
        _nameCtrl.text     = p['name']     ?? '';
        _emailCtrl.text    = p['email']    ?? '';
        _contactCtrl.text  = p['contact']  ?? '';
        _addressCtrl.text  = p['address']  ?? '';
        _zipCtrl.text      = p['zipcode']  ?? '';
        _countryCtrl.text  = p['country']  ?? '';
        _gstinCtrl.text    = p['gstin']    ?? '';
        _checkInCtrl.text  = p['checkin_time']  ?? '';
        _checkOutCtrl.text = p['checkout_time'] ?? '';
        _termsCtrl.text    = p['terms']    ?? '';
        _imageUrl = p['image_url'];
        if (_imageUrl != null && _imageUrl!.isNotEmpty &&
            !_imageUrl!.startsWith('http')) {
          _imageUrl = AppConfig.baseUrl + _imageUrl!;
        }
      }
      // Fetch notification status
      try {
        final notifRes = await ApiService.instance.getData(
            AppConfig.notificationSettings);
        _notifEnabled = notifRes.data['enabled'] ?? true;
      } catch (_) {}

      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _toggleNotif(bool value) async {
    setState(() { _notifEnabled = value; _notifLoading = true; });
    try {
      final res = await ApiService.instance.postData(
          AppConfig.notificationSettings, {'enabled': value});
      _snack(res.data['message'] ?? 'Updated');
    } catch (e) {
      setState(() => _notifEnabled = !value);
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _notifLoading = false);
    }
  }

  Future<void> _pickImage() async {
    if (_isSubuser) return;
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024, imageQuality: 85);
      if (file == null) return;
      final imgFile = File(file.path);
      final sizeKb  = imgFile.lengthSync() / 1024;
      if (sizeKb > 700) {
        _snack('Image too large (${sizeKb.toInt()}KB). Max 700KB.');
        return;
      }
      setState(() => _newImage = imgFile);
    } catch (e) {
      _snack('Failed to pick image');
    }
  }

  Future<void> _save() async {
    if (_isSubuser) { _snack('Only main account can edit'); return; }
    if (_nameCtrl.text.trim().isEmpty) {
      _snack('Hotel name required'); return;
    }

    setState(() => _saving = true);
    try {
      final uid = await ApiService.instance.getUserId();
      final form = FormData.fromMap({
        'user_id':       uid,
        'name':          _nameCtrl.text.trim(),
        'email':         _emailCtrl.text.trim(),
        'contact':       _contactCtrl.text.trim(),
        'address':       _addressCtrl.text.trim(),
        'zipcode':       _zipCtrl.text.trim(),
        'country':       _countryCtrl.text.trim(),
        'gstin':         _gstinCtrl.text.trim(),
        'checkin_time':  _checkInCtrl.text.trim(),
        'checkout_time': _checkOutCtrl.text.trim(),
        'terms':         _termsCtrl.text.trim(),
        if (_newImage != null)
          'image': await MultipartFile.fromFile(_newImage!.path,
              filename: _newImage!.path.split('/').last),
      });

      final res = await ApiService.instance.postFormData(
          AppConfig.hotelProfile, form);

      if (!mounted) return;
      _snack(res.data['message'] ?? 'Profile saved');
      setState(() {
        _newImage = null;
        _imageUrl = res.data['profile']?['image_url'];
        if (_imageUrl != null && _imageUrl!.isNotEmpty &&
            !_imageUrl!.startsWith('http')) {
          _imageUrl = AppConfig.baseUrl + _imageUrl!;
        }
      });
    } catch (e) {
      if (!mounted) return;
      if (e is DioException) {
        _snack(e.response?.data?['error']?.toString() ?? friendlyError(e));
      } else {
        _snack(friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(TextEditingController ctrl) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
          child: child!),
    );
    if (picked != null) {
      final h12 = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
      final mm  = picked.minute.toString().padLeft(2, '0');
      final ap  = picked.period == DayPeriod.am ? 'AM' : 'PM';
      ctrl.text = '$h12:$mm $ap';
      setState(() {});
    }
  }

  void _selectState() => _selectFromList(_states, _zipCtrl, 'Select State');
  void _selectCountry() => _selectFromList(_countries, _countryCtrl, 'Select Country');

  void _selectFromList(List<String> items, TextEditingController ctrl, String title) {
    showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.card,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => SafeArea(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(title, style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700))),
              const Divider(height: 1),
              Flexible(child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (ctx, i) => ListTile(
                      dense: true,
                      title: Text(items[i]),
                      selected: ctrl.text == items[i],
                      onTap: () {
                        ctrl.text = items[i];
                        setState(() {});
                        Navigator.pop(context);
                      }))),
            ]))));
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m),
      duration: const Duration(seconds: 2)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        title: const Text('Hotel Profile',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
        actions: [
          if (_loading || _saving)
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary)))
          else if (!_isSubuser)
            TextButton(
                onPressed: _save,
                child: const Text('Save',
                    style: TextStyle(fontWeight: FontWeight.w700,
                        fontSize: 15, color: AppColors.primary))),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(
          color: AppColors.primary, strokeWidth: 2.5))
          : _error != null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, style: const TextStyle(
            color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: _load, child: const Text('Retry')),
      ]))
          : _form(),
    );
  }

  Widget _form() => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Subuser warning
        if (_isSubuser)
          Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD97706))),
              child: const Row(children: [
                Icon(Icons.info_outline,
                    size: 16, color: Color(0xFFD97706)),
                SizedBox(width: 8),
                Expanded(child: Text(
                    'Only the main account can edit hotel profile.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFD97706),
                        fontWeight: FontWeight.w600))),
              ])),

        // Profile image
        Center(child: GestureDetector(
            onTap: _pickImage,
            child: Stack(children: [
              Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border, width: 2),
                      image: _newImage != null
                          ? DecorationImage(image: FileImage(_newImage!), fit: BoxFit.cover)
                          : (_imageUrl != null && _imageUrl!.isNotEmpty)
                          ? DecorationImage(
                          image: NetworkImage(_imageUrl!), fit: BoxFit.cover)
                          : null),
                  child: (_newImage == null && (_imageUrl == null || _imageUrl!.isEmpty))
                      ? const Icon(Icons.business,
                      size: 50, color: AppColors.primary)
                      : null),
              if (!_isSubuser)
                Positioned(
                    right: 0, bottom: 0,
                    child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                            color: AppColors.primary, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 16))),
            ]))),
        const SizedBox(height: 8),
        Center(child: Text('Tap to upload logo (max 700KB)',
            style: const TextStyle(fontSize: 11,
                color: AppColors.textSecondary))),
        const SizedBox(height: 24),

        // Hotel Info
        _sec('Hotel Information'),
        _field('Hotel Name', _nameCtrl, required: true),
        _field('Email', _emailCtrl, type: TextInputType.emailAddress),
        _field('Phone Number', _contactCtrl,
            type: TextInputType.phone, prefix: '+91 '),
        _field('Address', _addressCtrl, maxLines: 2),

        // Pickers
        Row(children: [
          Expanded(child: _pickerField('State', _zipCtrl, _selectState)),
          const SizedBox(width: 10),
          Expanded(child: _pickerField('Country', _countryCtrl, _selectCountry)),
        ]),

        _field('GSTIN Number', _gstinCtrl,
            formatter: (v) => v.toUpperCase()),

        // Times
        Row(children: [
          Expanded(child: _pickerField(
              'Check-in Time', _checkInCtrl, () => _pickTime(_checkInCtrl),
              icon: Icons.access_time)),
          const SizedBox(width: 10),
          Expanded(child: _pickerField(
              'Check-out Time', _checkOutCtrl, () => _pickTime(_checkOutCtrl),
              icon: Icons.access_time)),
        ]),

        _field('Terms & Conditions', _termsCtrl, maxLines: 4,
            hint: 'Enter hotel terms and conditions...'),

        const SizedBox(height: 16),

        // Notification Settings
        _sec('Notification Settings'),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border)),
            child: Column(children: [
              // Push notifications toggle
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: _notifEnabled
                              ? AppColors.accentSoft
                              : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(
                          _notifEnabled
                              ? Icons.notifications_active
                              : Icons.notifications_off,
                          color: _notifEnabled
                              ? AppColors.primary
                              : const Color(0xFFDC2626),
                          size: 20)),
                  title: const Text('Push Notifications',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      _notifEnabled
                          ? 'You will receive booking alerts'
                          : 'Notifications are turned off',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                  trailing: _notifLoading
                      ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary))
                      : Switch(
                      value: _notifEnabled,
                      activeColor: AppColors.primary,
                      onChanged: _toggleNotif)),
            ])),

        const SizedBox(height: 16),

        if (!_isSubuser)
          SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  child: _saving
                      ? const SizedBox(height: 18, width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                      : const Text('Save Changes',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)))),

        const SizedBox(height: 40),
      ]);

  Widget _sec(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 8),
      child: Text(t, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary)));

  Widget _field(String label, TextEditingController ctrl,
      {TextInputType type = TextInputType.text,
        int maxLines = 1, bool required = false, String? hint,
        String? prefix, String Function(String)? formatter}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label, style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
              if (required) const Text(' *',
                  style: TextStyle(color: Color(0xFFDC2626), fontSize: 11)),
            ]),
            const SizedBox(height: 4),
            TextField(
                controller: ctrl,
                enabled: !_isSubuser,
                keyboardType: type,
                maxLines: maxLines,
                onChanged: formatter == null ? null : (v) {
                  final f = formatter(v);
                  if (f != v) {
                    ctrl.value = TextEditingValue(
                        text: f, selection: TextSelection.collapsed(offset: f.length));
                  }
                },
                decoration: InputDecoration(
                    isDense: true,
                    hintText: hint,
                    prefixText: prefix,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    filled: true,
                    fillColor: _isSubuser ? AppColors.accentSoft : AppColors.card,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 1.5))),
                style: const TextStyle(fontSize: 13))]));

  Widget _pickerField(String label, TextEditingController ctrl,
      VoidCallback onTap, {IconData? icon}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            GestureDetector(
                onTap: _isSubuser ? null : onTap,
                child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                        color: _isSubuser ? AppColors.accentSoft : AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border)),
                    child: Row(children: [
                      Expanded(child: Text(
                          ctrl.text.isEmpty ? 'Select...' : ctrl.text,
                          style: TextStyle(fontSize: 13,
                              color: ctrl.text.isEmpty
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary))),
                      Icon(icon ?? Icons.arrow_drop_down,
                          size: 18, color: AppColors.textSecondary),
                    ])))]));
}