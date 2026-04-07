// HTTP callback to the Function App's /api/internal/video-processing-complete endpoint.
//
// Auth: Azure Functions function key, passed as ?code=<key> query parameter.
// The Function endpoint is configured with `authLevel: 'function'` so the
// runtime validates the key automatically before invoking the handler.
//
// The function key is sourced from FUNCTION_CALLBACK_KEY env var, which on
// Container Apps Job points at a secretref backed by Key Vault.

import type { CallbackPayload } from './types';

const CALLBACK_URL = process.env.FUNCTION_CALLBACK_URL!;
const FUNCTION_CALLBACK_KEY = process.env.FUNCTION_CALLBACK_KEY!;

if (!CALLBACK_URL) {
  throw new Error('FUNCTION_CALLBACK_URL env var is required');
}
if (!FUNCTION_CALLBACK_KEY) {
  throw new Error('FUNCTION_CALLBACK_KEY env var is required');
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
  const body = JSON.stringify(payload);

  // Append the function key as a query parameter
  const separator = CALLBACK_URL.includes('?') ? '&' : '?';
  const urlWithKey = `${CALLBACK_URL}${separator}code=${encodeURIComponent(FUNCTION_CALLBACK_KEY)}`;

  let lastError: Error | null = null;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const response = await fetch(urlWithKey, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
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
