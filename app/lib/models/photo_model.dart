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
  final List<({String id, String type})> userReactions;
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

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  factory PhotoModel.fromJson(Map<String, dynamic> json) {
    return PhotoModel(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      uploadedByUserId: json['uploaded_by_user_id'] as String,
      uploadedByName: json['uploaded_by_name'] as String?,
      originalUrl: json['original_url'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      mimeType: json['mime_type'] as String?,
      width: _toInt(json['width']),
      height: _toInt(json['height']),
      fileSizeBytes: _toInt(json['file_size_bytes']),
      status: json['status'] as String? ?? 'active',
      reactionCounts: (json['reaction_counts'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, _toInt(v) ?? 0)) ?? {},
      userReactions: (json['user_reactions'] as List<dynamic>?)
          ?.map((e) {
            if (e is String) return (id: '', type: e);
            final m = e as Map<String, dynamic>;
            return (id: m['id'] as String? ?? '', type: m['reaction_type'] as String);
          }).toList() ?? [],
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}
