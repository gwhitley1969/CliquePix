class PhotoModel {
  final String id;
  final String eventId;
  final String uploadedByUserId;
  final String? uploadedByName;
  final String? originalUrl;
  final String? thumbnailUrl;
  final String? mimeType;
  final int? width;
  final int? height;
  final int? fileSizeBytes;
  final String status;
  final Map<String, int> reactionCounts;
  final List<String> userReactions;
  final DateTime createdAt;
  final DateTime expiresAt;

  const PhotoModel({
    required this.id,
    required this.eventId,
    required this.uploadedByUserId,
    this.uploadedByName,
    this.originalUrl,
    this.thumbnailUrl,
    this.mimeType,
    this.width,
    this.height,
    this.fileSizeBytes,
    required this.status,
    this.reactionCounts = const {},
    this.userReactions = const [],
    required this.createdAt,
    required this.expiresAt,
  });

  factory PhotoModel.fromJson(Map<String, dynamic> json) {
    return PhotoModel(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      uploadedByUserId: json['uploaded_by_user_id'] as String,
      uploadedByName: json['uploaded_by_name'] as String?,
      originalUrl: json['original_url'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      mimeType: json['mime_type'] as String?,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt(),
      status: json['status'] as String? ?? 'active',
      reactionCounts: (json['reaction_counts'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toInt())) ?? {},
      userReactions: (json['user_reactions'] as List<dynamic>?)
          ?.map((e) => e as String).toList() ?? [],
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}
