import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import 'dashboard_screen.dart';
import '../core/notification_service.dart';

// ═══════════════════════════════════════════════════════════════
//  Saved logins store
//
//  App ke private folder me ek file me rakhta hai. SharedPreferences
//  ya SecureStorage isliye use nahi kiye kyunki app ke doosre parts
//  (logout / token clear / deleteAll) unhe saaf kar dete hain.
//  File ko koi nahi chhoota, isliye ye reliable hai.
//
//  File app-private sandbox me hai (doosri apps padh nahi sakti)
//  aur content obfuscated hai, plain text me nahi.
// ═══════════════════════════════════════════════════════════════
class CredentialStore {
  static const _fileName = '.bz_accounts.dat';
  static const _secret = 'Bz#Krishnam@2026\$SecureSeed';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static String _obfuscate(String plain) {
    final data = utf8.encode(plain);
    final key = utf8.encode(_secret);
    final out =
    List<int>.generate(data.length, (i) => data[i] ^ key[i % key.length]);
    return base64Encode(out);
  }

  static String _deobfuscate(String enc) {
    final data = base64Decode(enc);
    final key = utf8.encode(_secret);
    final out =
    List<int>.generate(data.length, (i) => data[i] ^ key[i % key.length]);
    return utf8.decode(out);
  }

  /// { "last": "userId", "accounts": {...}, "counts": { "userId": 5 } }
  static Future<Map<String, dynamic>> _readRaw() async {
    try {
      final f = await _file();
      if (!await f.exists()) {
        return {'last': null, 'accounts': {}, 'counts': {}};
      }
      final enc = await f.readAsString();
      if (enc.trim().isEmpty) {
        return {'last': null, 'accounts': {}, 'counts': {}};
      }
      final decoded = jsonDecode(_deobfuscate(enc)) as Map<String, dynamic>;
      return {
        'last': decoded['last'],
        'accounts': (decoded['accounts'] as Map?) ?? {},
        'counts': (decoded['counts'] as Map?) ?? {},
      };
    } catch (e) {
      print('CRED READ FAILED -> $e');
      return {'last': null, 'accounts': {}, 'counts': {}};
    }
  }

  static Future<void> _writeRaw(Map<String, dynamic> data) async {
    try {
      final f = await _file();
      await f.writeAsString(_obfuscate(jsonEncode(data)), flush: true);
    } catch (e) {
      print('CRED WRITE FAILED -> $e');
    }
  }

  /// Saare saved accounts: userId -> password
  static Future<Map<String, String>> getAccounts() async {
    final raw = await _readRaw();
    return (raw['accounts'] as Map)
        .map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  /// Kitni baar login hua: userId -> count
  static Future<Map<String, int>> getUsageCounts() async {
    final raw = await _readRaw();
    return (raw['counts'] as Map).map(
            (k, v) => MapEntry(k.toString(), int.tryParse(v.toString()) ?? 0));
  }

  /// Last successfully used user id
  static Future<String?> getLastUser() async {
    final raw = await _readRaw();
    final last = raw['last'];
    return last == null ? null : last.toString();
  }

  /// Successful login ke baad -> save + usage count +1
  static Future<void> save(String userId, String password) async {
    final raw = await _readRaw();
    final accounts = (raw['accounts'] as Map)
        .map((k, v) => MapEntry(k.toString(), v.toString()));
    final counts = (raw['counts'] as Map).map(
            (k, v) => MapEntry(k.toString(), int.tryParse(v.toString()) ?? 0));

    accounts[userId] = password;
    counts[userId] = (counts[userId] ?? 0) + 1;

    await _writeRaw({'last': userId, 'accounts': accounts, 'counts': counts});
    print('CRED SAVED -> $userId | uses: ${counts[userId]} | total: ${accounts.length}');
  }

  /// Galat password par ya user ke hataane par
  static Future<void> remove(String userId) async {
    final raw = await _readRaw();
    final accounts = (raw['accounts'] as Map)
        .map((k, v) => MapEntry(k.toString(), v.toString()));
    final counts = (raw['counts'] as Map).map(
            (k, v) => MapEntry(k.toString(), int.tryParse(v.toString()) ?? 0));

    accounts.remove(userId);
    counts.remove(userId);
    final last = raw['last']?.toString();

    await _writeRaw({
      'last': (last == userId) ? null : last,
      'accounts': accounts,
      'counts': counts,
    });
    print('CRED REMOVED -> $userId | left: ${accounts.length}');
  }

  /// Sab saved logins hatane ke liye (optional)
  static Future<void> clearAll() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
      print('CRED CLEARED ALL');
    } catch (e) {
      print('CRED CLEAR FAILED -> $e');
    }
  }
}

