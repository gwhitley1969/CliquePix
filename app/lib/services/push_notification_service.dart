import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/routing/app_router.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/notifications/presentation/notifications_providers.dart';
import '../features/photos/presentation/photos_providers.dart';
import '../features/videos/presentation/videos_providers.dart';
import 'telemetry_service.dart';

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

      // Foreground messages
      //  - token_refresh silent pushes: run Layer 2 refresh directly, skip
      //    in-app list refresh (it's not a user-visible notification)
      //  - everything else: invalidate the notifications list so any new
      //    in-app notification row appears immediately
      FirebaseMessaging.onMessage.listen((message) {
        if (message.data['type'] == 'token_refresh') {
          _handleSilentRefresh();
          return;
        }
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

  // Type-aware tap routing for FCM notifications. Mirrors
  // `_handleNotificationTap` in
  // `app/lib/features/notifications/presentation/notifications_screen.dart`
  // (the in-app list). Keep both in sync when adding a new notification type.
  void _navigateFromNotification(Map<String, dynamic> data) {
    try {
      final router = _ref.read(routerProvider);
      final eventId = data['event_id'] as String?;
      final cliqueId = data['clique_id'] as String?;
      final threadId = data['thread_id'] as String?;
      final videoId = data['video_id'] as String?;
      final type = data['type'] as String?;

      // Video ready: open the player directly. The feed caches may have been
      // populated before this video finished transcoding, so invalidate them
      // so the event feed shows the new video when the user navigates back.
      if (type == 'video_ready' && eventId != null && videoId != null) {
        _ref.invalidate(eventVideosProvider(eventId));
        _ref.invalidate(eventPhotosProvider(eventId));
        router.push('/events/$eventId/videos/$videoId');
        return;
      }

      // Video processing failed: open the event so the uploader can see/delete
      if (type == 'video_processing_failed' && eventId != null) {
        router.push('/events/$eventId');
        return;
      }

      // Weekly Friday reminder: drop the user on the Home dashboard so the
      // contextual UI (clique creation prompts vs Create Event CTA) guides
      // them. /events/create is rejected because it requires a clique and
      // would be jarring for users with none.
      if (type == 'friday_reminder') {
        try {
          _ref.read(telemetryServiceProvider).record('friday_reminder_tapped');
        } catch (_) {
          // telemetry is best-effort
        }
        router.go('/events');
        return;
      }

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

  /// Layer 2 foreground path: backend sent a silent token_refresh push while
  /// the app was foregrounded. Trigger MSAL silent refresh immediately.
  Future<void> _handleSilentRefresh() async {
    debugPrint('[AUTH-LAYER-2] foreground silent_push_received');
    final telemetry = _ref.read(telemetryServiceProvider);
    telemetry.record('silent_push_received');
    try {
      final success =
          await _ref.read(authRepositoryProvider).refreshToken();
      telemetry.record(
        success ? 'silent_push_refresh_success' : 'silent_push_refresh_failed',
      );
    } catch (e) {
      telemetry.record('silent_push_refresh_failed', errorCode: e.toString().split('\n').first);
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
