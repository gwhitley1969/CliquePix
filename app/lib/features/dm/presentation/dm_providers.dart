import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/dm_thread_model.dart';
import '../../../models/dm_message_model.dart';
import '../../../services/api_client.dart';
import '../data/dm_api.dart';
import '../domain/dm_repository.dart';
import '../domain/dm_realtime_service.dart';

final dmApiProvider = Provider<DmApi>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return DmApi(apiClient.dio);
});

final dmRepositoryProvider = Provider<DmRepository>((ref) {
  return DmRepository(ref.watch(dmApiProvider));
});

final dmRealtimeServiceProvider = Provider<DmRealtimeService>((ref) {
  final service = DmRealtimeService();
  ref.onDispose(() => service.dispose());
  return service;
});

final dmThreadsProvider = FutureProvider.family<List<DmThreadModel>, String>((ref, eventId) async {
  final repo = ref.watch(dmRepositoryProvider);
  return repo.listThreads(eventId);
});

final dmThreadDetailProvider = FutureProvider.family<DmThreadModel, String>((ref, threadId) async {
  final repo = ref.watch(dmRepositoryProvider);
  return repo.getThread(threadId);
});

final dmMessagesProvider = FutureProvider.family<List<DmMessageModel>, String>((ref, threadId) async {
  final repo = ref.watch(dmRepositoryProvider);
  final result = await repo.listMessages(threadId);
  return result.messages;
});
