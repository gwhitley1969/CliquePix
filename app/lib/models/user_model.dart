class UserModel {
  final String id;
  final String displayName;
  final String emailOrPhone;
  final String? avatarUrl;
  final DateTime createdAt;

  const UserModel({
    required this.id,
    required this.displayName,
    required this.emailOrPhone,
    this.avatarUrl,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      displayName: json['display_name'] as String,
      emailOrPhone: json['email_or_phone'] as String,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'display_name': displayName,
    'email_or_phone': emailOrPhone,
    'avatar_url': avatarUrl,
    'created_at': createdAt.toIso8601String(),
  };
}
