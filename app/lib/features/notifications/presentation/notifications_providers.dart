import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/notification_model.dart';
import '../domain/notifications_repository.dart';
import '../data/notifications_api.dart';

final notificationsApiProvider = Provider<NotificationsApi>((ref) {
  throw UnimplementedError('Wire up NotificationsApi with Dio');
});

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  return NotificationsRepository(ref.watch(notificationsApiProvider));
});

final notificationsListProvider = FutureProvider<List<NotificationModel>>((ref) async {
  final repo = ref.watch(notificationsRepositoryProvider);
  final result = await repo.listNotifications();
  return result.notifications;
});
