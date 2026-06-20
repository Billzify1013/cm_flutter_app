import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';


// ===================================================================
//  Billzify API service
//  - Django se baat (dio)
//  - Login token reliable storage me (encryptedSharedPreferences)
//  - Har authed request me token automatic + 401 pe auto-refresh
//  - DAILY SESSION: roz raat 12 baje (midnight) auto-logout
// ===================================================================

class ApiService {
  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    _rawDio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await getAccessToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        if (e.response?.statusCode == 401) {
          final newAccess = await _tryRefresh();
          if (newAccess != null) {
            final req = e.requestOptions;
            req.headers['Authorization'] = 'Bearer $newAccess';
            try {
              final clone = await _dio.fetch(req);
              return handler.resolve(clone);
            } catch (_) {
              return handler.next(e);
            }
          }
        }
        handler.next(e);
      },
    ));
  }

  static final ApiService instance = ApiService._internal();
  late final Dio _dio;
  late final Dio _rawDio;

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ---------------- Token storage ----------------
  Future<void> saveTokens({
    required String access,
    required String refresh,
    required int userId,
    bool isSubuser = false,
  }) async {
    await _storage.write(key: 'access', value: access);
    await _storage.write(key: 'refresh', value: refresh);
    await _storage.write(key: 'user_id', value: userId.toString());
    await _storage.write(key: 'is_subuser', value: isSubuser.toString());
    // Aaj raat 12 baje (next midnight) ki expiry save karo
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    await _storage.write(
        key: 'session_expiry', value: nextMidnight.toIso8601String());
  }

  Future<bool> isSubuser() async {
    final val = await _storage.read(key: 'is_subuser');
    return val == 'true';
  }

  Future<String?> getAccessToken() => _storage.read(key: 'access');
  Future<String?> getUserId() => _storage.read(key: 'user_id');
  Future<void> clearTokens() => _storage.deleteAll();

  // Session khatam? (roz raat 12 baje ke baad)
  Future<bool> isSessionExpired() async {
    final exp = await _storage.read(key: 'session_expiry');
    if (exp == null) return true;
    final expiry = DateTime.tryParse(exp);
    if (expiry == null) return true;
    return DateTime.now().isAfter(expiry);
  }

  Future<bool> isLoggedIn() async {
    final t = await getAccessToken();
    if (t == null || t.isEmpty) return false;
    // Raat 12 baje ke baad -> session khatam, logout
    if (await isSessionExpired()) {
      await clearTokens();
      return false;
    }
    return true;
  }

  Future<String?> _tryRefresh() async {
    try {
      final refresh = await _storage.read(key: 'refresh');
      if (refresh == null || refresh.isEmpty) return null;
      final res = await _rawDio
          .post(AppConfig.tokenRefresh, data: {'refresh': refresh});
      final newAccess = res.data['access'] as String?;
      if (newAccess != null) {
        await _storage.write(key: 'access', value: newAccess);
        return newAccess;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------------- Auth ----------------
  Future<Response> login(String username, String password) async {
    final res = await _dio.post(AppConfig.login, data: {
      'username': username,
      'password': password,
    });
    final data = res.data as Map<String, dynamic>;
    await saveTokens(
      access: data['access'] as String,
      refresh: data['refresh'] as String,
      userId: data['user_id'] as int,
      isSubuser: data['is_subuser'] == true,
    );
    return res;
  }

  Future<void> saveHotelName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hotel_name', name);
    print('SAVED HOTEL NAME: $name');  // ✅ DEBUG
  }

  Future<String?> getHotelName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('hotel_name');
    print('RETRIEVED HOTEL NAME: $name');  // ✅ DEBUG
    return name;
  }

  // ---------------- Generic helpers ----------------
  Future<Response> postData(String path, Map<String, dynamic> body) {
    return _dio.post(path, data: body);
  }

  Future<Response> getData(String path, {Map<String, dynamic>? query}) {
    return _dio.get(path, queryParameters: query);
  }

  Future<Response> postFormData(String path, FormData formData) {
    return _dio.post(path, data: formData);
  }

  Future<void> downloadFile(String path, String savePath,
      {Map<String, dynamic>? data}) async {
    await _dio.download(
      path, savePath,
      data: data,
      options: Options(method: 'POST', responseType: ResponseType.bytes),
    );
  }
}


