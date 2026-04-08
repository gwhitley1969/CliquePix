import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../models/dm_message_model.dart';

/// VideoReadyEvent — emitted when the backend pushes a `video_ready`
/// notification via Web PubSub. Fans out to listeners that want to update
/// the feed in-place when a video finishes transcoding.
class VideoReadyEvent {
  final String eventId;
  final String videoId;
  const VideoReadyEvent({required this.eventId, required this.videoId});
}

class DmRealtimeService {
  WebSocketChannel? _channel;
  final _messageController = StreamController<DmMessageModel>.broadcast();
  final _videoReadyController = StreamController<VideoReadyEvent>.broadcast();
  Timer? _reconnectTimer;
  String? _url;
  int _reconnectAttempts = 0;
  bool _disposed = false;
  Future<String> Function()? onNegotiate;

  Stream<DmMessageModel> get onMessage => _messageController.stream;
  Stream<VideoReadyEvent> get onVideoReady => _videoReadyController.stream;
  bool get isConnected => _channel != null;

  Future<void> connect(String url) async {
    _url = url;
    _reconnectAttempts = 0;
    _disposed = false;
    _connectInternal(url);
  }

  void _connectInternal(String url) {
    try {
      _channel?.sink.close();
    } catch (_) {}

    debugPrint('[CliquePix DM] Connecting to Web PubSub...');
    _channel = WebSocketChannel.connect(Uri.parse(url));

    _channel!.stream.listen(
      (data) {
        _reconnectAttempts = 0;
        try {
          final json = jsonDecode(data as String) as Map<String, dynamic>;
          final type = json['type'] as String?;
          if (type == 'dm_message_created') {
            final messageJson = json['message'] as Map<String, dynamic>;
            final message = DmMessageModel.fromJson(messageJson);
            _messageController.add(message);
            debugPrint('[CliquePix DM] Received message: ${message.id}');
          } else if (type == 'video_ready') {
            final eventId = json['event_id'] as String?;
            final videoId = json['video_id'] as String?;
            if (eventId != null && videoId != null) {
              _videoReadyController.add(VideoReadyEvent(eventId: eventId, videoId: videoId));
              debugPrint('[CliquePix Realtime] video_ready: $videoId in event $eventId');
            }
          }
        } catch (e) {
          debugPrint('[CliquePix DM] Failed to parse message: $e');
        }
      },
      onError: (error) {
        debugPrint('[CliquePix DM] WebSocket error: $error');
        _scheduleReconnect();
      },
      onDone: () {
        debugPrint('[CliquePix DM] WebSocket closed');
        _scheduleReconnect();
      },
    );

    debugPrint('[CliquePix DM] Connected');
  }

  void _scheduleReconnect() {
    if (_disposed || _url == null) return;
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectDelay());
    debugPrint('[CliquePix DM] Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(delay, () async {
      if (_disposed) return;
      // Re-negotiate for a fresh URL (old token may have expired)
      if (onNegotiate != null) {
        try {
          _url = await onNegotiate!();
          debugPrint('[CliquePix DM] Re-negotiated fresh URL');
        } catch (e) {
          debugPrint('[CliquePix DM] Re-negotiate failed: $e');
        }
      }
      if (_url != null) _connectInternal(_url!);
    });
  }

  int _reconnectDelay() {
    // Exponential backoff: 1, 2, 4, 8, 16, max 30 seconds
    final delay = (1 << (_reconnectAttempts - 1)).clamp(1, 30);
    return delay;
  }

  void disconnect() {
    _disposed = true;
    _reconnectTimer?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _url = null;
    debugPrint('[CliquePix DM] Disconnected');
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _videoReadyController.close();
  }
}
