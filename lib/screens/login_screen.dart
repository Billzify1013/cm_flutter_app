import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import 'dashboard_screen.dart';
import '../core/notification_service.dart';

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

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
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
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (!isNetworkError(e) && (code == 400 || code == 401)) {
        _showMsg('Incorrect User ID or Password');
      } else {
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
              const SizedBox(height: 34),
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

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(t,
        style:
        const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
  );
}