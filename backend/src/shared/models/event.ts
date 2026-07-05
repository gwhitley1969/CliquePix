// 24 = legacy (dropped from clients 2026-07; still accepted from installed
// builds <=1.0.0+12 and present on historical rows — tighten in v1.5).
export type RetentionHours = 24 | 72 | 168 | 336;
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