// ═══════════════════════════════════════════════════════════════
//  Login Screen
// ═══════════════════════════════════════════════════════════════
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _hidePass = true;

  /// userId -> password
  Map<String, String> _accounts = {};
  Map<String, int> _counts = {};
  String? _lastUser;

  @override
  void initState() {
    super.initState();
    _loadSavedAccounts();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAccounts() async {
    final accounts = await CredentialStore.getAccounts();
    final counts = await CredentialStore.getUsageCounts();
    final last = await CredentialStore.getLastUser();
    print('CRED LOAD -> ${accounts.keys.toList()} | counts=$counts | last=$last');
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _counts = counts;
      _lastUser = last;
    });
  }

  /// Suggestion chip par tap -> fields bhar ke seedha login
  Future<void> _useAccount(String userId) async {
    final pass = _accounts[userId];
    if (pass == null) return;
    _userCtrl.text = userId;
    _passCtrl.text = pass;
    await _login();
  }

  Future<void> _forgetAccount(String userId) async {
    await CredentialStore.remove(userId);
    await _loadSavedAccounts();
    if (_userCtrl.text.trim() == userId) {
      _userCtrl.clear();
      _passCtrl.clear();
    }
  }

  Future<void> _login() async {
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (user.isEmpty || pass.isEmpty) {
      _showMsg('Please enter both User ID and Password');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final res = await ApiService.instance.login(user, pass);

      // ✅ YEH ADD KAR - DEBUG
      // print('LOGIN RESPONSE: ${res.data}');
      // final hotelName = res.data['hotel_name'] ?? 'Hotel';


      // ✅ Hotel name extract kar
      final hotelName = res.data['hotel_name'] ?? 'Hotel';
      await ApiService.instance.saveHotelName(hotelName);
      print('HOTEL NAME: $hotelName');
      await NotificationService.instance.saveTokenAfterLogin();

      // ✅ Login successful -> credentials save + usage count
      await CredentialStore.save(user, pass);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (!isNetworkError(e) && (code == 400 || code == 401)) {
        // Galat credentials -> saved entry hata do
        await CredentialStore.remove(user);
        await _loadSavedAccounts();
        if (mounted) _passCtrl.clear();
        _showMsg('Incorrect User ID or Password');
      } else {
        // Network issue -> saved data safe rahega
        _showMsg(friendlyError(e));
      }
    } catch (e) {
      _showMsg(friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMsg(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.card,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Image.asset('assets/images/illfy.png', width: 120)),
              const SizedBox(height: 30),
              const Text('Welcome back',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              const Text('Sign in to your hotel',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),

              // ---- Saved accounts: ek row, left-right scrollable ----
              if (_accounts.isNotEmpty) ...[
                const SizedBox(height: 18),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    itemCount: _sortedUserIds().length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => _accountChip(_sortedUserIds()[i]),
                  ),
                ),
              ],

              const SizedBox(height: 30),
              _label('User ID'),
              TextField(
                controller: _userCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'Enter your user ID',
                  prefixIcon:
                  Icon(Icons.person_outline, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 18),
              _label('Password'),
              TextField(
                controller: _passCtrl,
                obscureText: _hidePass,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  hintText: 'Enter your password',
                  prefixIcon: const Icon(Icons.lock_outline,
                      color: AppColors.textSecondary),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _hidePass
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => setState(() => _hidePass = !_hidePass),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _loading ? null : _login,
                child: _loading
                    ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                    : const Text('Log in'),
              ),
              const SizedBox(height: 22),
              const Center(
                child: Text('Billzify · Hotel suite',
                    style:
                    TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sabse zyada use hone wala pehle. Barabar ho to last used pehle.
  List<String> _sortedUserIds() {
    final ids = _accounts.keys.toList();
    ids.sort((a, b) {
      final ca = _counts[a] ?? 0;
      final cb = _counts[b] ?? 0;
      if (cb != ca) return cb.compareTo(ca);
      if (a == _lastUser) return -1;
      if (b == _lastUser) return 1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return ids;
  }

  Widget _accountChip(String id) {
    return InkWell(
      onTap: _loading ? null : () => _useAccount(id),
      onLongPress: _loading ? null : () => _confirmForget(id),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_circle_outlined,
                size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              id,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _loading ? null : () => _confirmForget(id),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 1, vertical: 3),
                child: Icon(Icons.close,
                    size: 13, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmForget(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove saved login?'),
        content: Text('"$id" ka saved password hata diya jayega.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await _forgetAccount(id);
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(t,
        style:
        const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
  );
}