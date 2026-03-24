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
  title: string;
  body: string;
  data?: Record<string, string>;
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
        body: JSON.stringify({
          message: {
            token: message.token,
            notification: {
              title: message.title,
              body: message.body,
            },
            data: message.data,
          },
        }),
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
