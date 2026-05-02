// Models powering the "who reacted?" sheet (mobile mirror of the backend
// types in `backend/src/shared/models/reaction.ts`).
//
// One row per reaction in the reactions table — the same user appears
// twice if they left both heart AND fire on the same media. The All tab
// counts these as 2 distinct entries to match the pill totals; per-type
// tabs filter to a single reaction_type.

class ReactorAvatar {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String? avatarThumbUrl;
  final DateTime? avatarUpdatedAt;
  final int avatarFramePreset;

  const ReactorAvatar({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.avatarThumbUrl,
    this.avatarUpdatedAt,
    this.avatarFramePreset = 0,
  });

  /// Stable cache key for `cached_network_image` — churns only when the
  /// avatar is actually replaced, not when the SAS URL rotates hourly.
  String? get avatarCacheKey {
    if (avatarUrl == null) return null;
    return 'avatar_${userId}_v${avatarUpdatedAt?.millisecondsSinceEpoch ?? 0}';
  }

  factory ReactorAvatar.fromJson(Map<String, dynamic> json) {
    return ReactorAvatar(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      avatarThumbUrl: json['avatar_thumb_url'] as String?,
      avatarUpdatedAt: json['avatar_updated_at'] == null
          ? null
          : DateTime.parse(json['avatar_updated_at'] as String),
      avatarFramePreset:
          (json['avatar_frame_preset'] as num?)?.toInt() ?? 0,
    );
  }
}

class ReactorEntry {
  final String id;
  final String userId;
  final String displayName;
  final String reactionType;
  final DateTime createdAt;
  final String? avatarUrl;
  final String? avatarThumbUrl;
  final DateTime? avatarUpdatedAt;
  final int avatarFramePreset;

  const ReactorEntry({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.reactionType,
    required this.createdAt,
    this.avatarUrl,
    this.avatarThumbUrl,
    this.avatarUpdatedAt,
    this.avatarFramePreset = 0,
  });

  String? get avatarCacheKey {
    if (avatarUrl == null) return null;
    return 'avatar_${userId}_v${avatarUpdatedAt?.millisecondsSinceEpoch ?? 0}';
  }

  factory ReactorEntry.fromJson(Map<String, dynamic> json) {
    return ReactorEntry(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String? ?? '',
      reactionType: json['reaction_type'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      avatarUrl: json['avatar_url'] as String?,
      avatarThumbUrl: json['avatar_thumb_url'] as String?,
      avatarUpdatedAt: json['avatar_updated_at'] == null
          ? null
          : DateTime.parse(json['avatar_updated_at'] as String),
      avatarFramePreset:
          (json['avatar_frame_preset'] as num?)?.toInt() ?? 0,
    );
  }
}

class ReactorList {
  final String mediaId;
  final int totalReactions;
  final Map<String, int> byType;
  final List<ReactorEntry> reactors;

  const ReactorList({
    required this.mediaId,
    required this.totalReactions,
    required this.byType,
    required this.reactors,
  });

  factory ReactorList.fromJson(Map<String, dynamic> json) {
    return ReactorList(
      mediaId: json['media_id'] as String,
      totalReactions: (json['total_reactions'] as num?)?.toInt() ?? 0,
      byType: (json['by_type'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)) ??
          const {},
      reactors: (json['reactors'] as List<dynamic>?)
              ?.map((e) =>
                  ReactorEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  /// Filter reactors to a single reaction type for per-type tab content.
  List<ReactorEntry> filterByType(String reactionType) {
    return reactors.where((r) => r.reactionType == reactionType).toList();
  }
}
