import 'reactor_model.dart';

class PhotoModel {
  final String id;
  final String eventId;
  final String uploadedByUserId;
  final String? uploadedByName;
  final String? uploadedByAvatarUrl;
  final String? uploadedByAvatarThumbUrl;
  final DateTime? uploadedByAvatarUpdatedAt;
  final int uploadedByAvatarFramePreset;
  final String? originalUrl;
  final String? thumbnailUrl;
  final String? mimeType;
  final int? width;
  final int? height;
  final int? fileSizeBytes;
  final String status;
  final Map<String, int> reactionCounts;
  final List<({String id, String type})> userReactions;
  /// Up to 3 distinct most-recent reactors. Drives the avatar stack on the
  /// "who reacted?" strip rendered above the reaction pill row.
  final List<ReactorAvatar> topReactors;
  final DateTime createdAt;
  final DateTime expiresAt;

  const PhotoModel({
    required this.id,
    required this.eventId,
    required this.uploadedByUserId,
    this.uploadedByName,
    this.uploadedByAvatarUrl,
    this.uploadedByAvatarThumbUrl,
    this.uploadedByAvatarUpdatedAt,
    this.uploadedByAvatarFramePreset = 0,
    this.originalUrl,
    this.thumbnailUrl,
    this.mimeType,
    this.width,
    this.height,
    this.fileSizeBytes,
    required this.status,
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

  /// Stable cache key for the uploader's avatar. Shared pattern across all
  /// models that carry a denormalized uploader/sender/creator avatar.
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

  factory PhotoModel.fromJson(Map<String, dynamic> json) {
    return PhotoModel(
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
      originalUrl: json['original_url'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      mimeType: json['mime_type'] as String?,
      width: _toInt(json['width']),
      height: _toInt(json['height']),
      fileSizeBytes: _toInt(json['file_size_bytes']),
      status: json['status'] as String? ?? 'active',
      reactionCounts: (json['reaction_counts'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, _toInt(v) ?? 0)) ?? {},
      userReactions: (json['user_reactions'] as List<dynamic>?)
          ?.map((e) {
            if (e is String) return (id: '', type: e);
            final m = e as Map<String, dynamic>;
            return (id: m['id'] as String? ?? '', type: m['reaction_type'] as String);
          }).toList() ?? [],
      topReactors: (json['top_reactors'] as List<dynamic>?)
              ?.map((e) =>
                  ReactorAvatar.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}
