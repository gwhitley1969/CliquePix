import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/constants/api_endpoints.dart';

class DmApi {
  final Dio dio;
  DmApi(this.dio);

  Future<Map<String, dynamic>> createOrGetThread(String eventId, String targetUserId) async {
    final response = await dio.post(
      ApiEndpoints.eventDmThreads(eventId),
      data: {'target_user_id': targetUserId},
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> listThreads(String eventId) async {
    debugPrint('[CliquePix DM] listThreads eventId=$eventId url=${ApiEndpoints.eventDmThreads(eventId)}');
    final response = await dio.get(ApiEndpoints.eventDmThreads(eventId));
    debugPrint('[CliquePix DM] listThreads response status=${response.statusCode} data=${response.data}');
    return response.data['data'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> getThread(String threadId) async {
    final response = await dio.get(ApiEndpoints.dmThread(threadId));
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> listMessages(String threadId, {String? cursor, int limit = 50}) async {
    final params = <String, dynamic>{'limit': limit};
    if (cursor != null) params['cursor'] = cursor;
    final response = await dio.get(ApiEndpoints.dmMessages(threadId), queryParameters: params);
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendMessage(String threadId, String body) async {
    final response = await dio.post(
      ApiEndpoints.dmMessages(threadId),
      data: {'body': body},
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<void> markRead(String threadId, String lastReadMessageId) async {
    await dio.patch(
      ApiEndpoints.dmRead(threadId),
      data: {'last_read_message_id': lastReadMessageId},
    );
  }

  Future<String> negotiate() async {
    final response = await dio.post(ApiEndpoints.dmNegotiate);
    return response.data['data']['url'] as String;
  }
}
