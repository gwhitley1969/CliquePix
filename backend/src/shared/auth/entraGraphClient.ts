import { DefaultAzureCredential } from '@azure/identity';

/**
 * Thin Microsoft Graph client for operations the backend occasionally needs.
 * Uses the Function App's system-assigned managed identity to obtain a Graph
 * token via `DefaultAzureCredential`. Requires the `User.ReadWrite.All`
 * application permission granted + admin-consented on the Graph service
 * principal for the tenant.
 *
 * Only one operation today: delete an Entra user by objectId. Used by the
 * age-gate branch in `authVerify` to clean up orphan under-13 accounts.
 */

const credential = new DefaultAzureCredential();

async function getGraphToken(): Promise<string> {
  const tokenResponse = await credential.getToken(
    'https://graph.microsoft.com/.default',
  );
  if (!tokenResponse?.token) {
    throw new Error('Failed to acquire Microsoft Graph token');
  }
  return tokenResponse.token;
}

/**
 * Delete an Entra user by objectId. Returns true on success, false on any
 * failure (caller logs + continues — we never fail user-facing requests
 * because the cleanup failed).
 */
export async function deleteEntraUserByOid(oid: string): Promise<boolean> {
  try {
    const token = await getGraphToken();
    const res = await fetch(
      `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(oid)}`,
      {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${token}` },
      },
    );
    // 204 No Content = success. 404 is acceptable (already gone).
    return res.status === 204 || res.status === 404;
  } catch {
    return false;
  }
}
