import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/api_service.dart';
import '../config/app_config.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  debugPrint('BG notification: ${message.notification?.title}');
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _localNotif = FlutterLocalNotificationsPlugin();

  static const _channelId   = 'billzify_notifications';
  static const _channelName = 'Billzify Bookings';
  static const _channelDesc = 'Booking alerts';

  Future<void> init() async {
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    await _requestPermissions();
    await _setupLocalNotifications();
    await _fetchAndSaveToken();
    _messaging.onTokenRefresh.listen(_saveToken);

    // Foreground messages — local notification show karenge
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
  }

  Future<void> _requestPermissions() async {
    await _messaging.requestPermission(
      alert: true, badge: true, sound: true,
    );
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true,
    );
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
      final token = await _messaging.getToken();
      if (token != null) await _saveToken(token);
    } catch (e) {
      debugPrint('FCM token error: $e');
    }
  }

  Future<void> saveTokenAfterLogin() async {
    await _fetchAndSaveToken();
  }

  Future<void> _saveToken(String token) async {
    try {
      final uid = await ApiService.instance.getUserId();
      if (uid == null) return;
      await ApiService.instance.postData(AppConfig.saveFcmToken, {
        'user_id':  uid,
        'token':    token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
      debugPrint('FCM token saved');
    } catch (e) {
      debugPrint('FCM token save error: $e');
    }
  }
}