// Guest ID APIs (Django GuestDocs app) ka client.
//
// Login token wahi hai jo baaki app use karta hai: ApiService (Dio) har request me
// "Authorization: Bearer <token>" khud lagata hai aur 401 pe token refresh karta hai.
//
// Image server se nahi guzarti: upload-url se S3 ki permission milti hai,
// phir photo seedha S3 pe jaati hai, phir confirm.
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/api_service.dart';

class GuestDocsException implements Exception {
  GuestDocsException(this.message, [this.status]);
  final String message;
  final int? status;

  @override
  String toString() => message;
}

class GuestDocsApi {
  GuestDocsApi._();
  static final GuestDocsApi instance = GuestDocsApi._();

  static const _base = '/guestdocs/api/';

  /// S3 ke liye alag Dio: isme login token NAHI jaana chahiye (S3 mana kar deta hai).
  final Dio _s3 = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 30),
    validateStatus: (_) => true,
  ));

  Map<String, dynamic> _json(Response r) {
    final d = r.data;
    final j = d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    if (j['success'] == false) {
      throw GuestDocsException((j['message'] ?? 'Something went wrong').toString(), r.statusCode);
    }
    return j;
  }

  Future<Map<String, dynamic>> _call(Future<Response> Function() send) async {
    try {
      return _json(await send());
    } on DioException catch (e) {
      final d = e.response?.data;
      final msg = d is Map ? (d['message'] ?? d['detail'])?.toString() : null;
      if (e.response == null) {
        throw GuestDocsException('No internet connection. Please try again.');
      }
      throw GuestDocsException(msg ?? 'Error ${e.response?.statusCode}', e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> _get(String path, [Map<String, dynamic>? query]) =>
      _call(() => ApiService.instance.getData('$_base$path', query: query));

  Future<Map<String, dynamic>> _post(String path, [Map<String, dynamic>? body]) =>
      _call(() => ApiService.instance.postData('$_base$path', body ?? <String, dynamic>{}));

  Future<Map<String, dynamic>> status(int bookingId) => _get('status/', {'booking_id': '$bookingId'});

  Future<void> acceptTerms(int bookingId) async {
    await _post('accept-terms/', {'booking_id': bookingId});
  }

  /// {found, has_id, guest:{..., documents:[...]}, message}
  Future<Map<String, dynamic>> lookup(int bookingId, String phone) =>
      _get('lookup/', {'booking_id': '$bookingId', 'phone': phone});

  /// Guest banao/update karo aur booking se jodo. Guest ka json lautata hai.
  Future<Map<String, dynamic>> upsertGuest(int bookingId, Map<String, dynamic> data) async {
    final j = await _post('guests/', {'booking_id': bookingId, ...data});
    return Map<String, dynamic>.from(j['guest'] as Map);
  }

  /// Stay View ke liye: in bookings me se kin ka registration ho chuka (ek hi request, sirf DB).
  /// Server purana ho ya net na ho to khaali set (bas tick nahi dikhega).
  Future<Set<String>> registeredBookings(Iterable<String> bookingIds) async {
    final ids = bookingIds.where((e) => RegExp(r'^\d+$').hasMatch(e)).toSet();
    if (ids.isEmpty) return <String>{};
    try {
      final j = await _get('registered/', {'booking_ids': ids.join(',')});
      return ((j['registered'] as List?) ?? const []).map((e) => '$e').toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// 5 minute chalne wala link (server pe log hota hai)
  Future<String> viewUrl(int documentId) async {
    final j = await _get('view-url/$documentId/');
    return j['url'] as String;
  }

  /// Photo upload: permission -> seedha S3 -> confirm. Document ka json lautata hai.
  Future<Map<String, dynamic>> uploadImage({
    required int bookingId,
    required int guestId,
    required String kind, // id_front / id_back
    required String idType,
    required Uint8List bytes,
    required String contentType, // image/jpeg
    required bool isMasked,
    bool maskOffAck = false,
  }) async {
    final j = await _post('upload-url/', {
      'booking_id': bookingId,
      'guest_id': guestId,
      'kind': kind,
      'id_type': idType,
      'content_type': contentType,
      'size': bytes.lengthInBytes,
      'is_masked': isMasked,
      'mask_off_ack': maskOffAck,
    });
    final up = Map<String, dynamic>.from(j['upload'] as Map);
    final form = FormData();
    (up['fields'] as Map).forEach((k, v) => form.fields.add(MapEntry('$k', '$v')));
    // Dio pehle saare fields bhejta hai, file aakhir me (S3 ko yahi chahiye)
    form.files.add(MapEntry(
      'file',
      MultipartFile.fromBytes(bytes, filename: '$kind${contentType == 'image/webp' ? '.webp' : '.jpg'}'),
    ));
    Response res;
    try {
      res = await _s3.post(up['url'] as String, data: form);
    } on DioException {
      throw GuestDocsException('Upload failed. Please check the internet and try again.');
    }
    final code = res.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw GuestDocsException('Upload failed ($code). Please try again.', code);
    }
    final c = await _post('confirm/', {'document_id': j['document_id']});
    return Map<String, dynamic>.from(c['document'] as Map);
  }
}