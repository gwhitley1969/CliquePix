import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/routing/app_router.dart';
import '../features/notifications/presentation/notifications_providers.dart';

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref);
});

class PushNotificationService {
  final Ref _ref;
  bool _initialized = false;

  /// Static callback for local notification taps (set during initialize,
  /// called from main.dart's onDidReceiveNotificationResponse).
  static void Function(String payload)? onNotificationTap;

  PushNotificationService(this._ref);

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final messaging = FirebaseMessaging.instance;

      // iOS permission request (Android handled in main.dart via requestNotificationsPermission)
      if (Platform.isIOS) {
        final settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        if (settings.authorizationStatus == AuthorizationStatus.denied) {
          debugPrint('[CliquePix] Push notifications denied by user');
          return;
        }
      }

      // Get and register the FCM token
      final token = await messaging.getToken();
      debugPrint('[CliquePix] FCM token: ${token?.substring(0, 20)}...');
      if (token != null) {
        await _registerToken(token);
      }

      // Listen for token refresh
      messaging.onTokenRefresh.listen(_registerToken);

      // Foreground messages: refresh in-app notification list
      // (display is handled by main.dart's onMessage listener)
      FirebaseMessaging.onMessage.listen((_) {
        _ref.invalidate(notificationsListProvider);
      });

      // Background tap: user taps notification while app is backgrounded
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        debugPrint('[CliquePix] Notification tapped (background): ${message.data}');
        _navigateFromNotification(message.data);
      });

      // Terminated tap: app launched from killed state via notification
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('[CliquePix] Notification opened app (terminated): ${initialMessage.data}');
        Future.delayed(const Duration(milliseconds: 500), () {
          _navigateFromNotification(initialMessage.data);
        });
      }

      // Wire up local notification tap callback (foreground-shown notifications)
      onNotificationTap = (payload) {
        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          debugPrint('[CliquePix] Local notification tapped: $data');
          _navigateFromNotification(data);
        } catch (e) {
          debugPrint('[CliquePix] Failed to parse notification payload: $e');
        }
      };

      debugPrint('[CliquePix] PushNotificationService initialized');
    } catch (e) {
      debugPrint('[CliquePix] Push notification init failed: $e');
    }
  }

  void _navigateFromNotification(Map<String, dynamic> data) {
    try {
      final router = _ref.read(routerProvider);
      final eventId = data['event_id'] as String?;
      final cliqueId = data['clique_id'] as String?;
      final threadId = data['thread_id'] as String?;
      final type = data['type'] as String?;
      if (type == 'dm_message' && threadId != null && eventId != null) {
        router.push('/events/$eventId/dm/$threadId');
      } else if (eventId != null) {
        router.push('/events/$eventId');
      } else if (cliqueId != null) {
        router.push('/cliques/$cliqueId');
      }
    } catch (e) {
      debugPrint('[CliquePix] Notification navigation failed: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      final repo = _ref.read(notificationsRepositoryProvider);
      await repo.registerPushToken(platform, token);
      debugPrint('[CliquePix] FCM token registered ($platform)');
    } catch (e) {
      debugPrint('[CliquePix] Failed to register push token: $e');
    }
  }
}
