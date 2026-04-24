/**
 * Avatar denormalization shape shared by every user-bearing model. Comes
 * back from the backend (post-camelize) as a cluster of four fields. Kept
 * together here so adding a fifth field (e.g., a future badge) is a
 * single-point update.
 */
export interface AvatarFields {
  avatarUrl?: string | null;
  avatarThumbUrl?: string | null;
  avatarUpdatedAt?: string | null;
  avatarFramePreset?: number;
}

export interface User extends AvatarFields {
  id: string;
  emailOrPhone: string;
  displayName: string;
  createdAt?: string;
  ageVerified?: boolean;
  /**
   * Computed by backend: true when avatar_blob_path is null AND the user
   * has not yet dismissed/snoozed the first-sign-in welcome prompt. Used
   * by the web app shell to show the `AvatarWelcomePromptModal` exactly
   * once per onboarding.
   */
  shouldPromptForAvatar?: boolean;
}

export interface Clique {
  id: string;
  name: string;
  inviteCode?: string;
  createdByUserId?: string;
  memberCount?: number;
  role?: 'owner' | 'member';
  createdAt?: string;
}

export interface CliqueMember extends AvatarFields {
  userId: string;
  displayName: string;
  role: 'owner' | 'member';
  joinedAt: string;
}

export interface CliqueEvent {
  id: string;
  cliqueId: string;
  cliqueName?: string;
  name: string;
  description?: string | null;
  createdByUserId: string;
  createdByName?: string;
  createdByAvatarUrl?: string | null;
  createdByAvatarThumbUrl?: string | null;
  createdByAvatarUpdatedAt?: string | null;
  createdByAvatarFramePreset?: number;
  retentionHours: 24 | 72 | 168;
  status: 'active' | 'expired';
  createdAt: string;
  expiresAt: string;
  photoCount?: number;
  videoCount?: number;
}

export interface MediaBase {
  id: string;
  eventId: string;
  uploadedByUserId: string;
  // Joined from users.display_name at read time; matches backend enriched shape.
  uploadedByName?: string;
  // Avatar denormalization for the uploader. Matches the prefix used
  // server-side (uploaded_by_avatar_*) after camelize conversion.
  uploadedByAvatarUrl?: string | null;
  uploadedByAvatarThumbUrl?: string | null;
  uploadedByAvatarUpdatedAt?: string | null;
  uploadedByAvatarFramePreset?: number;
  createdAt: string;
  status: 'pending' | 'active' | 'processing' | 'rejected' | 'deleted';
  // Backend enriched shape: reactionCounts is a { type -> count } map, and
  // userReactions is the list of reaction types the current user has added.
  // Reaction IDs are not returned in-line; clients track them locally after
  // a POST completes (mirroring the mobile app's reaction_bar_widget).
  reactionCounts?: Record<string, number>;
  userReactions?: string[];
}

export interface Photo extends MediaBase {
  mediaType: 'photo';
  mimeType: string;
  width: number;
  height: number;
  fileSizeBytes: number;
  thumbnailUrl?: string;
  originalUrl?: string;
}

export interface Video extends MediaBase {
  mediaType: 'video';
  durationSeconds?: number;
  processingStatus?: 'pending' | 'queued' | 'running' | 'complete' | 'failed';
  posterUrl?: string;
  previewUrl?: string;
}

export type Media = Photo | Video;

export type ReactionType = 'heart' | 'laugh' | 'fire' | 'wow';

/**
 * POST /api/photos/:id/reactions and POST /api/videos/:id/reactions return a
 * single reaction row (camelized from the backend's reactions table schema).
 * The client captures `id` so a subsequent unreact can DELETE by ID.
 */
export interface ReactionRecord {
  id: string;
  mediaId: string;
  userId: string;
  reactionType: ReactionType;
  createdAt: string;
}

export interface DmThread {
  id: string;
  eventId: string;
  otherUser: {
    id: string;
    displayName: string;
    avatarUrl?: string | null;
    avatarThumbUrl?: string | null;
    avatarUpdatedAt?: string | null;
    avatarFramePreset?: number;
  };
  // Backend also flattens these at the top level (other_user_* prefix) so
  // either shape works. Pre-camelize fields kept as optional aliases so
  // consumers tolerate either response shape during rollouts.
  otherUserId?: string;
  otherUserName?: string;
  otherUserAvatarUrl?: string | null;
  otherUserAvatarThumbUrl?: string | null;
  otherUserAvatarUpdatedAt?: string | null;
  otherUserAvatarFramePreset?: number;
  lastMessage?: {
    body: string;
    createdAt: string;
    senderUserId: string;
  };
  unreadCount: number;
  readOnly?: boolean;
}

export interface DmMessage {
  id: string;
  threadId: string;
  senderUserId: string;
  senderName?: string;
  senderAvatarUrl?: string | null;
  senderAvatarThumbUrl?: string | null;
  senderAvatarUpdatedAt?: string | null;
  senderAvatarFramePreset?: number;
  body: string;
  createdAt: string;
}

export type NotificationType =
  | 'new_photo'
  | 'new_video'
  | 'video_ready'
  | 'event_expiring'
  | 'event_expired'
  | 'member_joined'
  | 'event_deleted'
  | 'dm_message';

export interface AppNotification {
  id: string;
  type: NotificationType;
  title: string;
  subtitle?: string;
  // Backend column is `payload_json`; camelized to `payloadJson` at the
  // response boundary. Contents are arbitrary per notification type.
  payloadJson: Record<string, unknown>;
  isRead: boolean;
  createdAt: string;
}

export interface ApiEnvelope<T> {
  data: T;
  error: null;
}

export interface ApiErrorEnvelope {
  data: null;
  error: {
    code: string;
    message: string;
    request_id?: string;
  };
}
