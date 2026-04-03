import '../../../models/dm_thread_model.dart';
import '../../../models/dm_message_model.dart';
import '../data/dm_api.dart';

class DmRepository {
  final DmApi api;
  DmRepository(this.api);

  Future<DmThreadModel> createOrGetThread(String eventId, String targetUserId) async {
    final data = await api.createOrGetThread(eventId, targetUserId);
    return DmThreadModel.fromJson(data);
  }

  Future<List<DmThreadModel>> listThreads(String eventId) async {
    final data = await api.listThreads(eventId);
    return data.map((e) => DmThreadModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<DmThreadModel> getThread(String threadId) async {
    final data = await api.getThread(threadId);
    return DmThreadModel.fromJson(data);
  }

  Future<({List<DmMessageModel> messages, String? nextCursor})> listMessages(
    String threadId, {String? cursor}
  ) async {
    final data = await api.listMessages(threadId, cursor: cursor);
    final messages = (data['messages'] as List<dynamic>)
        .map((e) => DmMessageModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return (
      messages: messages,
      nextCursor: data['next_cursor'] as String?,
    );
  }

  Future<DmMessageModel> sendMessage(String threadId, String body) async {
    final data = await api.sendMessage(threadId, body);
    return DmMessageModel.fromJson(data);
  }

  Future<void> markRead(String threadId, String lastReadMessageId) async {
    await api.markRead(threadId, lastReadMessageId);
  }

  Future<String> negotiate() async {
    return api.negotiate();
  }
}
