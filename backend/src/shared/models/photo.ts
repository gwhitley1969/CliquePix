export type PhotoStatus = 'pending' | 'active' | 'deleted';
export type MimeType = 'image/jpeg' | 'image/png';

export interface Photo {
  id: string;
  event_id: string;
  uploaded_by_user_id: string;
  blob_path: string;
  thumbnail_blob_path: string | null;
  original_filename: string | null;
  mime_type: MimeType;
  width: number | null;
  height: number | null;
  file_size_bytes: number | null;
  status: PhotoStatus;
  created_at: Date;
  expires_at: Date;
  deleted_at: Date | null;
}

export interface PhotoWithUrls extends Photo {
  original_url: string;
  thumbnail_url: string | null;
  reaction_counts: Record<string, number>;
  user_reactions: string[];
}
