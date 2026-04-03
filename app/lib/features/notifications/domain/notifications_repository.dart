import '../../../models/notification_model.dart';
import '../data/notifications_api.dart';

class NotificationsRepository {
  final NotificationsApi api;
  NotificationsRepository(this.api);

  Future<({List<NotificationModel> notifications, String? nextCursor})> listNotifications({String? cursor}) async {
    final data = await api.listNotifications(cursor: cursor);
    final notifications = (data['notifications'] as List<dynamic>)
        .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return (
      notifications: notifications,
      nextCursor: data['next_cursor'] as String?,
    );
  }

  Future<void> markRead(String notificationId) async {
    await api.markRead(notificationId);
  }

  Future<void> deleteNotification(String notificationId) async {
    await api.deleteNotification(notificationId);
  }

  Future<void> clearAll() async {
    await api.clearAll();
  }

  Future<void> registerPushToken(String platform, String token) async {
    await api.registerPushToken(platform, token);
  }
}
