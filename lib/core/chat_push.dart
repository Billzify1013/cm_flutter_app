// Opens the right chat when a "chat_message" push is tapped.
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../screens/chat_thread_screen.dart';

class ChatPush {
  /// Same key passed to MaterialApp(navigatorKey: ...) in main.dart.
  static GlobalKey<NavigatorState>? navigatorKey;

  /// Chat to open once the dashboard is ready (app was closed when the push was tapped).
  static int? _pending;

  static bool isChat(Map<String, dynamic> data) => data['type'] == 'chat_message';

  static int? _id(Map<String, dynamic> data) => int.tryParse('${data['conversation_id'] ?? ''}');

  /// True when the user is already looking at this chat (no banner needed).
  static bool isOpenNow(Map<String, dynamic> data) {
    final id = _id(data);
    return id != null && ChatThreadScreen.openConversationId == id;
  }

  /// Payload used for the local notification shown while the app is open.
  static String payloadFor(Map<String, dynamic> data) => 'chat:${data['conversation_id'] ?? ''}';

  /// Handles a tapped local-notification payload. Returns true if it was a chat.
  static bool openPayload(String? payload) {
    if (payload == null || !payload.startsWith('chat:')) return false;
    openId(int.tryParse(payload.substring(5)));
    return true;
  }

  static void openId(int? id) {
    if (id == null) return;
    if (ChatThreadScreen.openConversationId == id) return; // already on screen
    final nav = navigatorKey?.currentState;
    if (nav == null) {
      _pending = id; // app still starting; dashboard will open it
      return;
    }
    nav.push(ChatThreadScreen.route(id));
  }

  /// Call from the dashboard after it is shown (opens a chat tapped while the app was closed).
  static void openPending() {
    final id = _pending;
    _pending = null;
    if (id != null) openId(id);
  }

  /// Call once in main.dart after NotificationService.instance.init().
  static Future<void> init() async {
    // App was closed and opened by tapping the push: open it after login/splash → dashboard
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null && isChat(initial.data)) _pending = _id(initial.data);

    // App was in the background
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      if (isChat(m.data)) openId(_id(m.data));
    });
  }
}