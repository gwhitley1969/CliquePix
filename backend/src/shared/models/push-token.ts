export type Platform = 'ios' | 'android';

export interface PushToken {
  id: string;
  user_id: string;
  platform: Platform;
  token: string;
  created_at: Date;
  updated_at: Date;
}
