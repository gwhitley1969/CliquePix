import {
  BlobSASPermissions,
  generateBlobSASQueryParameters,
  SASProtocol,
  UserDelegationKey,
} from '@azure/storage-blob';
import { getBlobServiceClient } from './blobService';

const CONTAINER_NAME = 'photos';
let cachedDelegationKey: UserDelegationKey | null = null;
let delegationKeyExpiry: Date | null = null;

async function getUserDelegationKey(): Promise<UserDelegationKey> {
  const now = new Date();
  if (cachedDelegationKey && delegationKeyExpiry && delegationKeyExpiry > now) {
    return cachedDelegationKey;
  }

  const startsOn = new Date(now.getTime() - 5 * 60 * 1000); // 5 min in the past
  const expiresOn = new Date(now.getTime() + 60 * 60 * 1000); // 1 hour from now

  const client = getBlobServiceClient();
  cachedDelegationKey = await client.getUserDelegationKey(startsOn, expiresOn);
  delegationKeyExpiry = expiresOn;

  return cachedDelegationKey;
}

/**
 * Generate a write-only User Delegation SAS for uploading to a blob path.
 *
 * @param blobPath - blob path inside the photos container
 * @param expirySeconds - SAS validity duration in seconds (default: 5 min for photos).
 *                        Use 30 * 60 (1800) for video block uploads — videos take longer.
 */
export async function generateUploadSas(
  blobPath: string,
  expirySeconds: number = 5 * 60,
): Promise<string> {
  const delegationKey = await getUserDelegationKey();
  const accountName = process.env.STORAGE_ACCOUNT_NAME!;

  const permissions = new BlobSASPermissions();
  permissions.write = true;

  const now = new Date();
  const expiresOn = new Date(now.getTime() + expirySeconds * 1000);

  const sasParams = generateBlobSASQueryParameters(
    {
      containerName: CONTAINER_NAME,
      blobName: blobPath,
      permissions,
      startsOn: new Date(now.getTime() - 60 * 1000),
      expiresOn,
      protocol: SASProtocol.Https,
    },
    delegationKey,
    accountName,
  );

  return `https://${accountName}.blob.core.windows.net/${CONTAINER_NAME}/${blobPath}?${sasParams.toString()}`;
}

/**
 * Generate a read-only User Delegation SAS for viewing/downloading a blob.
 *
 * @param blobPath - blob path inside the photos container
 * @param expirySeconds - SAS validity duration in seconds (default: 5 min for photos).
 *                        Use 15 * 60 (900) for HLS segments and video posters/fallbacks
 *                        — playback sessions can last several minutes.
 */
export async function generateViewSas(
  blobPath: string,
  expirySeconds: number = 5 * 60,
): Promise<string> {
  const delegationKey = await getUserDelegationKey();
  const accountName = process.env.STORAGE_ACCOUNT_NAME!;

  const permissions = new BlobSASPermissions();
  permissions.read = true;

  const now = new Date();
  const expiresOn = new Date(now.getTime() + expirySeconds * 1000);

  const sasParams = generateBlobSASQueryParameters(
    {
      containerName: CONTAINER_NAME,
      blobName: blobPath,
      permissions,
      startsOn: new Date(now.getTime() - 60 * 1000),
      expiresOn,
      protocol: SASProtocol.Https,
    },
    delegationKey,
    accountName,
  );

  return `https://${accountName}.blob.core.windows.net/${CONTAINER_NAME}/${blobPath}?${sasParams.toString()}`;
}
