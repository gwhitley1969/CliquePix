class ApiEndpoints {
  ApiEndpoints._();

  // Auth
  static const authVerify = '/api/auth/verify';
  static const usersMe = '/api/users/me';

  // Avatar (profile picture)
  static const avatarUploadUrl = '/api/users/me/avatar/upload-url';
  static const avatarConfirm = '/api/users/me/avatar';
  static const avatarDelete = '/api/users/me/avatar';
  static const avatarFrame = '/api/users/me/avatar/frame';
  static const avatarPrompt = '/api/users/me/avatar-prompt';

  // Cliques
  static const cliques = '/api/cliques';
  static String clique(String id) => '/api/cliques/$id';
  static String cliqueInvite(String id) => '/api/cliques/$id/invite';
  static String cliqueJoin(String id) => '/api/cliques/$id/join';
  static String cliqueMembers(String id) => '/api/cliques/$id/members';
  static String cliqueLeave(String id) => '/api/cliques/$id/members/me';
  static String cliqueMember(String cliqueId, String userId) => '/api/cliques/$cliqueId/members/$userId';

  // Events
  static const events = '/api/events';
  static String cliqueEvents(String cliqueId) => '/api/cliques/$cliqueId/events';
  static String event(String id) => '/api/events/$id';

  // Photos
  static String photoUploadUrl(String eventId) => '/api/events/$eventId/photos/upload-url';
  static String eventPhotos(String eventId) => '/api/events/$eventId/photos';
  static String photo(String id) => '/api/photos/$id';

  // Videos
  static String videoUploadUrl(String eventId) => '/api/events/$eventId/videos/upload-url';
  static String eventVideos(String eventId) => '/api/events/$eventId/videos';
  static String video(String id) => '/api/videos/$id';
  static String videoPlayback(String id) => '/api/videos/$id/playback';

  // Unified mixed-media feed (photos + videos in one ordered list)
  static String eventMedia(String eventId) => '/api/events/$eventId/media';

  // Reactions — photos
  static String photoReactions(String photoId) => '/api/photos/$photoId/reactions';
  static String reaction(String photoId, String reactionId) =>
      '/api/photos/$photoId/reactions/$reactionId';

  // Reactions — videos
  static String videoReactions(String videoId) => '/api/videos/$videoId/reactions';
  static String videoReaction(String videoId, String reactionId) =>
      '/api/videos/$videoId/reactions/$reactionId';

  // DMs
  static String eventDmThreads(String eventId) => '/api/events/$eventId/dm-threads';
  static String dmThread(String threadId) => '/api/dm-threads/$threadId';
  static String dmMessages(String threadId) => '/api/dm-threads/$threadId/messages';
  static String dmRead(String threadId) => '/api/dm-threads/$threadId/read';
  static const dmNegotiate = '/api/realtime/dm/negotiate';

  // Notifications
  static const notifications = '/api/notifications';
  static String notificationRead(String id) => '/api/notifications/$id/read';
  static const pushTokens = '/api/push-tokens';
}
