import { useMsal } from '@azure/msal-react';
import { InteractionRequiredAuthError } from '@azure/msal-browser';
import { loginRequest } from './msalConfig';

/**
 * Hook that returns a function to acquire a fresh access token. The actual
 * token acquisition is async and happens per-request inside the axios
 * interceptor — not via a top-level hook.
 */
export function useAccessToken() {
  const { instance, accounts } = useMsal();

  return async (): Promise<string | null> => {
    if (accounts.length === 0) return null;
    try {
      const result = await instance.acquireTokenSilent({
        ...loginRequest,
        account: accounts[0],
      });
      return result.accessToken;
    } catch (err) {
      if (err instanceof InteractionRequiredAuthError) {
        await instance.acquireTokenRedirect(loginRequest);
      }
      return null;
    }
  };
}
