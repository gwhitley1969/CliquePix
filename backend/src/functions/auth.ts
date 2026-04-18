import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import * as jwt from 'jsonwebtoken';
import jwksRsa from 'jwks-rsa';
import { query, queryOne, execute } from '../shared/services/dbService';
import { deleteBlob } from '../shared/services/blobService';
import { handleError } from '../shared/middleware/errorHandler';
import { authenticateRequest } from '../shared/middleware/authMiddleware';
import { successResponse, errorResponse } from '../shared/utils/response';
import { trackEvent } from '../shared/services/telemetryService';
import { User } from '../shared/models/user';
import { MIN_AGE, ageBucket, calculateAge, parseDob } from '../shared/utils/ageUtils';
import { deleteEntraUserByOid } from '../shared/auth/entraGraphClient';

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

/**
 * Pull the dateOfBirth claim out of a decoded JWT payload. Entra emits
 * directory-schema-extension claims with GUID-prefixed keys of the form
 * `extension_<b2cExtensionsAppId-without-hyphens>_dateOfBirth`. We search
 * case-insensitively so configuration changes in Entra don't break us.
 * Returns null when the claim is absent (grandfathered pre-age-gate users).
 */
export function extractDobFromClaims(
  payload: Record<string, unknown>,
): string | null {
  for (const key of Object.keys(payload)) {
    if (key.toLowerCase().includes('dateofbirth')) {
      const raw = payload[key];
      if (typeof raw === 'string' && raw.trim().length > 0) return raw.trim();
    }
  }
  return null;
}

/**
 * Accept three date formats: YYYY-MM-DD (Entra default), MM/DD/YYYY, MMDDYYYY.
 * Returns null for anything else. Mirrors the old CAE validateAge logic.
 */
export function parseAnyDob(raw: string): Date | null {
  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) return parseDob(raw);
  let m = raw.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (m) return parseDob(`${m[3]}-${m[1]}-${m[2]}`);
  m = raw.match(/^(\d{2})(\d{2})(\d{4})$/);
  if (m) return parseDob(`${m[3]}-${m[1]}-${m[2]}`);
  return null;
}

export type AgeGateDecision =
  | { action: 'pass'; age: number }
  | { action: 'block'; reason: 'under_13' }
  | { action: 'grandfather'; reason: 'missing_claim' | 'unparseable_dob' };

/**
 * Compute the age gate decision from a JWT payload. Pure function, no I/O.
 * Exported for unit tests. The caller handles side effects (DB write,
 * Graph delete, telemetry, HTTP response).
 */
export function decideAgeGate(
  payload: Record<string, unknown>,
  now: Date = new Date(),
): AgeGateDecision {
  const rawDob = extractDobFromClaims(payload);
  if (!rawDob) return { action: 'grandfather', reason: 'missing_claim' };
  const dob = parseAnyDob(rawDob);
  if (!dob) return { action: 'grandfather', reason: 'unparseable_dob' };
  const age = calculateAge(dob, now);
  if (age < MIN_AGE) return { action: 'block', reason: 'under_13' };
  return { action: 'pass', age };
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

    // Age-gate branching (claim-based, replaces the old Custom Authentication
    // Extension path). The dateOfBirth claim is emitted by Entra on every
    // access token for users who completed signup with the updated user flow.
    const decision = decideAgeGate(payload as Record<string, unknown>);
    if (decision.action === 'block') {
      trackEvent('age_gate_denied_under_13', { ageBucket: 'under_13' });
      const oid =
        typeof payload.oid === 'string' ? payload.oid : String(externalAuthId);
      // Best-effort Entra account cleanup. We log but don't fail the 403 if
      // this fails — the user still can't use the product.
      const deleted = await deleteEntraUserByOid(oid);
      if (!deleted) trackEvent('age_gate_entra_delete_failed', { oid });
      return errorResponse(
        'AGE_VERIFICATION_FAILED',
        `You must be at least ${MIN_AGE} years old to use Clique Pix.`,
        403,
      );
    }

    // Extract user info from token claims
    const email = payload.preferred_username || payload.email ||
      (Array.isArray(payload.emails) ? payload.emails[0] : '') || '';
    const displayName = payload.name ||
      [payload.given_name, payload.family_name].filter(Boolean).join(' ') ||
      email.split('@')[0] || 'User';

    // Upsert user. age_verified_at is stamped only on the 'pass' branch —
    // 'grandfather' (missing/unparseable DOB claim on pre-existing users)
    // leaves it null, which is fine for existing accounts.
    const ageVerifiedAt = decision.action === 'pass' ? new Date() : null;
    const user = await queryOne<User>(
      `INSERT INTO users (external_auth_id, display_name, email_or_phone, age_verified_at)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (external_auth_id) DO UPDATE SET
         display_name = EXCLUDED.display_name,
         email_or_phone = EXCLUDED.email_or_phone,
         age_verified_at = COALESCE(users.age_verified_at, EXCLUDED.age_verified_at),
         updated_at = NOW()
       RETURNING *`,
      [externalAuthId, displayName, email, ageVerifiedAt],
    );

    if (decision.action === 'pass') {
      trackEvent('age_gate_passed', { ageBucket: ageBucket(decision.age) });
    }
    trackEvent('auth_verify_success');

    return successResponse({
      id: user!.id,
      display_name: user!.display_name,
      email_or_phone: user!.email_or_phone,
      avatar_url: user!.avatar_url,
      created_at: user!.created_at,
    });
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

    return successResponse({
      id: user.id,
      display_name: user.display_name,
      email_or_phone: user.email_or_phone,
      avatar_url: user.avatar_url,
      created_at: user.created_at,
    });
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
      const cliquePhotos = await query<{ blob_path: string; thumbnail_blob_path: string | null }>(
        `SELECT p.blob_path, p.thumbnail_blob_path FROM photos p
         JOIN events e ON e.id = p.event_id
         WHERE e.clique_id = $1`,
        [clique.id],
      );
      for (const photo of cliquePhotos) {
        await deleteBlob(photo.blob_path);
        if (photo.thumbnail_blob_path) await deleteBlob(photo.thumbnail_blob_path);
      }
      await execute('DELETE FROM cliques WHERE id = $1', [clique.id]);
    }

    // 3. Delete remaining photos uploaded by user (in other cliques)
    const userPhotos = await query<{ blob_path: string; thumbnail_blob_path: string | null }>(
      'SELECT blob_path, thumbnail_blob_path FROM photos WHERE uploaded_by_user_id = $1',
      [authUser.id],
    );
    for (const photo of userPhotos) {
      await deleteBlob(photo.blob_path);
      if (photo.thumbnail_blob_path) await deleteBlob(photo.thumbnail_blob_path);
    }
    await execute('DELETE FROM photos WHERE uploaded_by_user_id = $1', [authUser.id]);

    // 4. Delete user record (CASCADE: clique_members, reactions, push_tokens, notifications)
    // (SET NULL via migration 004: cliques.created_by_user_id, events.created_by_user_id)
    await execute('DELETE FROM users WHERE id = $1', [authUser.id]);

    trackEvent('account_deleted', { userId: authUser.id });

    return successResponse({ message: 'Account deleted.' });
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
