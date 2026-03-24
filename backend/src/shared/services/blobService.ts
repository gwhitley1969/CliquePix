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

export { getBlobServiceClient };
