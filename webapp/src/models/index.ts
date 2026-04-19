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
  uploaderDisplayName?: string;
  createdAt: string;
  status: 'pending' | 'active' | 'processing' | 'rejected' | 'deleted';
  reactions?: ReactionSummary[];
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

export interface ReactionSummary {
  type: ReactionType;
  count: number;
  hasReacted?: boolean;
  reactionId?: string;
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
  payload: Record<string, unknown>;
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
