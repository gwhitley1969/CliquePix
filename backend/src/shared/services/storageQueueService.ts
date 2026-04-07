// Storage Queue dispatch helper for the video transcoder pipeline.
//
// Function App writes one message per video upload commit; the Container Apps
// Job's KEDA Azure Storage Queue scaler reads the queue depth and triggers
// transcoder replicas accordingly.
//
// Auth: managed identity via DefaultAzureCredential.
// The Function App's MI has the `Storage Queue Data Contributor` role on
// stcliquepixprod (added in Phase 2).

import { QueueClient } from '@azure/storage-queue';
import { DefaultAzureCredential } from '@azure/identity';

const STORAGE_ACCOUNT_NAME = process.env.STORAGE_ACCOUNT_NAME;
const STORAGE_QUEUE_NAME = process.env.STORAGE_QUEUE_NAME ?? 'video-transcode-queue';

let cachedClient: QueueClient | null = null;

function getClient(): QueueClient {
  if (!cachedClient) {
    if (!STORAGE_ACCOUNT_NAME) {
      throw new Error('STORAGE_ACCOUNT_NAME env var is required');
    }
    cachedClient = new QueueClient(
      `https://${STORAGE_ACCOUNT_NAME}.queue.core.windows.net/${STORAGE_QUEUE_NAME}`,
      new DefaultAzureCredential(),
    );
  }
  return cachedClient;
}

/**
 * Message format for the video transcode queue.
 * Producer: this Function App's video commit endpoint.
 * Consumer: the Container Apps Job runner (backend/transcoder/src/runner.ts).
 *
 * Field names use camelCase to match the runner's TypeScript types.
 */
export interface TranscodeJobMessage {
  videoId: string;
  blobPath: string;
  eventId: string;
  cliqueId: string;
}

/**
 * Enqueue a video transcoding job. Returns once the message is durably
 * accepted by Azure Storage Queue.
 *
 * The message body is JSON-serialized then base64-encoded (Azure Storage
 * Queue convention — the SDK does NOT encode automatically).
 */
export async function enqueueTranscodeJob(message: TranscodeJobMessage): Promise<void> {
  const client = getClient();
  const json = JSON.stringify(message);
  const base64 = Buffer.from(json, 'utf-8').toString('base64');
  await client.sendMessage(base64);
}
