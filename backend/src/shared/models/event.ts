export type RetentionHours = 24 | 72 | 168;
export type EventStatus = 'active' | 'expired';

export interface Event {
  id: string;
  clique_id: string;
  name: string;
  description: string | null;
  created_by_user_id: string;
  retention_hours: RetentionHours;
  status: EventStatus;
  created_at: Date;
  expires_at: Date;
}
