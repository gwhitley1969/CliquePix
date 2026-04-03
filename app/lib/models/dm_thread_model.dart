class DmThreadModel {
  final String id;
  final String eventId;
  final String otherUserId;
  final String otherUserName;
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
    required this.status,
    this.unreadCount = 0,
    this.lastMessagePreview,
    this.lastMessageAt,
    required this.createdAt,
  });

  bool get isActive => status == 'active';
  bool get isReadOnly => status == 'read_only';

  factory DmThreadModel.fromJson(Map<String, dynamic> json) {
    return DmThreadModel(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      otherUserId: json['other_user_id'] as String,
      otherUserName: (json['other_user_name'] as String?) ?? 'User',
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
