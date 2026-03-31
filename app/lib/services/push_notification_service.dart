import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/notifications/presentation/notifications_providers.dart';

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref);
});

class PushNotificationService {
  final Ref _ref;
  bool _initialized = false;

  PushNotificationService(this._ref);

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final messaging = FirebaseMessaging.instance;

      // Request permission (required on iOS, no-op on Android 12 and below)
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Push notifications denied by user');
        return;
      }

      // Get and register the FCM token
      final token = await messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }

      // Listen for token refresh (tokens rotate periodically)
      messaging.onTokenRefresh.listen(_registerToken);
    } catch (e) {
      debugPrint('Push notification init failed: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      final repo = _ref.read(notificationsRepositoryProvider);
      await repo.registerPushToken(platform, token);
      debugPrint('FCM token registered ($platform)');
    } catch (e) {
      debugPrint('Failed to register push token: $e');
    }
  }
}
