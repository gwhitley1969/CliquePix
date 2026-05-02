// VideoModel mirrors PhotoModel but with video-specific fields.
// Backed by the same `photos` table on the backend (media_type='video').

import 'reactor_model.dart';

class VideoModel {
  final String id;
  final String eventId;
  final String uploadedByUserId;
  final String? uploadedByName;
  final String? uploadedByAvatarUrl;
  final String? uploadedByAvatarThumbUrl;
  final DateTime? uploadedByAvatarUpdatedAt;
  final int uploadedByAvatarFramePreset;
  final String? posterUrl;
  final String? mp4FallbackUrl;
  /// Instant-preview SAS URL for the ORIGINAL blob. Populated by the backend
  /// ONLY when the caller is the uploader AND the video is still in
  /// processing/pending state. Null for everyone else and for active videos.
  /// Lets the uploader play the video immediately without waiting for the
  /// transcoder to finish.
  final String? previewUrl;
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
  /// Up to 3 distinct most-recent reactors. Drives the avatar stack on the
  /// "who reacted?" strip — same semantics as PhotoModel.topReactors.
  final List<ReactorAvatar> topReactors;
  final DateTime createdAt;
  final DateTime expiresAt;

  const VideoModel({
    required this.id,
    required this.eventId,
    required this.uploadedByUserId,
    this.uploadedByName,
    this.uploadedByAvatarUrl,
    this.uploadedByAvatarThumbUrl,
    this.uploadedByAvatarUpdatedAt,
    this.uploadedByAvatarFramePreset = 0,
    this.posterUrl,
    this.mp4FallbackUrl,
    this.previewUrl,
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
    this.topReactors = const [],
    required this.createdAt,
    required this.expiresAt,
  });

  /// Total reactions across all types — used by the strip's "N reactions"
  /// label. Matches what the existing pill row sums to.
  int get totalReactions =>
      reactionCounts.values.fold<int>(0, (sum, count) => sum + count);

  /// Stable cache key for the uploader's avatar.
  String? get uploadedByAvatarCacheKey {
    if (uploadedByAvatarUrl == null) return null;
    return 'avatar_${uploadedByUserId}_v${uploadedByAvatarUpdatedAt?.millisecondsSinceEpoch ?? 0}';
  }

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
      uploadedByAvatarUrl: json['uploaded_by_avatar_url'] as String?,
      uploadedByAvatarThumbUrl: json['uploaded_by_avatar_thumb_url'] as String?,
      uploadedByAvatarUpdatedAt: json['uploaded_by_avatar_updated_at'] == null
          ? null
          : DateTime.parse(json['uploaded_by_avatar_updated_at'] as String),
      uploadedByAvatarFramePreset:
          (json['uploaded_by_avatar_frame_preset'] as num?)?.toInt() ?? 0,
      posterUrl: json['poster_url'] as String?,
      mp4FallbackUrl: json['mp4_fallback_url'] as String?,
      previewUrl: json['preview_url'] as String?,
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
      topReactors: (json['top_reactors'] as List<dynamic>?)
              ?.map((e) =>
                  ReactorAvatar.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
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
