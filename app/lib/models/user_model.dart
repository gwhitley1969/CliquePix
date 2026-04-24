class UserModel {
  final String id;
  final String displayName;
  final String emailOrPhone;
  final String? avatarUrl;
  final String? avatarThumbUrl;
  final DateTime? avatarUpdatedAt;
  final int avatarFramePreset;
  final bool shouldPromptForAvatar;
  final DateTime createdAt;

  const UserModel({
    required this.id,
    required this.displayName,
    required this.emailOrPhone,
    this.avatarUrl,
    this.avatarThumbUrl,
    this.avatarUpdatedAt,
    this.avatarFramePreset = 0,
    this.shouldPromptForAvatar = false,
    required this.createdAt,
  });

  /// Stable cache key for `CachedNetworkImageProvider` so the 1-hour SAS
  /// URL can rotate without invalidating cached bytes. Only changes when
  /// the user actually updates (or removes) their avatar.
  String? get avatarCacheKey {
    if (avatarUrl == null) return null;
    return 'avatar_${id}_v${avatarUpdatedAt?.millisecondsSinceEpoch ?? 0}';
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      displayName: json['display_name'] as String,
      emailOrPhone: json['email_or_phone'] as String,
      avatarUrl: json['avatar_url'] as String?,
      avatarThumbUrl: json['avatar_thumb_url'] as String?,
      avatarUpdatedAt: json['avatar_updated_at'] == null
          ? null
          : DateTime.parse(json['avatar_updated_at'] as String),
      avatarFramePreset: (json['avatar_frame_preset'] as num?)?.toInt() ?? 0,
      shouldPromptForAvatar: (json['should_prompt_for_avatar'] as bool?) ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'display_name': displayName,
    'email_or_phone': emailOrPhone,
    'avatar_url': avatarUrl,
    'avatar_thumb_url': avatarThumbUrl,
    'avatar_updated_at': avatarUpdatedAt?.toIso8601String(),
    'avatar_frame_preset': avatarFramePreset,
    'should_prompt_for_avatar': shouldPromptForAvatar,
    'created_at': createdAt.toIso8601String(),
  };

  UserModel copyWith({
    String? id,
    String? displayName,
    String? emailOrPhone,
    String? avatarUrl,
    String? avatarThumbUrl,
    DateTime? avatarUpdatedAt,
    int? avatarFramePreset,
    bool? shouldPromptForAvatar,
    DateTime? createdAt,
    bool clearAvatar = false,
  }) {
    return UserModel(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      emailOrPhone: emailOrPhone ?? this.emailOrPhone,
      avatarUrl: clearAvatar ? null : (avatarUrl ?? this.avatarUrl),
      avatarThumbUrl: clearAvatar ? null : (avatarThumbUrl ?? this.avatarThumbUrl),
      avatarUpdatedAt: clearAvatar ? null : (avatarUpdatedAt ?? this.avatarUpdatedAt),
      avatarFramePreset: avatarFramePreset ?? this.avatarFramePreset,
      shouldPromptForAvatar: shouldPromptForAvatar ?? this.shouldPromptForAvatar,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
