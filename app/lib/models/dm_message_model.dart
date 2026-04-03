class DmMessageModel {
  final String id;
  final String threadId;
  final String? senderUserId;
  final String? senderName;
  final String body;
  final DateTime createdAt;

  const DmMessageModel({
    required this.id,
    required this.threadId,
    this.senderUserId,
    this.senderName,
    required this.body,
    required this.createdAt,
  });

  factory DmMessageModel.fromJson(Map<String, dynamic> json) {
    return DmMessageModel(
      id: json['id'] as String,
      threadId: json['thread_id'] as String,
      senderUserId: json['sender_user_id'] as String?,
      senderName: json['sender_name'] as String?,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
