import { BlobServiceClient, ContainerClient } from '@azure/storage-blob';
import { DefaultAzureCredential } from '@azure/identity';
import * as path from 'path';

let blobServiceClient: BlobServiceClient | null = null;
let containerClient: ContainerClient | null = null;

const CONTAINER_NAME = 'photos';

function getBlobServiceClient(): BlobServiceClient {
  if (!blobServiceClient) {
    const accountName = process.env.STORAGE_ACCOUNT_NAME;
    if (!accountName) {
      throw new Error('STORAGE_ACCOUNT_NAME is not configured');
    }
    const credential = new DefaultAzureCredential();
    blobServiceClient = new BlobServiceClient(
      `https://${accountName}.blob.core.windows.net`,
      credential,
    );
  }
  return blobServiceClient;
}

function getContainerClient(): ContainerClient {
  if (!containerClient) {
    containerClient = getBlobServiceClient().getContainerClient(CONTAINER_NAME);
  }
  return containerClient;
}

export async function blobExists(blobPath: string): Promise<boolean> {
  const blockBlobClient = getContainerClient().getBlockBlobClient(blobPath);
  return blockBlobClient.exists();
}

export async function getBlobProperties(blobPath: string) {
  const blockBlobClient = getContainerClient().getBlockBlobClient(blobPath);
  return blockBlobClient.getProperties();
}

export async function downloadBlob(blobPath: string): Promise<Buffer> {
  const blockBlobClient = getContainerClient().getBlockBlobClient(blobPath);
  return blockBlobClient.downloadToBuffer();
}

export async function uploadBlob(blobPath: string, buffer: Buffer, contentType: string): Promise<void> {
  const blockBlobClient = getContainerClient().getBlockBlobClient(blobPath);
  await blockBlobClient.upload(buffer, buffer.length, {
    blobHTTPHeaders: { blobContentType: contentType },
  });
}

export async function deleteBlob(blobPath: string): Promise<void> {
  const blockBlobClient = getContainerClient().getBlockBlobClient(blobPath);
  await blockBlobClient.deleteIfExists();
}

/**
 * Commit a list of previously-uploaded blocks into a single blob via Put Block List.
 * Used by the video upload-confirm endpoint after the client has uploaded all blocks
 * via SAS URLs to assemble the final blob.
 *
 * Block IDs must be base64-encoded fixed-length strings (Azure requirement).
 * The order of the blockIds array determines the order of bytes in the assembled blob.
 *
 * @param blobPath - destination blob path inside the photos container
 * @param blockIds - ordered list of base64-encoded block IDs to commit
 * @param contentType - MIME type to set on the assembled blob (e.g., 'video/mp4')
 */
export async function commitBlockList(
  blobPath: string,
  blockIds: string[],
  contentType: string,
): Promise<void> {
  const blockBlobClient = getContainerClient().getBlockBlobClient(blobPath);
  await blockBlobClient.commitBlockList(blockIds, {
    blobHTTPHeaders: { blobContentType: contentType },
  });
}

/**
 * Delete all blobs whose names start with the given prefix.
 * Used for video expiration cleanup (HLS segment dirs contain many files).
 *
 * Note: this is a serial delete loop. For very large prefixes (>100 blobs)
 * consider batching via BlobBatchClient if performance becomes an issue.
 *
 * @param prefix - blob path prefix (e.g., 'photos/{cliqueId}/{eventId}/{videoId}/')
 * @returns the number of blobs deleted
 */
export async function deleteBlobsByPrefix(prefix: string): Promise<number> {
  const containerClient = getContainerClient();
  let count = 0;
  for await (const blob of containerClient.listBlobsFlat({ prefix })) {
    try {
      await containerClient.deleteBlob(blob.name);
      count++;
    } catch (_) {
      // Best-effort: continue if individual deletes fail (e.g., already gone)
    }
  }
  return count;
}

/**
 * Delete all blobs belonging to a single media row (photo OR video), given its
 * row. Photos store original.jpg + thumb.jpg under
 * `photos/{cliqueId}/{eventId}/{mediaId}/`; videos store original.mp4 + the
 * whole `hls/` dir + fallback.mp4 + poster.jpg under the same per-media dir.
 *
 * For videos we prefix-delete that directory so HLS segments + fallback +
 * poster are removed — NOT just `blob_path`. Several destructive paths
 * (deleteEvent, deleteMe, the expiry safety-net) historically deleted only
 * `blob_path` + `thumbnail_blob_path`, orphaning video HLS/fallback/poster
 * blobs in storage forever (cost + the product's "everything disappears"
 * promise). This helper is the single correct cleanup for both media types.
 *
 * Best-effort: individual blob delete failures are swallowed by the underlying
 * helpers, so a missing blob does not throw.
 */
export async function deleteMediaAssets(media: {
  blob_path: string;
  thumbnail_blob_path?: string | null;
  media_type?: string | null;
}): Promise<void> {
  if (media.media_type === 'video') {
    // The per-video directory is the parent of original.mp4. Trailing slash
    // guarantees `{videoId}/` cannot match a sibling `{videoId}X/` prefix.
    const dirPrefix = path.posix.dirname(media.blob_path) + '/';
    await deleteBlobsByPrefix(dirPrefix);
    return;
  }
  // Photo (or unknown/legacy): delete original + thumbnail explicitly to
  // preserve the exact pre-existing behavior for photo rows.
  await deleteBlob(media.blob_path);
  if (media.thumbnail_blob_path) {
    await deleteBlob(media.thumbnail_blob_path);
  }
}

/**
 * Set the access tier of a blob (Hot, Cool, or Archive).
 * Used to move video originals to Cool tier per Decision 7.
 */
export async function setBlobAccessTier(
  blobPath: string,
  tier: 'Hot' | 'Cool' | 'Archive',
): Promise<void> {
  const blockBlobClient = getContainerClient().getBlockBlobClient(blobPath);
  await blockBlobClient.setAccessTier(tier);
}

export { getBlobServiceClient };
