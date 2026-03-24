export type ReactionType = 'heart' | 'laugh' | 'fire' | 'wow';

export interface Reaction {
  id: string;
  photo_id: string;
  user_id: string;
  reaction_type: ReactionType;
  created_at: Date;
}
