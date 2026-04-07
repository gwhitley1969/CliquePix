import { BlobServiceClient, ContainerClient } from '@azure/storage-blob';
import { DefaultAzureCredential } from '@azure/identity';

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
