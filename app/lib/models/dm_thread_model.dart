class DmThreadModel {
  final String id;
  final String eventId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatarUrl;
  final String? otherUserAvatarThumbUrl;
  final DateTime? otherUserAvatarUpdatedAt;
  final int otherUserAvatarFramePreset;
  final String status;
  final int unreadCount;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final DateTime createdAt;

  const DmThreadModel({
    required this.id,
    required this.eventId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatarUrl,
    this.otherUserAvatarThumbUrl,
    this.otherUserAvatarUpdatedAt,
    this.otherUserAvatarFramePreset = 0,
    required this.status,
    this.unreadCount = 0,
    this.lastMessagePreview,
    this.lastMessageAt,
    required this.createdAt,
  });

  bool get isActive => status == 'active';
  bool get isReadOnly => status == 'read_only';

  /// Stable cache key for the other user's avatar.
  String? get otherUserAvatarCacheKey {
    if (otherUserAvatarUrl == null) return null;
    return 'avatar_${otherUserId}_v${otherUserAvatarUpdatedAt?.millisecondsSinceEpoch ?? 0}';
  }

  factory DmThreadModel.fromJson(Map<String, dynamic> json) {
    return DmThreadModel(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      otherUserId: json['other_user_id'] as String,
      otherUserName: (json['other_user_name'] as String?) ?? 'User',
      otherUserAvatarUrl: json['other_user_avatar_url'] as String?,
      otherUserAvatarThumbUrl: json['other_user_avatar_thumb_url'] as String?,
      otherUserAvatarUpdatedAt: json['other_user_avatar_updated_at'] == null
          ? null
          : DateTime.parse(json['other_user_avatar_updated_at'] as String),
      otherUserAvatarFramePreset:
          (json['other_user_avatar_frame_preset'] as num?)?.toInt() ?? 0,
      status: json['status'] as String,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      lastMessagePreview: json['last_message_preview'] as String?,
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
