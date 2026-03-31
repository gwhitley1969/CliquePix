export type NotificationType = 'new_photo' | 'event_expiring' | 'event_expired' | 'member_joined';

export interface Notification {
  id: string;
  user_id: string;
  type: NotificationType;
  payload_json: Record<string, unknown>;
  is_read: boolean;
  created_at: Date;
}
