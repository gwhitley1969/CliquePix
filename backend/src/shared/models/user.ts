export interface User {
  id: string;
  external_auth_id: string;
  display_name: string;
  email_or_phone: string;
  // Legacy column from migration 001, retained but unused post-migration 010.
  // New code reads avatar_blob_path / avatar_thumb_blob_path and emits signed
  // SAS URLs via enrichUserAvatar. A future migration 011 can drop this.
  avatar_url: string | null;
  avatar_blob_path: string | null;
  avatar_thumb_blob_path: string | null;
  avatar_updated_at: Date | null;
  avatar_frame_preset: number;
  avatar_prompt_dismissed: boolean;
  avatar_prompt_snoozed_until: Date | null;
  age_verified_at: Date | null;
  created_at: Date;
  updated_at: Date;
}
