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

  // Image compression. Balanced quality (2026-06): 3024px long edge keeps a
  // 12MP phone photo at ~6.9MP (vs the old 2048px/~3.15MP); q88 is near-
  // visually-lossless. NOTE: the pro_image_editor `maxOutputSize` in
  // camera_capture_screen.dart MUST stay >= maxImageDimension or the editor
  // silently re-caps every photo before this step ever runs.
  static const maxImageDimension = 3024;
  static const jpegQuality = 88;
  static const maxFileSizeBytes = 10 * 1024 * 1024; // 10MB (3024/q88 lands ~2-4MB)

  // Thumbnail
  static const thumbnailDimension = 400;
  static const thumbnailQuality = 70;

  // Video upload (server-side limits enforced too)
  static const maxVideoDurationSeconds = 5 * 60; // 5 minutes
  static const maxVideoFileSizeBytes = 500 * 1024 * 1024; // 500MB
  static const videoBlockSizeBytes = 4 * 1024 * 1024; // 4MB blocks
  static const acceptedVideoExtensions = ['mp4', 'mov'];
  static const perUserVideoLimitPerEvent = 5;

  // Reactions
  static const reactionTypes = ['heart', 'laugh', 'fire', 'wow'];
  static const reactionEmojis = {
    'heart': '\u2764\uFE0F',
    'laugh': '\uD83D\uDE02',
    'fire': '\uD83D\uDD25',
    'wow': '\uD83D\uDE2E',
  };

  // Token refresh — see ENTRA_REFRESH_TOKEN_WORKAROUND.md
  // Layer 3: foreground-resume refresh threshold
  static const tokenStaleThresholdHours = 6;
  // Layer 4: WorkManager best-effort Android-only backup
  static const workManagerIntervalHours = 8;

  // Feed
  static const feedPageSize = 20;
  static const feedPollIntervalSeconds = 30;

  // Deep link
  static const deepLinkHost = 'clique-pix.com';
  static const invitePath = '/invite/';
}
