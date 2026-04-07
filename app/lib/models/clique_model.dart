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
}

class CliqueMemberModel {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String role;
  final DateTime joinedAt;

  const CliqueMemberModel({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.role,
    required this.joinedAt,
  });

  factory CliqueMemberModel.fromJson(Map<String, dynamic> json) {
    return CliqueMemberModel(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      role: json['role'] as String,
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }
}
