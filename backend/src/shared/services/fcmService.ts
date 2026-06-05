import { google } from 'googleapis';

let accessToken: string | null = null;
let tokenExpiry: number = 0;

interface FcmCredentials {
  client_email: string;
  private_key: string;
  project_id: string;
}

function getCredentials(): FcmCredentials {
  const raw = process.env.FCM_CREDENTIALS;
  if (!raw) {
    throw new Error('FCM_CREDENTIALS is not configured');
  }
  return JSON.parse(raw) as FcmCredentials;
}

async function getAccessToken(): Promise<string> {
  if (accessToken && Date.now() < tokenExpiry) {
    return accessToken;
  }

  const credentials = getCredentials();
  const jwtClient = new google.auth.JWT(
    credentials.client_email,
    undefined,
    credentials.private_key,
    ['https://www.googleapis.com/auth/firebase.messaging'],
  );

  const tokens = await jwtClient.authorize();
  accessToken = tokens.access_token!;
  tokenExpiry = (tokens.expiry_date ?? Date.now() + 3500 * 1000);

  return accessToken;
}

export interface FcmMessage {
  token: string;
  title?: string;
  body?: string;
  data?: Record<string, string>;
  /**
   * When true, sends a silent / background push. The `notification` block
   * is omitted entirely and platform-specific flags are set so iOS and
   * Android wake the app in the background without displaying anything:
   *  - iOS: apns-push-type: background, apns-priority: 5, content-available: 1
   *  - Android: priority: high (required for data-only delivery)
   * Requires a non-empty `data` field (silent pushes without data have no
   * purpose). title/body are ignored.
   */
  silent?: boolean;
}

const APNS_TOPIC = process.env.APNS_TOPIC || 'com.cliquepix.app';

/**
 * Build the FCM v1 message body for either a visible or a silent push.
 * Exported for unit testing.
 */
export function buildFcmMessageBody(message: FcmMessage): Record<string, unknown> {
  if (message.silent) {
    return {
      message: {
        token: message.token,
        data: message.data,
        android: { priority: 'high' },
        apns: {
          headers: {
            'apns-push-type': 'background',
            'apns-priority': '5',
            'apns-topic': APNS_TOPIC,
          },
          payload: { aps: { 'content-available': 1 } },
        },
      },
    };
  }

  return {
    message: {
      token: message.token,
      notification: {
        title: message.title,
        body: message.body,
      },
      data: message.data,
    },
  };
}

export type FcmSendResult =
  | { ok: true }
  | { ok: false; permanent: boolean };

/**
 * FCM HTTP v1 marks a token PERMANENTLY invalid via:
 *   - HTTP 404 with error.status === 'NOT_FOUND' / details errorCode 'UNREGISTERED'
 *     (app uninstalled or token rotated away)
 *   - HTTP 400 with error.status === 'INVALID_ARGUMENT' / details errorCode
 *     'INVALID_ARGUMENT' (malformed / non-existent token)
 * Everything else — 401/403 (our OAuth credential), 429 (throttle), 5xx,
 * timeout, network — is TRANSIENT and the token MUST be kept. Treating a
 * transient failure as a dead token used to DELETE valid registrations, so an
 * FCM outage silently de-registered the whole device fleet (and broke the
 * Layer-2 silent-push refresh defense).
 *
 * NOTE: FCM's 400 INVALID_ARGUMENT is overloaded — it can mean a bad TOKEN or a
 * malformed MESSAGE. We send a structurally-fixed payload (buildFcmMessageBody),
 * so in practice a 400 here means the token; but a future change that ships a
 * malformed message field would 400 EVERY token and purge the whole fleet. Keep
 * the payload shape stable. Exported for unit testing.
 */
export function isPermanentTokenError(status: number, errorBody: string): boolean {
  if (status !== 400 && status !== 404) return false;
  try {
    const parsed = JSON.parse(errorBody) as {
      error?: { status?: string; details?: Array<{ '@type'?: string; errorCode?: string }> };
    };
    const errStatus = parsed.error?.status;
    const fcmCode = parsed.error?.details?.find((d) => d['@type']?.includes('fcm.v1.FcmError'))
      ?.errorCode;
    if (status === 404) return errStatus === 'NOT_FOUND' || fcmCode === 'UNREGISTERED';
    return errStatus === 'INVALID_ARGUMENT' || fcmCode === 'INVALID_ARGUMENT';
  } catch {
    return false; // unparseable body on a 400/404 (e.g. gateway HTML) — treat as transient
  }
}

export async function sendPushNotification(message: FcmMessage): Promise<FcmSendResult> {
  try {
    const credentials = getCredentials();
    const token = await getAccessToken();

    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(buildFcmMessageBody(message)),
      },
    );

    if (!response.ok) {
      const errorBody = await response.text();
      console.error('FCM send failed:', response.status, errorBody);
      return { ok: false, permanent: isPermanentTokenError(response.status, errorBody) };
    }

    return { ok: true };
  } catch (error) {
    // network / timeout / credential acquisition failure — all transient.
    console.error('FCM send error:', error);
    return { ok: false, permanent: false };
  }
}

export interface MultiSendResult {
  /** Tokens FCM reports as permanently invalid (uninstalled / malformed) — safe to DELETE. */
  permanentlyInvalid: string[];
  /** Count of ALL tokens that failed delivery (permanent + transient) — telemetry only. */
  totalFailed: number;
}

export async function sendToMultipleTokens(
  tokens: string[],
  title: string,
  body: string,
  data?: Record<string, string>,
): Promise<MultiSendResult> {
  const permanentlyInvalid: string[] = [];
  let totalFailed = 0;

  await Promise.all(
    tokens.map(async (token) => {
      const result = await sendPushNotification({ token, title, body, data });
      if (!result.ok) {
        totalFailed++;
        if (result.permanent) permanentlyInvalid.push(token);
      }
    }),
  );

  return { permanentlyInvalid, totalFailed };
}

/**
 * Silent (background) push to multiple device tokens. Used by the
 * refresh-push timer to wake inactive users before the Entra 12h
 * refresh-token inactivity timeout. No visible UI is shown on either
 * platform. Returns only the permanently-invalid tokens (for purge) plus a
 * total-failed count (for telemetry) — a transient FCM blip must NOT delete a
 * valid token and break the Layer-2 refresh defense.
 */
export async function sendSilentToMultipleTokens(
  tokens: string[],
  data: Record<string, string>,
): Promise<MultiSendResult> {
  const permanentlyInvalid: string[] = [];
  let totalFailed = 0;

  await Promise.all(
    tokens.map(async (token) => {
      const result = await sendPushNotification({ token, data, silent: true });
      if (!result.ok) {
        totalFailed++;
        if (result.permanent) permanentlyInvalid.push(token);
      }
    }),
  );

  return { permanentlyInvalid, totalFailed };
}
