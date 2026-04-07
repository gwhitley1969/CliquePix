export type DmThreadStatus = 'active' | 'read_only';

export interface DmThread {
  id: string;
  event_id: string;
  user_a_id: string;
  user_b_id: string;
  status: DmThreadStatus;
  user_a_last_read_message_id: string | null;
  user_b_last_read_message_id: string | null;
  last_message_at: Date | null;
  created_at: Date;
}

export interface DmMessage {
  id: string;
  thread_id: string;
  sender_user_id: string | null;
  body: string;
  created_at: Date;
}
