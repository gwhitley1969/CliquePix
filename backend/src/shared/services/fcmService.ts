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

export async function sendPushNotification(message: FcmMessage): Promise<boolean> {
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
      return false;
    }

    return true;
  } catch (error) {
    console.error('FCM send error:', error);
    return false;
  }
}

export async function sendToMultipleTokens(
  tokens: string[],
  title: string,
  body: string,
  data?: Record<string, string>,
): Promise<string[]> {
  const failedTokens: string[] = [];

  await Promise.all(
    tokens.map(async (token) => {
      const success = await sendPushNotification({ token, title, body, data });
      if (!success) {
        failedTokens.push(token);
      }
    }),
  );

  return failedTokens;
}

/**
 * Silent (background) push to multiple device tokens. Used by the
 * refresh-push timer to wake inactive users before the Entra 12h
 * refresh-token inactivity timeout. No visible UI is shown on either
 * platform. Returns the list of tokens that failed delivery.
 */
export async function sendSilentToMultipleTokens(
  tokens: string[],
  data: Record<string, string>,
): Promise<string[]> {
  const failedTokens: string[] = [];

  await Promise.all(
    tokens.map(async (token) => {
      const success = await sendPushNotification({ token, data, silent: true });
      if (!success) {
        failedTokens.push(token);
      }
    }),
  );

  return failedTokens;
}
