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

/**
 * One reactor entry returned by GET /api/photos/{id}/reactions and
 * GET /api/videos/{id}/reactions. Surfaces enough to render a row in
 * the "who reacted" sheet: the reaction itself + the reactor's display
 * name + their enriched avatar (1-hour SAS).
 *
 * One row per reaction in the reactions table — a single user who left
 * BOTH heart AND fire produces TWO entries here. The client groups for
 * the "All" tab as needed.
 */
export interface ReactorEntry {
  id: string;
  user_id: string;
  display_name: string;
  reaction_type: ReactionType;
  created_at: string;
  avatar_url: string | null;
  avatar_thumb_url: string | null;
  avatar_updated_at: string | null;
  avatar_frame_preset: number;
}

/**
 * Compact avatar reference for the strip's avatar stack. Surfaced on
 * every photo/video feed row so the strip can render real reactor
 * avatars without an extra round-trip when the count is non-zero.
 *
 * Up to 3 distinct most-recent reactors per media. When the same user
 * left multiple reactions, only their most-recent reaction is reflected
 * here (de-duped by user_id).
 */
export interface ReactorAvatar {
  user_id: string;
  display_name: string;
  avatar_url: string | null;
  avatar_thumb_url: string | null;
  avatar_updated_at: string | null;
  avatar_frame_preset: number;
}

/**
 * Response body for GET /api/photos/{id}/reactions and the video equivalent.
 *
 * - total_reactions = reactors.length (sum of by_type values; matches the
 *   existing reaction_counts pill totals so users see no surprising delta).
 * - by_type = per-type count, identical in shape to PhotoWithUrls.reaction_counts
 *   but scoped to this response so the sheet is self-contained.
 * - reactors = one row per reaction, sorted DESC by created_at, capped at 200.
 */
export interface ReactorListResponse {
  media_id: string;
  total_reactions: number;
  by_type: Record<ReactionType, number>;
  reactors: ReactorEntry[];
}
