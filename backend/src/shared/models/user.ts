export interface User {
  id: string;
  external_auth_id: string;
  display_name: string;
  email_or_phone: string;
  avatar_url: string | null;
  created_at: Date;
  updated_at: Date;
}
