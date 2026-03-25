class AppConstants {
  AppConstants._();

  // Duration presets (in hours)
  static const durationPresets = [24, 72, 168];
  static const durationLabels = {
    24: '24 Hours',
    72: '3 Days',
    168: '7 Days',
  };
  static const defaultDuration = 168;

  // Image compression
  static const maxImageDimension = 2048;
  static const jpegQuality = 80;
  static const maxFileSizeBytes = 10 * 1024 * 1024; // 10MB

  // Thumbnail
  static const thumbnailDimension = 400;
  static const thumbnailQuality = 70;

  // Reactions
  static const reactionTypes = ['heart', 'laugh', 'fire', 'wow'];
  static const reactionEmojis = {
    'heart': '\u2764\uFE0F',
    'laugh': '\uD83D\uDE02',
    'fire': '\uD83D\uDD25',
    'wow': '\uD83D\uDE2E',
  };

  // Token refresh
  static const tokenRefreshIntervalHours = 6;
  static const workManagerIntervalHours = 8;
  static const tokenRefreshChannel = 'token_refresh';

  // Feed
  static const feedPageSize = 20;
  static const feedPollIntervalSeconds = 30;

  // Deep link
  static const deepLinkHost = 'clique-pix.com';
  static const invitePath = '/invite/';
}
