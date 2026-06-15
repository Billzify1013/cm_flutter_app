import 'package:dio/dio.dart';

// ===================================================================
//  Error helper - internet down vs server error ko alag pehchanta hai
// ===================================================================

bool isNetworkError(Object e) {
  if (e is! DioException) return false;
  final t = e.type;
  if (t == DioExceptionType.connectionError ||
      t == DioExceptionType.connectionTimeout ||
      t == DioExceptionType.receiveTimeout ||
      t == DioExceptionType.sendTimeout) {
    return true;
  }
  final s = e.error?.toString() ?? '';
  return s.contains('SocketException') || s.contains('Failed host lookup');
}

String friendlyError(Object e) {
  if (isNetworkError(e)) {
    return 'No internet connection. Please check your network.';
  }
  if (e is DioException && e.type == DioExceptionType.badResponse) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    return 'Server error. Please try again in a moment.';
  }
  return 'Something went wrong. Please try again.';
}