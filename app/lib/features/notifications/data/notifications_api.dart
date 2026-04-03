import 'package:dio/dio.dart';
import '../../../core/constants/api_endpoints.dart';

class NotificationsApi {
  final Dio dio;
  NotificationsApi(this.dio);

  Future<Map<String, dynamic>> listNotifications({String? cursor, int limit = 50}) async {
    final params = <String, dynamic>{'limit': limit};
    if (cursor != null) params['cursor'] = cursor;
    final response = await dio.get(ApiEndpoints.notifications, queryParameters: params);
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<void> markRead(String notificationId) async {
    await dio.patch(ApiEndpoints.notificationRead(notificationId));
  }

  Future<void> deleteNotification(String notificationId) async {
    await dio.delete('${ApiEndpoints.notifications}/$notificationId');
  }

  Future<void> clearAll() async {
    await dio.delete(ApiEndpoints.notifications);
  }

  Future<void> registerPushToken(String platform, String token) async {
    await dio.post(ApiEndpoints.pushTokens, data: {'platform': platform, 'token': token});
  }
}
