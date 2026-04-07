// Storage Queue dequeue helper for the transcoder runner.
// One container execution = one message dequeued + processed + deleted.
//
// Auth: managed identity via DefaultAzureCredential.
// The Container Apps Job's MI has these roles on stcliquepixprod:
//   - Storage Queue Data Message Processor (peek/get/delete messages)
//   - Storage Queue Data Reader (KEDA scaler queue length polling)

import { QueueClient, DequeuedMessageItem } from '@azure/storage-queue';
import { DefaultAzureCredential } from '@azure/identity';
import type { TranscodeJobMessage } from './types';

const STORAGE_ACCOUNT_NAME = process.env.STORAGE_ACCOUNT_NAME!;
const STORAGE_QUEUE_NAME = process.env.STORAGE_QUEUE_NAME ?? 'video-transcode-queue';

if (!STORAGE_ACCOUNT_NAME) {
  throw new Error('STORAGE_ACCOUNT_NAME env var is required');
}

let cachedClient: QueueClient | null = null;

function getClient(): QueueClient {
  if (!cachedClient) {
    cachedClient = new QueueClient(
      `https://${STORAGE_ACCOUNT_NAME}.queue.core.windows.net/${STORAGE_QUEUE_NAME}`,
      new DefaultAzureCredential(),
    );
  }
  return cachedClient;
}

export interface DequeuedTranscodeJob {
  raw: DequeuedMessageItem;
  payload: TranscodeJobMessage;
}

/**
 * Dequeue one message from the video-transcode-queue.
 * Returns null if the queue is empty.
 *
 * Visibility timeout is set to 15 minutes — long enough for FFmpeg to complete
 * a 5-min source transcode without the message reappearing in the queue.
 * If the runner crashes or exits without deleting, the message reappears
 * after the visibility timeout and is picked up by a new replica.
 */
export async function dequeueMessage(): Promise<DequeuedTranscodeJob | null> {
  const client = getClient();
  const response = await client.receiveMessages({
    numberOfMessages: 1,
    visibilityTimeout: 15 * 60, // 15 min — matches Container Apps Job replica-timeout
  });

  if (response.receivedMessageItems.length === 0) {
    return null;
  }

  const raw = response.receivedMessageItems[0];

  // Storage queue messages are base64-encoded by convention. The producer
  // (Function App) base64-encodes the JSON before sending; we decode here.
  const decoded = Buffer.from(raw.messageText, 'base64').toString('utf-8');
  const payload = JSON.parse(decoded) as TranscodeJobMessage;

  return { raw, payload };
}

/**
 * Delete a successfully-processed message from the queue.
 * Must be called after the callback POST succeeds, NOT before — otherwise
 * a callback failure leaves the row stuck in 'processing' with no retry.
 */
export async function deleteMessage(message: DequeuedTranscodeJob): Promise<void> {
  const client = getClient();
  await client.deleteMessage(message.raw.messageId, message.raw.popReceipt);
}
