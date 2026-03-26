import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import * as jwt from 'jsonwebtoken';
import jwksRsa from 'jwks-rsa';
import { queryOne } from '../shared/services/dbService';
import { handleError } from '../shared/middleware/errorHandler';
import { authenticateRequest } from '../shared/middleware/authMiddleware';
import { successResponse, errorResponse } from '../shared/utils/response';
import { trackEvent } from '../shared/services/telemetryService';
import { User } from '../shared/models/user';

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

    // Upsert user
    const user = await queryOne<User>(
      `INSERT INTO users (external_auth_id, display_name, email_or_phone)
       VALUES ($1, $2, $3)
       ON CONFLICT (external_auth_id) DO UPDATE SET
         display_name = EXCLUDED.display_name,
         email_or_phone = EXCLUDED.email_or_phone,
         updated_at = NOW()
       RETURNING *`,
      [externalAuthId, displayName, email],
    );

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
