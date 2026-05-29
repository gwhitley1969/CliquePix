import { generateViewSas } from './sasService';

/**
 * Canonical avatar-related columns pulled off any user row that's being
 * surfaced in an API response. Every handler that returns uploader /
 * creator / member / sender / other-user info should project these four
 * fields (with appropriate aliases) into its SELECT and pass the result
 * here for SAS signing.
 */
export interface UserAvatarRef {
  avatar_blob_path: string | null;
  avatar_thumb_blob_path: string | null;
  avatar_updated_at: Date | null | string;
  avatar_frame_preset: number | null;
}

/**
 * Shape emitted to clients. URL fields are 1-hour signed SAS or null.
 */
export interface EnrichedAvatar {
  avatar_url: string | null;
  avatar_thumb_url: string | null;
  avatar_updated_at: string | null;
  avatar_frame_preset: number;
}

const AVATAR_SAS_EXPIRY_SECONDS = 60 * 60; // 1 hour

/**
 * Sign the two avatar blob paths into short-lived read URLs. Returns the
 * frame preset + updated_at alongside so callers have everything they need
 * to return the user reference block. Null-safe: when avatar_blob_path is
 * null, the URL fields come back null too and no signing is performed.
 *
 * Long SAS expiry (1h vs photos' 5 min / videos' 15 min) is deliberate:
 * avatars render on every screen and rotating URLs faster would thrash
 * Flutter's cached_network_image cache and browsers' HTTP cache. Pair with
 * a stable `cacheKey: 'avatar_${userId}_v${updated_at.ms}'` on the client
 * so cached entries survive URL churn but invalidate when the user
 * actually changes their avatar.
 */
export async function enrichUserAvatar(ref: UserAvatarRef): Promise<EnrichedAvatar> {
  const [avatarUrl, avatarThumbUrl] = await Promise.all([
    ref.avatar_blob_path
      ? generateViewSas(ref.avatar_blob_path, AVATAR_SAS_EXPIRY_SECONDS)
      : Promise.resolve(null),
    ref.avatar_thumb_blob_path
      ? generateViewSas(ref.avatar_thumb_blob_path, AVATAR_SAS_EXPIRY_SECONDS)
      : Promise.resolve(null),
  ]);

  // Normalize updated_at to ISO string. DB driver returns Date; some test
  // paths pass strings. Null stays null.
  let updatedAtIso: string | null = null;
  if (ref.avatar_updated_at) {
    updatedAtIso =
      ref.avatar_updated_at instanceof Date
        ? ref.avatar_updated_at.toISOString()
        : String(ref.avatar_updated_at);
  }

  return {
    avatar_url: avatarUrl,
    avatar_thumb_url: avatarThumbUrl,
    avatar_updated_at: updatedAtIso,
    avatar_frame_preset: ref.avatar_frame_preset ?? 0,
  };
}

/**
 * Compute the first-sign-in welcome-prompt flag. Single source of truth so
 * every auth response returns the same answer. Pure function — handlers
 * supply the three columns straight off the user row.
 *
 *   avatar_blob_path IS NULL
 *   AND NOT avatar_prompt_dismissed
 *   AND (avatar_prompt_snoozed_until IS NULL OR avatar_prompt_snoozed_until < NOW())
 */
export function shouldPromptForAvatar(
  row: {
    avatar_blob_path: string | null;
    avatar_prompt_dismissed: boolean;
    avatar_prompt_snoozed_until: Date | string | null;
  },
  now: Date = new Date(),
): boolean {
  if (row.avatar_blob_path) return false;
  if (row.avatar_prompt_dismissed) return false;
  if (row.avatar_prompt_snoozed_until) {
    const snoozedUntil =
      row.avatar_prompt_snoozed_until instanceof Date
        ? row.avatar_prompt_snoozed_until
        : new Date(row.avatar_prompt_snoozed_until);
    if (snoozedUntil > now) return false;
  }
  return true;
}

/**
 * Minimal user row shape needed to assemble the canonical auth/profile
 * response body. Accepting this instead of the full User type keeps the
 * helper usable from places that build a partial row from a JOIN.
 *
 * Entitlement fields (migration 012) are tolerated as optional so callers
 * that haven't been updated yet still compile — the response just omits
 * the entitlement block, which the client interprets as "inactive."
 */
export interface AuthUserRow {
  id: string;
  display_name: string;
  email_or_phone: string;
  avatar_blob_path: string | null;
  avatar_thumb_blob_path: string | null;
  avatar_updated_at: Date | null;
  avatar_frame_preset: number;
  avatar_prompt_dismissed: boolean;
  avatar_prompt_snoozed_until: Date | null;
  created_at: Date;
  // Subscription state — present after migration 012 ships
  entitlement_active?: boolean;
  entitlement_product_id?: string | null;
  entitlement_period_type?: string | null;
  entitlement_will_renew?: boolean | null;
  entitlement_expires_at?: Date | null;
  entitlement_store?: string | null;
}

/**
 * Build the `entitlement` object emitted to clients. Always present on the
 * response; `active: false` for non-subscribers (the hard-paywall router
 * gate keys off this).
 */
export interface EntitlementResponse {
  active: boolean;
  product_id: string | null;
  period_type: string | null;
  will_renew: boolean | null;
  expires_at: string | null;
  store: string | null;
}

function buildEntitlementResponse(row: AuthUserRow): EntitlementResponse {
  let expiresAtIso: string | null = null;
  if (row.entitlement_expires_at) {
    expiresAtIso =
      row.entitlement_expires_at instanceof Date
        ? row.entitlement_expires_at.toISOString()
        : String(row.entitlement_expires_at);
  }
  return {
    active: row.entitlement_active ?? false,
    product_id: row.entitlement_product_id ?? null,
    period_type: row.entitlement_period_type ?? null,
    will_renew: row.entitlement_will_renew ?? null,
    expires_at: expiresAtIso,
    store: row.entitlement_store ?? null,
  };
}

/**
 * Canonical user response body emitted by auth endpoints (authVerify,
 * getMe) and every avatar-mutation endpoint. Single source of truth so
 * the Flutter UserModel + web User interface can depend on one shape.
 */
export async function buildAuthUserResponse(row: AuthUserRow): Promise<Record<string, unknown>> {
  const enriched = await enrichUserAvatar({
    avatar_blob_path: row.avatar_blob_path,
    avatar_thumb_blob_path: row.avatar_thumb_blob_path,
    avatar_updated_at: row.avatar_updated_at,
    avatar_frame_preset: row.avatar_frame_preset,
  });
  return {
    id: row.id,
    display_name: row.display_name,
    email_or_phone: row.email_or_phone,
    avatar_url: enriched.avatar_url,
    avatar_thumb_url: enriched.avatar_thumb_url,
    avatar_updated_at: enriched.avatar_updated_at,
    avatar_frame_preset: enriched.avatar_frame_preset,
    should_prompt_for_avatar: shouldPromptForAvatar(row),
    entitlement: buildEntitlementResponse(row),
    created_at: row.created_at,
  };
}
