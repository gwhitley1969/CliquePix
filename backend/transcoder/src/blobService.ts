// Blob storage helpers for the transcoder runner.
//
// Auth: managed identity via DefaultAzureCredential.
// The Container Apps Job's MI has Storage Blob Data Contributor on stcliquepixprod.

import { BlobServiceClient, BlockBlobClient } from '@azure/storage-blob';
import { DefaultAzureCredential } from '@azure/identity';
import * as fs from 'fs';
import * as path from 'path';

const STORAGE_ACCOUNT_NAME = process.env.STORAGE_ACCOUNT_NAME!;
const BLOB_CONTAINER_NAME = process.env.BLOB_CONTAINER_NAME ?? 'photos';

if (!STORAGE_ACCOUNT_NAME) {
  throw new Error('STORAGE_ACCOUNT_NAME env var is required');
}

let cachedServiceClient: BlobServiceClient | null = null;

function getServiceClient(): BlobServiceClient {
  if (!cachedServiceClient) {
    cachedServiceClient = new BlobServiceClient(
      `https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net`,
      new DefaultAzureCredential(),
    );
  }
  return cachedServiceClient;
}

function getBlobClient(blobPath: string): BlockBlobClient {
  return getServiceClient()
    .getContainerClient(BLOB_CONTAINER_NAME)
    .getBlockBlobClient(blobPath);
}

/**
 * Download a blob to a local file path. Used to fetch the original video
 * before transcoding.
 */
export async function downloadBlob(blobPath: string, localPath: string): Promise<void> {
  const blobClient = getBlobClient(blobPath);
  await blobClient.downloadToFile(localPath);
}

/**
 * Upload a single local file to a blob path with the given content-type.
 * Used for the MP4 fallback and poster.
 */
export async function uploadBlob(
  localPath: string,
  blobPath: string,
  contentType: string,
): Promise<void> {
  const blobClient = getBlobClient(blobPath);
  await blobClient.uploadFile(localPath, {
    blobHTTPHeaders: {
      blobContentType: contentType,
    },
  });
}

/**
 * Upload all files in a local directory to a blob prefix, recursively.
 * Used for HLS output (manifest + segments).
 *
 * Content type is inferred from extension:
 *   .m3u8 → application/vnd.apple.mpegurl
 *   .ts   → video/mp2t
 *   .m4s  → video/iso.segment
 *   other → application/octet-stream
 */
export async function uploadDirectory(localDir: string, blobPrefix: string): Promise<void> {
  const entries = await fs.promises.readdir(localDir, { withFileTypes: true });
  for (const entry of entries) {
    const localPath = path.join(localDir, entry.name);
    const blobPath = `${blobPrefix}/${entry.name}`;
    if (entry.isDirectory()) {
      await uploadDirectory(localPath, blobPath);
    } else {
      const ext = path.extname(entry.name).toLowerCase();
      const contentType = inferContentType(ext);
      await uploadBlob(localPath, blobPath, contentType);
    }
  }
}

function inferContentType(ext: string): string {
  switch (ext) {
    case '.m3u8':
      return 'application/vnd.apple.mpegurl';
    case '.ts':
      return 'video/mp2t';
    case '.m4s':
      return 'video/iso.segment';
    case '.mp4':
      return 'video/mp4';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    default:
      return 'application/octet-stream';
  }
}

/**
 * Set the access tier of a blob. Used to put the original video master
 * on Cool tier per Decision 7.
 */
export async function setBlobTier(
  blobPath: string,
  tier: 'Hot' | 'Cool' | 'Archive',
): Promise<void> {
  const blobClient = getBlobClient(blobPath);
  await blobClient.setAccessTier(tier);
}

/**
 * Delete all blobs under a given prefix. Used by the runner only in the
 * case of a callback discard (when the photos row was already deleted
 * before the transcode completed).
 *
 * Note: this is a one-by-one delete loop. The Function-side cleanup uses
 * a different prefix-delete helper for the timer-driven expiration path.
 */
export async function deleteBlobsByPrefix(prefix: string): Promise<number> {
  const containerClient = getServiceClient().getContainerClient(BLOB_CONTAINER_NAME);
  let count = 0;
  for await (const blob of containerClient.listBlobsFlat({ prefix })) {
    await containerClient.deleteBlob(blob.name);
    count++;
  }
  return count;
}
