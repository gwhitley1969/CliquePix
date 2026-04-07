// Internal auth middleware for service-to-service callbacks.
//
// Used by /api/internal/video-processing-complete to verify that the caller
// is the Container Apps Job's managed identity (and not an arbitrary external
// caller spoofing the endpoint).
//
// Verification:
//   1. Token is a valid JWT signed by Azure AD (signature check via JWKS)
//   2. Token's `aud` claim matches FUNCTION_APP_AUDIENCE
//   3. Token's `oid` (object ID) claim matches TRANSCODER_MI_PRINCIPAL_ID
//
// The transcoder acquires this token via DefaultAzureCredential().getToken(),
// passing the Function App audience as the scope.

import { HttpRequest } from '@azure/functions';
import * as jwt from 'jsonwebtoken';
import jwksRsa from 'jwks-rsa';
import { UnauthorizedError, ForbiddenError } from '../utils/errors';

const TRANSCODER_MI_PRINCIPAL_ID = process.env.TRANSCODER_MI_PRINCIPAL_ID || '';
const FUNCTION_APP_AUDIENCE = process.env.FUNCTION_APP_AUDIENCE || '';

if (!TRANSCODER_MI_PRINCIPAL_ID) {
  console.warn('TRANSCODER_MI_PRINCIPAL_ID is not set — internal callback auth will fail');
}
if (!FUNCTION_APP_AUDIENCE) {
  console.warn('FUNCTION_APP_AUDIENCE is not set — internal callback auth will fail');
}

// JWKS for Azure AD common endpoint (managed identity tokens are signed
// here regardless of which tenant the MI lives in).
const jwksClient = jwksRsa({
  jwksUri: 'https://login.microsoftonline.com/common/discovery/v2.0/keys',
  cache: true,
  cacheMaxEntries: 5,
  cacheMaxAge: 600000, // 10 minutes
});

async function getSigningKey(kid: string): Promise<string> {
  const key = await jwksClient.getSigningKey(kid);
  return key.getPublicKey();
}

/**
 * Validate that the request bears a valid managed identity token from
 * the transcoder Container Apps Job. Throws if the token is missing,
 * invalid, expired, or belongs to the wrong principal.
 */
export async function validateInternalCallerIdentity(req: HttpRequest): Promise<void> {
  const authHeader = req.headers.get('authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    throw new UnauthorizedError('Missing bearer token');
  }
  const token = authHeader.slice(7);

  // Decode the token header to get the key ID
  const decoded = jwt.decode(token, { complete: true });
  if (!decoded || typeof decoded === 'string' || !decoded.header.kid) {
    throw new UnauthorizedError('Invalid token format');
  }

  // Fetch the signing key from Azure AD JWKS
  let signingKey: string;
  try {
    signingKey = await getSigningKey(decoded.header.kid);
  } catch (err) {
    throw new UnauthorizedError('Failed to fetch signing key');
  }

  // Verify signature, audience, and expiry
  let payload: jwt.JwtPayload;
  try {
    payload = jwt.verify(token, signingKey, {
      audience: FUNCTION_APP_AUDIENCE,
      algorithms: ['RS256'],
    }) as jwt.JwtPayload;
  } catch (err) {
    throw new UnauthorizedError(`Token verification failed: ${err instanceof Error ? err.message : String(err)}`);
  }

  // Check the object ID (oid) claim matches the transcoder's MI principal
  const callerOid = payload.oid as string | undefined;
  if (!callerOid) {
    throw new UnauthorizedError('Token missing oid claim');
  }
  if (callerOid !== TRANSCODER_MI_PRINCIPAL_ID) {
    throw new ForbiddenError(
      `Caller identity ${callerOid} is not authorized to call this endpoint`,
    );
  }
}
