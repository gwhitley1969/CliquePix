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

export async function generateUploadSas(blobPath: string): Promise<string> {
  const delegationKey = await getUserDelegationKey();
  const accountName = process.env.STORAGE_ACCOUNT_NAME!;

  const permissions = new BlobSASPermissions();
  permissions.write = true;
  permissions.create = true;

  const now = new Date();
  const expiresOn = new Date(now.getTime() + 5 * 60 * 1000); // 5 minutes

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

export async function generateViewSas(blobPath: string): Promise<string> {
  const delegationKey = await getUserDelegationKey();
  const accountName = process.env.STORAGE_ACCOUNT_NAME!;

  const permissions = new BlobSASPermissions();
  permissions.read = true;

  const now = new Date();
  const expiresOn = new Date(now.getTime() + 15 * 60 * 1000); // 15 minutes

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
