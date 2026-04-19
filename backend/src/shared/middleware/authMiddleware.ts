import { HttpRequest } from '@azure/functions';
import * as jwt from 'jsonwebtoken';
import jwksRsa from 'jwks-rsa';
import { execute, queryOne } from '../services/dbService';
import { UnauthorizedError, NotFoundError } from '../utils/errors';
import { User } from '../models/user';

const TENANT_ID = process.env.ENTRA_TENANT_ID || '';
const CLIENT_ID = process.env.ENTRA_CLIENT_ID || '';

if (!TENANT_ID) {
  console.warn('ENTRA_TENANT_ID is not set — authentication will fail');
}
if (!CLIENT_ID) {
  console.warn('ENTRA_CLIENT_ID is not set — authentication will fail');
}

const jwksClient = jwksRsa({
  jwksUri: `https://cliquepix.ciamlogin.com/${TENANT_ID}/discovery/v2.0/keys`,
  cache: true,
  cacheMaxEntries: 5,
  cacheMaxAge: 600000, // 10 minutes
});

async function getSigningKey(kid: string): Promise<string> {
  const key = await jwksClient.getSigningKey(kid);
  return key.getPublicKey();
}

export interface AuthenticatedUser {
  id: string;
  externalAuthId: string;
  displayName: string;
  emailOrPhone: string;
}

export async function authenticateRequest(req: HttpRequest): Promise<AuthenticatedUser> {
  const authHeader = req.headers.get('authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    throw new UnauthorizedError();
  }

  const token = authHeader.slice(7);

  // Decode header to get kid
  const decoded = jwt.decode(token, { complete: true });
  if (!decoded || typeof decoded === 'string') {
    throw new UnauthorizedError();
  }

  const kid = decoded.header.kid;
  if (!kid) {
    throw new UnauthorizedError();
  }

  // Get signing key and verify
  const signingKey = await getSigningKey(kid);

  const payload = jwt.verify(token, signingKey, {
    algorithms: ['RS256'],
    issuer: `https://${TENANT_ID}.ciamlogin.com/${TENANT_ID}/v2.0`,
    audience: CLIENT_ID,
  }) as jwt.JwtPayload;

  const externalAuthId = payload.sub || payload.oid;
  if (!externalAuthId) {
    throw new UnauthorizedError();
  }

  // Look up user in database
  const user = await queryOne<User>(
    'SELECT id, external_auth_id, display_name, email_or_phone FROM users WHERE external_auth_id = $1',
    [externalAuthId],
  );

  if (!user) {
    throw new NotFoundError('user');
  }

  // Fire-and-forget: update users.last_activity_at so the refresh-push timer
  // can detect users approaching the Entra 12h refresh-token cliff. The
  // WHERE predicate caps writes to at most one per minute per user so this
  // adds no measurable load. Never await — must not add latency to callers.
  void execute(
    `UPDATE users SET last_activity_at = NOW()
       WHERE id = $1
         AND (last_activity_at IS NULL OR last_activity_at < NOW() - INTERVAL '1 minute')`,
    [user.id],
  ).catch((err) => {
    console.warn('last_activity_at update failed', (err as Error).message);
  });

  return {
    id: user.id,
    externalAuthId: user.external_auth_id,
    displayName: user.display_name,
    emailOrPhone: user.email_or_phone,
  };
}

// ============================================================================
// JWT signature verification that accepts expired tokens.
// ============================================================================
// Used by the /api/telemetry/auth endpoint, which is the one place we want
// to hear from clients whose access token is specifically expiring/expired.
// The signature check confirms the caller is from our CIAM tenant; the exp
// check is deliberately skipped.
export interface VerifiedTokenPayload {
  userId: string;
  issuer: string;
  audience: string | string[];
  exp?: number;
}

export async function verifyJwtAllowExpired(
  token: string,
): Promise<VerifiedTokenPayload> {
  const decoded = jwt.decode(token, { complete: true });
  if (!decoded || typeof decoded === 'string') {
    throw new UnauthorizedError();
  }
  const kid = decoded.header.kid;
  if (!kid) {
    throw new UnauthorizedError();
  }

  const signingKey = await getSigningKey(kid);
  const payload = jwt.verify(token, signingKey, {
    algorithms: ['RS256'],
    issuer: `https://${TENANT_ID}.ciamlogin.com/${TENANT_ID}/v2.0`,
    audience: CLIENT_ID,
    ignoreExpiration: true,
  }) as jwt.JwtPayload;

  const userId = (payload.sub || payload.oid) as string | undefined;
  if (!userId) {
    throw new UnauthorizedError();
  }

  return {
    userId,
    issuer: payload.iss || '',
    audience: payload.aud || '',
    exp: payload.exp,
  };
}
