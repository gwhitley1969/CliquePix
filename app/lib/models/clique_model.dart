class CliqueModel {
  final String id;
  final String name;
  final String inviteCode;
  final String createdByUserId;
  final int memberCount;
  final DateTime createdAt;

  const CliqueModel({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.createdByUserId,
    required this.memberCount,
    required this.createdAt,
  });

  factory CliqueModel.fromJson(Map<String, dynamic> json) {
    return CliqueModel(
      id: json['id'] as String,
      name: json['name'] as String,
      inviteCode: json['invite_code'] as String,
      createdByUserId: json['created_by_user_id'] as String,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'invite_code': inviteCode,
        'created_by_user_id': createdByUserId,
        'member_count': memberCount,
        'created_at': createdAt.toIso8601String(),
      };
}

class CliqueMemberModel {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String? avatarThumbUrl;
  final DateTime? avatarUpdatedAt;
  final int avatarFramePreset;
  final String role;
  final DateTime joinedAt;

  const CliqueMemberModel({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.avatarThumbUrl,
    this.avatarUpdatedAt,
    this.avatarFramePreset = 0,
    required this.role,
    required this.joinedAt,
  });

  /// Stable cache key for the member's avatar.
  String? get avatarCacheKey {
    if (avatarUrl == null) return null;
    return 'avatar_${userId}_v${avatarUpdatedAt?.millisecondsSinceEpoch ?? 0}';
  }

  factory CliqueMemberModel.fromJson(Map<String, dynamic> json) {
    return CliqueMemberModel(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      avatarThumbUrl: json['avatar_thumb_url'] as String?,
      avatarUpdatedAt: json['avatar_updated_at'] == null
          ? null
          : DateTime.parse(json['avatar_updated_at'] as String),
      avatarFramePreset: (json['avatar_frame_preset'] as num?)?.toInt() ?? 0,
      role: json['role'] as String,
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }
}
