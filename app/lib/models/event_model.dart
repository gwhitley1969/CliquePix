class EventModel {
  final String id;
  final String cliqueId;
  final String name;
  final String? description;
  final String createdByUserId;
  final String? createdByName;
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

  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      id: json['id'] as String,
      cliqueId: json['clique_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      createdByUserId: json['created_by_user_id'] as String,
      createdByName: json['created_by_name'] as String?,
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
}
