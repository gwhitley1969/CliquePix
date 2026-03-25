import { HttpRequest } from '@azure/functions';
import * as jwt from 'jsonwebtoken';
import jwksRsa from 'jwks-rsa';
import { queryOne } from '../services/dbService';
import { UnauthorizedError, NotFoundError } from '../utils/errors';
import { User } from '../models/user';

const TENANT_ID = process.env.ENTRA_TENANT_ID || '';
const CLIENT_ID = process.env.ENTRA_CLIENT_ID || '';

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
    issuer: `https://cliquepix.ciamlogin.com/${TENANT_ID}/v2.0`,
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

  return {
    id: user.id,
    externalAuthId: user.external_auth_id,
    displayName: user.display_name,
    emailOrPhone: user.email_or_phone,
  };
}
