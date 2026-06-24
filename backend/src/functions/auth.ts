import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import * as jwt from 'jsonwebtoken';
import jwksRsa from 'jwks-rsa';
import { query, queryOne, execute } from '../shared/services/dbService';
import { deleteBlob, deleteMediaAssets } from '../shared/services/blobService';
import { handleError } from '../shared/middleware/errorHandler';
import { authenticateRequest } from '../shared/middleware/authMiddleware';
import { successResponse, errorResponse } from '../shared/utils/response';
import { trackEvent } from '../shared/services/telemetryService';
import { User } from '../shared/models/user';
import { buildAuthUserResponse } from '../shared/services/avatarEnricher';
import { deleteSubscriberFromRc } from '../shared/services/revenuecatRestClient';
import { selectSuccessorUserId, promoteToOwner, notifyNewOwner } from '../shared/services/cliqueOwnershipService';
import { forceSyncFromRcApi } from '../shared/services/entitlementService';

const TENANT_ID = process.env.ENTRA_TENANT_ID || '';
const CLIENT_ID = process.env.ENTRA_CLIENT_ID || '';

const jwksClient = jwksRsa({
  jwksUri: `https://cliquepix.ciamlogin.com/${TENANT_ID}/discovery/v2.0/keys`,
  cache: true,
  cacheMaxEntries: 5,
  cacheMaxAge: 600000,
});

async function getSigningKey(kid: string): Promise<string> {
  const key = await jwksClient.getSigningKey(kid);
  return key.getPublicKey();
}

