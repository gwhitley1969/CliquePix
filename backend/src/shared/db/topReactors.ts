import { query } from '../services/dbService';
import { enrichUserAvatar } from '../services/avatarEnricher';
import { ReactorAvatar } from '../models/reaction';

const TOP_REACTORS_LIMIT = 3;

/**
 * Returns up to 3 distinct most-recent reactors on a single media row,
 * with avatars enriched into 1-hour signed SAS URLs.
 *
 * Used by enrichPhotoWithUrls / enrichVideoWithUrls to seed the
 * "who reacted?" strip's avatar stack on every feed row. When the user
 * leaves multiple reaction types we collapse to one entry per user
 * (their most-recent reaction wins) — purely a visual concern; the
 * separate GET /api/{photos|videos}/:id/reactions endpoint returns the
 * raw row-per-reaction list.
 *
 * Empty array when the media has no reactions. The query is index-backed
 * by the existing `UNIQUE (media_id, user_id, reaction_type)` constraint
 * (media_id is the leading column).
 */
export async function fetchTopReactors(mediaId: string): Promise<ReactorAvatar[]> {
  const rows = await query<{
    user_id: string;
    display_name: string;
    avatar_blob_path: string | null;
    avatar_thumb_blob_path: string | null;
    avatar_updated_at: Date | null;
    avatar_frame_preset: number | null;
  }>(
    `SELECT u.id AS user_id, u.display_name,
            u.avatar_blob_path, u.avatar_thumb_blob_path,
            u.avatar_updated_at, u.avatar_frame_preset
     FROM (
       SELECT user_id, MAX(created_at) AS recent
       FROM reactions
       WHERE media_id = $1
       GROUP BY user_id
       ORDER BY recent DESC
       LIMIT $2
     ) recent_users
     JOIN users u ON u.id = recent_users.user_id
     ORDER BY recent_users.recent DESC`,
    [mediaId, TOP_REACTORS_LIMIT],
  );

  return Promise.all(
    rows.map(async (row): Promise<ReactorAvatar> => {
      const avatar = await enrichUserAvatar({
        avatar_blob_path: row.avatar_blob_path,
        avatar_thumb_blob_path: row.avatar_thumb_blob_path,
        avatar_updated_at: row.avatar_updated_at,
        avatar_frame_preset: row.avatar_frame_preset,
      });
      return {
        user_id: row.user_id,
        display_name: row.display_name,
        avatar_url: avatar.avatar_url,
        avatar_thumb_url: avatar.avatar_thumb_url,
        avatar_updated_at: avatar.avatar_updated_at,
        avatar_frame_preset: avatar.avatar_frame_preset,
      };
    }),
  );
}
