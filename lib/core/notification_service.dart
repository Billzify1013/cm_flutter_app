import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_service.dart';
import '../config/app_config.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  debugPrint('BG notification: ${message.notification?.title}');
  final prefs = await SharedPreferences.getInstance();
  final current = prefs.getInt('unread_booking_count') ?? 0;
  await prefs.setInt('unread_booking_count', current + 1);
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _localNotif = FlutterLocalNotificationsPlugin();

  static const _channelId   = 'billzify_notifications';
  static const _channelName = 'Billzify Bookings';
  static const _channelDesc = 'Booking alerts';

  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);
  final ValueNotifier<int> newBookingTrigger = ValueNotifier<int>(0);

  // DEBUG: last status/error yahan store hoga, dashboard pe dikhane ke liye
  final ValueNotifier<String> debugStatus = ValueNotifier<String>('Not started');

  Future<void> init() async {
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    await _requestPermissions();
    await _setupLocalNotifications();
    await _fetchAndSaveToken();
    await refreshUnreadCount();
    _messaging.onTokenRefresh.listen(_saveToken);
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
  }

  Future<void> refreshUnreadCount() async {
    final prefs = await SharedPreferences.getInstance();
    unreadCount.value = prefs.getInt('unread_booking_count') ?? 0;
  }

  Future<void> _incrementUnread() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt('unread_booking_count') ?? 0;
    final updated = current + 1;
    await prefs.setInt('unread_booking_count', updated);
    unreadCount.value = updated;
    newBookingTrigger.value = newBookingTrigger.value + 1;
  }

  Future<void> clearUnread() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('unread_booking_count', 0);
    unreadCount.value = 0;
  }

  Future<void> _requestPermissions() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true, badge: true, sound: true,
      );
      debugStatus.value = 'Permission: ${settings.authorizationStatus}';
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true,
      );
    } catch (e) {
      debugStatus.value = 'Permission error: $e';
    }
  }

  Future<void> _setupLocalNotifications() async {
    const androidChannel = AndroidNotificationChannel(
      _channelId, _channelName,
      description: _channelDesc,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _localNotif
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _localNotif.initialize(initSettings);
  }

  void _onForegroundMessage(RemoteMessage message) {
    final notif = message.notification;
    _incrementUnread();
    if (notif == null) return;
    _localNotif.show(
      notif.hashCode,
      notif.title,
      notif.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          largeIcon: const DrawableResourceAndroidBitmap('blogo'),
          color: const Color(0xFF18181B),
          playSound: true,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data['booking_id'],
    );
  }

  Future<void> _fetchAndSaveToken() async {
    try {
      if (Platform.isIOS) {
        debugStatus.value = 'iOS: waiting for APNs token...';
        String? apnsToken = await _messaging.getAPNSToken();
        int attempts = 0;
        while (apnsToken == null && attempts < 15) {
          await Future.delayed(const Duration(seconds: 1));
          apnsToken = await _messaging.getAPNSToken();
          attempts++;
        }
        if (apnsToken == null) {
          debugStatus.value = 'APNs token NULL after $attempts attempts';
          return;
        }
        debugStatus.value = 'APNs token OK: ${apnsToken.substring(0, 10)}...';
      }

      final token = await _messaging.getToken();
      if (token == null) {
        debugStatus.value = 'FCM getToken() returned NULL';
        return;
      }
      debugStatus.value = 'FCM token OK: ${token.substring(0, 15)}...';
      await _saveToken(token);
    } catch (e, st) {
      debugStatus.value = 'EXCEPTION: $e';
      debugPrint('FCM token error: $e\n$st');
    }
  }

  Future<void> saveTokenAfterLogin() async {
    await _fetchAndSaveToken();
  }

  Future<void> _saveToken(String token) async {
    try {
      final uid = await ApiService.instance.getUserId();
      if (uid == null) {
        debugStatus.value = 'No user_id found, skipping save';
        return;
      }
      await ApiService.instance.postData(AppConfig.saveFcmToken, {
        'user_id':  uid,
        'token':    token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
      debugStatus.value = 'Token saved to backend successfully';
    } catch (e) {
      debugStatus.value = 'Save to backend FAILED: $e';
      debugPrint('FCM token save error: $e');
    }
  }
}