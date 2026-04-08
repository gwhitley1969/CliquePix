// VideoModel mirrors PhotoModel but with video-specific fields.
// Backed by the same `photos` table on the backend (media_type='video').

class VideoModel {
  final String id;
  final String eventId;
  final String uploadedByUserId;
  final String? uploadedByName;
  final String? posterUrl;
  final String? mp4FallbackUrl;
  final String? mimeType;
  final int? width;
  final int? height;
  final int? fileSizeBytes;
  final int? durationSeconds;
  final String status; // 'pending' | 'processing' | 'active' | 'rejected' | 'deleted'
  final String? processingStatus; // 'pending' | 'queued' | 'running' | 'complete' | 'failed'
  final String? processingError;
  final Map<String, int> reactionCounts;
  final List<({String id, String type})> userReactions;
  final DateTime createdAt;
  final DateTime expiresAt;

  const VideoModel({
    required this.id,
    required this.eventId,
    required this.uploadedByUserId,
    this.uploadedByName,
    this.posterUrl,
    this.mp4FallbackUrl,
    this.mimeType,
    this.width,
    this.height,
    this.fileSizeBytes,
    this.durationSeconds,
    required this.status,
    this.processingStatus,
    this.processingError,
    this.reactionCounts = const {},
    this.userReactions = const [],
    required this.createdAt,
    required this.expiresAt,
  });

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  factory VideoModel.fromJson(Map<String, dynamic> json) {
    return VideoModel(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      uploadedByUserId: json['uploaded_by_user_id'] as String,
      uploadedByName: json['uploaded_by_name'] as String?,
      posterUrl: json['poster_url'] as String?,
      mp4FallbackUrl: json['mp4_fallback_url'] as String?,
      mimeType: json['mime_type'] as String?,
      width: _toInt(json['width']),
      height: _toInt(json['height']),
      fileSizeBytes: _toInt(json['file_size_bytes']),
      durationSeconds: _toInt(json['duration_seconds']),
      status: json['status'] as String? ?? 'processing',
      processingStatus: json['processing_status'] as String?,
      processingError: json['processing_error'] as String?,
      reactionCounts: (json['reaction_counts'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, _toInt(v) ?? 0)) ??
          {},
      userReactions: (json['user_reactions'] as List<dynamic>?)
              ?.map((e) {
                if (e is String) return (id: '', type: e);
                final m = e as Map<String, dynamic>;
                return (id: m['id'] as String? ?? '', type: m['reaction_type'] as String);
              })
              .toList() ??
          [],
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : DateTime.now().add(const Duration(days: 7)),
    );
  }

  /// Whether the video is ready to play (transcoding complete).
  bool get isReady => status == 'active' && processingStatus == 'complete';

  /// Whether the video is still being processed.
  bool get isProcessing => status == 'processing';

  /// Whether processing failed.
  bool get isFailed => status == 'rejected';

  /// Formatted duration like "1:23" or "0:05".
  String get durationLabel {
    final seconds = durationSeconds ?? 0;
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}

/// Playback metadata returned by GET /api/videos/{id}/playback.
/// Contains the rewritten HLS manifest text + fresh SAS URLs for fallback and poster.
class VideoPlaybackInfo {
  final String videoId;
  final String hlsManifest; // raw .m3u8 text with per-segment SAS URLs inlined
  final String mp4FallbackUrl;
  final String posterUrl;
  final int? durationSeconds;
  final int? width;
  final int? height;

  const VideoPlaybackInfo({
    required this.videoId,
    required this.hlsManifest,
    required this.mp4FallbackUrl,
    required this.posterUrl,
    this.durationSeconds,
    this.width,
    this.height,
  });

  factory VideoPlaybackInfo.fromJson(Map<String, dynamic> json) {
    return VideoPlaybackInfo(
      videoId: json['video_id'] as String,
      hlsManifest: json['hls_manifest'] as String,
      mp4FallbackUrl: json['mp4_fallback_url'] as String,
      posterUrl: json['poster_url'] as String,
      durationSeconds: VideoModel._toInt(json['duration_seconds']),
      width: VideoModel._toInt(json['width']),
      height: VideoModel._toInt(json['height']),
    );
  }
}
