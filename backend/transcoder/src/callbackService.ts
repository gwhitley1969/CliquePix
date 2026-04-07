// HTTP callback to the Function App's /api/internal/video-processing-complete endpoint.
//
// Auth: managed identity. The transcoder acquires a token for the Function App's
// audience (`api://func-cliquepix-fresh`) and presents it as a Bearer token.
// The Function validates the token's signature and `oid` claim against the
// transcoder's principal ID (set as TRANSCODER_MI_PRINCIPAL_ID env var on the Function).

import { DefaultAzureCredential } from '@azure/identity';
import type { CallbackPayload } from './types';

const CALLBACK_URL = process.env.FUNCTION_CALLBACK_URL!;
const FUNCTION_AUDIENCE = process.env.FUNCTION_APP_AUDIENCE!;

if (!CALLBACK_URL) {
  throw new Error('FUNCTION_CALLBACK_URL env var is required');
}
if (!FUNCTION_AUDIENCE) {
  throw new Error('FUNCTION_APP_AUDIENCE env var is required');
}

let cachedCredential: DefaultAzureCredential | null = null;

function getCredential(): DefaultAzureCredential {
  if (!cachedCredential) {
    cachedCredential = new DefaultAzureCredential();
  }
  return cachedCredential;
}

async function getAccessToken(): Promise<string> {
  const credential = getCredential();
  const tokenResponse = await credential.getToken(`${FUNCTION_AUDIENCE}/.default`);
  if (!tokenResponse) {
    throw new Error('Failed to acquire access token for Function App callback');
  }
  return tokenResponse.token;
}

/**
 * POST a callback payload to the Function App with retry on failure.
 *
 * Retries: 3 attempts, exponential backoff (1s, 2s, 4s).
 * If all retries fail, the error is thrown — the runner does NOT delete
 * the queue message in that case, so it gets re-tried (which is wasteful
 * but correct). After 5 dequeues without deletion, Storage Queue moves
 * the message to the poison queue and a separate timer Function cleans up.
 */
export async function postCallback(payload: CallbackPayload): Promise<void> {
  const token = await getAccessToken();
  const body = JSON.stringify(payload);

  let lastError: Error | null = null;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const response = await fetch(CALLBACK_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body,
      });

      if (response.ok) {
        console.log(`Callback POST succeeded on attempt ${attempt}`);
        return;
      }

      const text = await response.text();
      lastError = new Error(`Callback POST failed: ${response.status} ${response.statusText} — ${text}`);
      console.error(`Attempt ${attempt}/3 failed:`, lastError.message);
    } catch (err) {
      lastError = err instanceof Error ? err : new Error(String(err));
      console.error(`Attempt ${attempt}/3 threw:`, lastError.message);
    }

    if (attempt < 3) {
      const delayMs = 1000 * Math.pow(2, attempt - 1);
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }

  throw lastError ?? new Error('Callback POST failed after 3 attempts');
}
