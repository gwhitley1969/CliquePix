class EventModel {
  final String id;
  final String cliqueId;
  final String name;
  final String? description;
  final String createdByUserId;
  final String? createdByName;
  final String? createdByAvatarUrl;
  final String? createdByAvatarThumbUrl;
  final DateTime? createdByAvatarUpdatedAt;
  final int createdByAvatarFramePreset;
  final int retentionHours;
  final String status;
  final int photoCount;
  final int videoCount;
  final String? cliqueName;
  final int? memberCount;
  final DateTime createdAt;
  final DateTime expiresAt;

  const EventModel({
    required this.id,
    required this.cliqueId,
    required this.name,
    this.description,
    required this.createdByUserId,
    this.createdByName,
    this.createdByAvatarUrl,
    this.createdByAvatarThumbUrl,
    this.createdByAvatarUpdatedAt,
    this.createdByAvatarFramePreset = 0,
    required this.retentionHours,
    required this.status,
    this.photoCount = 0,
    this.videoCount = 0,
    this.cliqueName,
    this.memberCount,
    required this.createdAt,
    required this.expiresAt,
  });

  bool get isActive => status == 'active';
  bool get isExpired => status == 'expired';
  bool get isExpiringSoon => isActive && expiresAt.difference(DateTime.now()).inHours < 24;

  /// Stable cache key for the creator's avatar.
  String? get createdByAvatarCacheKey {
    if (createdByAvatarUrl == null) return null;
    return 'avatar_${createdByUserId}_v${createdByAvatarUpdatedAt?.millisecondsSinceEpoch ?? 0}';
  }

  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      id: json['id'] as String,
      cliqueId: json['clique_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      createdByUserId: json['created_by_user_id'] as String,
      createdByName: json['created_by_name'] as String?,
      createdByAvatarUrl: json['created_by_avatar_url'] as String?,
      createdByAvatarThumbUrl: json['created_by_avatar_thumb_url'] as String?,
      createdByAvatarUpdatedAt: json['created_by_avatar_updated_at'] == null
          ? null
          : DateTime.parse(json['created_by_avatar_updated_at'] as String),
      createdByAvatarFramePreset:
          (json['created_by_avatar_frame_preset'] as num?)?.toInt() ?? 0,
      retentionHours: (json['retention_hours'] as num).toInt(),
      status: json['status'] as String,
      photoCount: (json['photo_count'] as num?)?.toInt() ?? 0,
      videoCount: (json['video_count'] as num?)?.toInt() ?? 0,
      cliqueName: json['clique_name'] as String?,
      memberCount: (json['member_count'] as num?)?.toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'clique_id': cliqueId,
        'name': name,
        'description': description,
        'created_by_user_id': createdByUserId,
        'created_by_name': createdByName,
        'created_by_avatar_url': createdByAvatarUrl,
        'created_by_avatar_thumb_url': createdByAvatarThumbUrl,
        'created_by_avatar_updated_at': createdByAvatarUpdatedAt?.toIso8601String(),
        'created_by_avatar_frame_preset': createdByAvatarFramePreset,
        'retention_hours': retentionHours,
        'status': status,
        'photo_count': photoCount,
        'video_count': videoCount,
        'clique_name': cliqueName,
        'member_count': memberCount,
        'created_at': createdAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
      };
}