async function authVerify(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authHeader = req.headers.get('authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return errorResponse('UNAUTHORIZED', 'Authentication required.', 401);
    }

    const token = authHeader.slice(7);
    const decoded = jwt.decode(token, { complete: true });
    if (!decoded || typeof decoded === 'string') {
      return errorResponse('UNAUTHORIZED', 'Invalid token.', 401);
    }

    const kid = decoded.header.kid;
    if (!kid) {
      return errorResponse('UNAUTHORIZED', 'Invalid token.', 401);
    }

    const signingKey = await getSigningKey(kid);
    const payload = jwt.verify(token, signingKey, {
      algorithms: ['RS256'],
      issuer: `https://${TENANT_ID}.ciamlogin.com/${TENANT_ID}/v2.0`,
      audience: CLIENT_ID,
    }) as jwt.JwtPayload;

    const externalAuthId = payload.sub || payload.oid;
    if (!externalAuthId) {
      return errorResponse('UNAUTHORIZED', 'Invalid token claims.', 401);
    }

    // Extract user info from token claims
    const email = payload.preferred_username || payload.email ||
      (Array.isArray(payload.emails) ? payload.emails[0] : '') || '';
    const displayName = payload.name ||
      [payload.given_name, payload.family_name].filter(Boolean).join(' ') ||
      email.split('@')[0] || 'User';

    // Upsert user.
    const user = await queryOne<User>(
      `INSERT INTO users (external_auth_id, display_name, email_or_phone, trial_ends_at)
       VALUES ($1, $2, $3, NOW() + INTERVAL '7 days')
       ON CONFLICT (external_auth_id) DO UPDATE SET
         display_name = EXCLUDED.display_name,
         email_or_phone = EXCLUDED.email_or_phone,
         trial_ends_at = COALESCE(users.trial_ends_at, EXCLUDED.trial_ends_at),
         updated_at = NOW()
       RETURNING *`,
      [externalAuthId, displayName, email],
    );

    trackEvent('auth_verify_success');

    return successResponse(await buildAuthUserResponse(user!));
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

async function getMe(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const user = await queryOne<User>(
      'SELECT * FROM users WHERE id = $1',
      [authUser.id],
    );

    if (!user) {
      return errorResponse('USER_NOT_FOUND', 'User not found.', 404);
    }

    return successResponse(await buildAuthUserResponse(user));
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

async function deleteMe(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    // 1. Find cliques where user is the sole owner (only member)
    const soleOwnerCliques = await query<{ id: string }>(
      `SELECT c.id FROM cliques c
       WHERE c.created_by_user_id = $1
       AND (SELECT COUNT(*) FROM clique_members cm WHERE cm.clique_id = c.id) = 1`,
      [authUser.id],
    );

    // 2. For sole-owner cliques: delete all photo blobs, then delete clique (CASCADE)
    for (const clique of soleOwnerCliques) {
      const cliqueMedia = await query<{ blob_path: string; thumbnail_blob_path: string | null; media_type: string }>(
        `SELECT p.blob_path, p.thumbnail_blob_path, p.media_type FROM photos p
         JOIN events e ON e.id = p.event_id
         WHERE e.clique_id = $1`,
        [clique.id],
      );
      // Branch on media_type so video rows prefix-delete their HLS/fallback/
      // poster dir, not just blob_path + thumbnail (which orphaned them).
      for (const m of cliqueMedia) {
        try { await deleteMediaAssets(m); } catch (_) { /* best-effort */ }
      }
      await execute('DELETE FROM cliques WHERE id = $1', [clique.id]);
    }

    // 3. Delete remaining media uploaded by user (in other cliques)
    const userMedia = await query<{ blob_path: string; thumbnail_blob_path: string | null; media_type: string }>(
      'SELECT blob_path, thumbnail_blob_path, media_type FROM photos WHERE uploaded_by_user_id = $1',
      [authUser.id],
    );
    for (const m of userMedia) {
      try { await deleteMediaAssets(m); } catch (_) { /* best-effort */ }
    }
    await execute('DELETE FROM photos WHERE uploaded_by_user_id = $1', [authUser.id]);

    // 4. Delete avatar blobs if any. deleteIfExists is idempotent so missing
    //    blobs are fine. Fixed paths per user (no DB read needed).
    await deleteBlob(`avatars/${authUser.id}/original.jpg`);
    await deleteBlob(`avatars/${authUser.id}/thumb.jpg`);

    // 5. GDPR/CCPA "right to be forgotten" — remove from RevenueCat too.
    //    Best-effort: failure logs but does NOT block the account delete.
    //    The user's local DB row is the source of truth for our app; an RC
    //    orphan customer is a side effect, not a blocker.
    const rcDeleted = await deleteSubscriberFromRc(authUser.id);
    if (!rcDeleted) {
      trackEvent('rc_subscriber_delete_failed', { userId: authUser.id });
    }

    // 5b. Hand off ownership of cliques the user OWNS that still have other
    //     members, so the clique isn't left ownerless after the cascade below
    //     deletes the user's clique_members(role='owner') row and SET NULLs
    //     created_by. (Sole-owner-sole-member cliques were already deleted in
    //     step 2; this handles the multi-member case — disjoint sets.) Promote
    //     the longest-tenured remaining member and keep created_by in lockstep.
    const ownedMultiMember = await query<{ clique_id: string }>(
      `SELECT cm.clique_id FROM clique_members cm
       WHERE cm.user_id = $1 AND cm.role = 'owner'
       AND (SELECT COUNT(*) FROM clique_members x WHERE x.clique_id = cm.clique_id) > 1`,
      [authUser.id],
    );
    for (const { clique_id } of ownedMultiMember) {
      const successor = await selectSuccessorUserId(clique_id, authUser.id);
      if (successor) {
        await promoteToOwner(clique_id, successor);
        await notifyNewOwner(clique_id, successor);
        trackEvent('clique_ownership_transferred', {
          cliqueId: clique_id,
          from: authUser.id,
          to: successor,
          reason: 'account_deleted',
        });
      }
    }

    // 6. Delete user record (CASCADE: clique_members, reactions, push_tokens, notifications)
    // (SET NULL via migration 004: cliques.created_by_user_id, events.created_by_user_id)
    await execute('DELETE FROM users WHERE id = $1', [authUser.id]);

    trackEvent('account_deleted', { userId: authUser.id });

    return successResponse({ message: 'Account deleted.' });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// ============================================================================
// POST /api/users/me/entitlement/refresh
// ============================================================================
// Manual force-sync of entitlement state from RevenueCat's REST API. Used
// in two paths:
//   1. User-initiated: Profile → "Refresh Subscription" tile (visible after
//      the version-tap-7-times diagnostics unlock).
//   2. Client auto-recovery: 30s after a successful purchase, if the
//      backend webhook hasn't landed yet, the client calls this so the
//      paywall finally dismisses.
//
// Throttled to 1 call per minute per user via the same fire-and-forget
// approach authMiddleware uses for last_activity_at — we don't want a
// stuck user retrying constantly to hammer RC's API.
const lastRefreshCallByUser = new Map<string, number>();
const REFRESH_THROTTLE_MS = 60_000;

async function entitlementRefresh(
  req: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const now = Date.now();
    const last = lastRefreshCallByUser.get(authUser.id) ?? 0;
    if (now - last < REFRESH_THROTTLE_MS) {
      return errorResponse(
        'RATE_LIMITED',
        'Please wait a moment before refreshing your subscription again.',
        429,
      );
    }
    lastRefreshCallByUser.set(authUser.id, now);

    await forceSyncFromRcApi(authUser.id);

    // Re-read the user row + emit the full enriched response so the client
    // can drop it straight into AuthState without an extra round-trip.
    const user = await queryOne<User>('SELECT * FROM users WHERE id = $1', [authUser.id]);
    if (!user) {
      return errorResponse('USER_NOT_FOUND', 'User not found.', 404);
    }

    trackEvent('entitlement_refresh_invoked', { userId: authUser.id });
    return successResponse(await buildAuthUserResponse(user));
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

app.http('authVerify', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'auth/verify',
  handler: authVerify,
});

app.http('getMe', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'users/me',
  handler: getMe,
});

app.http('deleteMe', {
  methods: ['DELETE'],
  authLevel: 'anonymous',
  route: 'users/me',
  handler: deleteMe,
});

app.http('entitlementRefresh', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'users/me/entitlement/refresh',
  handler: entitlementRefresh,
});
