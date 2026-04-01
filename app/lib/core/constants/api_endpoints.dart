class ApiEndpoints {
  ApiEndpoints._();

  // Auth
  static const authVerify = '/api/auth/verify';
  static const usersMe = '/api/users/me';

  // Circles
  static const circles = '/api/circles';
  static String circle(String id) => '/api/circles/$id';
  static String circleInvite(String id) => '/api/circles/$id/invite';
  static String circleJoin(String id) => '/api/circles/$id/join';
  static String circleMembers(String id) => '/api/circles/$id/members';
  static String circleLeave(String id) => '/api/circles/$id/members/me';
  static String circleMember(String circleId, String userId) => '/api/circles/$circleId/members/$userId';

  // Events
  static const events = '/api/events';
  static String circleEvents(String circleId) => '/api/circles/$circleId/events';
  static String event(String id) => '/api/events/$id';

  // Photos
  static String photoUploadUrl(String eventId) => '/api/events/$eventId/photos/upload-url';
  static String eventPhotos(String eventId) => '/api/events/$eventId/photos';
  static String photo(String id) => '/api/photos/$id';

  // Reactions
  static String photoReactions(String photoId) => '/api/photos/$photoId/reactions';
  static String reaction(String photoId, String reactionId) =>
      '/api/photos/$photoId/reactions/$reactionId';

  // Notifications
  static const notifications = '/api/notifications';
  static String notificationRead(String id) => '/api/notifications/$id/read';
  static const pushTokens = '/api/push-tokens';
}
