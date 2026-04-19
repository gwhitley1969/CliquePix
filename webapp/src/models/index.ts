export interface User {
  id: string;
  emailOrPhone: string;
  displayName: string;
  avatarUrl?: string | null;
  createdAt?: string;
  ageVerified?: boolean;
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

export interface CliqueMember {
  userId: string;
  displayName: string;
  avatarUrl?: string | null;
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
  };
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
