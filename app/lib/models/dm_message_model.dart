class DmMessageModel {
  final String id;
  final String threadId;
  final String? senderUserId;
  final String? senderName;
  final String? senderAvatarUrl;
  final String? senderAvatarThumbUrl;
  final DateTime? senderAvatarUpdatedAt;
  final int senderAvatarFramePreset;
  final String body;
  final DateTime createdAt;

  const DmMessageModel({
    required this.id,
    required this.threadId,
    this.senderUserId,
    this.senderName,
    this.senderAvatarUrl,
    this.senderAvatarThumbUrl,
    this.senderAvatarUpdatedAt,
    this.senderAvatarFramePreset = 0,
    required this.body,
    required this.createdAt,
  });

  /// Stable cache key for the sender's avatar.
  String? get senderAvatarCacheKey {
    if (senderAvatarUrl == null || senderUserId == null) return null;
    return 'avatar_${senderUserId}_v${senderAvatarUpdatedAt?.millisecondsSinceEpoch ?? 0}';
  }

  factory DmMessageModel.fromJson(Map<String, dynamic> json) {
    return DmMessageModel(
      id: json['id'] as String,
      threadId: json['thread_id'] as String,
      senderUserId: json['sender_user_id'] as String?,
      senderName: json['sender_name'] as String?,
      senderAvatarUrl: json['sender_avatar_url'] as String?,
      senderAvatarThumbUrl: json['sender_avatar_thumb_url'] as String?,
      senderAvatarUpdatedAt: json['sender_avatar_updated_at'] == null
          ? null
          : DateTime.parse(json['sender_avatar_updated_at'] as String),
      senderAvatarFramePreset:
          (json['sender_avatar_frame_preset'] as num?)?.toInt() ?? 0,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
