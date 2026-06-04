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
 * Maximum number of times one message may be delivered before the runner treats
 * it as poison and discards it. The bare @azure/storage-queue SDK does NOT
 * auto-move messages to a poison queue — that is an Azure Functions trigger
 * binding feature, not a Storage Queue property — so the runner must bound
 * retries itself. Without this, a persistently-failing message (callback always
 * 500s, FFmpeg repeatedly crashes) redelivers forever, respawning a 2-vCPU job
 * replica every poll cycle. `raw.dequeueCount` is 1 on first delivery.
 */
export const MAX_DEQUEUE_COUNT = 5;

/**
 * Dequeue one message from the video-transcode-queue.
 * Returns null if the queue is empty OR if the message was malformed/undecodable
 * (in which case it is deleted here so it cannot redeliver and crash-loop forever).
 *
 * Visibility timeout is set to 15 minutes — long enough for FFmpeg to complete
 * a 5-min source transcode without the message reappearing in the queue.
 * If the runner crashes or exits without deleting, the message reappears after
 * the visibility timeout and a new replica retries it — bounded by
 * MAX_DEQUEUE_COUNT (enforced in the runner).
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
  // A malformed/undecodable message can NEVER be processed — historically the
  // JSON.parse here threw OUTSIDE the runner's try/catch, crashing the process
  // (exit 1) WITHOUT deleting the message, so it redelivered forever. Delete it
  // here instead and return null (treated as "queue empty" by the runner).
  let payload: TranscodeJobMessage;
  try {
    const decoded = Buffer.from(raw.messageText, 'base64').toString('utf-8');
    payload = JSON.parse(decoded) as TranscodeJobMessage;
  } catch (err) {
    console.error(
      `[queueService] Dropping malformed queue message ${raw.messageId} ` +
        `(dequeueCount=${raw.dequeueCount}): ${err instanceof Error ? err.message : String(err)}`,
    );
    await safeDeleteRaw(client, raw);
    return null;
  }

  // Guard the required fields the runner dereferences. A structurally-valid JSON
  // object missing these would otherwise fail downstream and redeliver forever.
  if (
    !payload ||
    typeof payload.videoId !== 'string' ||
    typeof payload.blobPath !== 'string' ||
    typeof payload.eventId !== 'string' ||
    typeof payload.cliqueId !== 'string'
  ) {
    console.error(
      `[queueService] Dropping queue message ${raw.messageId} with missing/invalid ` +
        `fields (dequeueCount=${raw.dequeueCount})`,
    );
    await safeDeleteRaw(client, raw);
    return null;
  }

  return { raw, payload };
}

/** Best-effort delete of a raw message (poison/malformed). Never throws. */
async function safeDeleteRaw(client: QueueClient, raw: DequeuedMessageItem): Promise<void> {
  try {
    await client.deleteMessage(raw.messageId, raw.popReceipt);
  } catch (delErr) {
    console.error('[queueService] Failed to delete poison/malformed message:', delErr);
  }
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
