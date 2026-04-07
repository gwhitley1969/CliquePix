export type ReactionType = 'heart' | 'laugh' | 'fire' | 'wow';

export interface Reaction {
  id: string;
  // Renamed from photo_id in migration 007. The column references photos(id)
  // which now hosts both photos and videos.
  media_id: string;
  user_id: string;
  reaction_type: ReactionType;
  created_at: Date;
}
