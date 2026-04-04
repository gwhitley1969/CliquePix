import { WebPubSubServiceClient } from '@azure/web-pubsub';

const HUB_NAME = 'cliquepix';
let client: WebPubSubServiceClient | null = null;

function getClient(): WebPubSubServiceClient {
  if (!client) {
    const connStr = process.env.WEB_PUBSUB_CONNECTION_STRING;
    if (!connStr) {
      throw new Error('WEB_PUBSUB_CONNECTION_STRING is not configured');
    }
    client = new WebPubSubServiceClient(connStr, HUB_NAME);
  }
  return client;
}

export async function getClientAccessToken(userId: string): Promise<{ url: string }> {
  return getClient().getClientAccessToken({ userId });
}

export async function sendToUser(userId: string, payload: Record<string, unknown>): Promise<void> {
  await getClient().sendToUser(userId, payload);
}

export async function publishToThread(threadId: string, payload: Record<string, unknown>): Promise<void> {
  await getClient().group(`dm-thread-${threadId}`).sendToAll(payload);
}

export async function addUserToThreadGroup(threadId: string, userId: string): Promise<void> {
  await getClient().group(`dm-thread-${threadId}`).addUser(userId);
}

export async function removeUserFromThreadGroup(threadId: string, userId: string): Promise<void> {
  await getClient().group(`dm-thread-${threadId}`).removeUser(userId);
}
