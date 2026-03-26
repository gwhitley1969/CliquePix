class EventModel {
  final String id;
  final String circleId;
  final String name;
  final String? description;
  final String createdByUserId;
  final int retentionHours;
  final String status;
  final int photoCount;
  final String? circleName;
  final int? memberCount;
  final DateTime createdAt;
  final DateTime expiresAt;

  const EventModel({
    required this.id,
    required this.circleId,
    required this.name,
    this.description,
    required this.createdByUserId,
    required this.retentionHours,
    required this.status,
    this.photoCount = 0,
    this.circleName,
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
      circleId: json['circle_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      createdByUserId: json['created_by_user_id'] as String,
      retentionHours: (json['retention_hours'] as num).toInt(),
      status: json['status'] as String,
      photoCount: (json['photo_count'] as num?)?.toInt() ?? 0,
      circleName: json['circle_name'] as String?,
      memberCount: (json['member_count'] as num?)?.toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}
