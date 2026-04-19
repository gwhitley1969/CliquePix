import axios, { AxiosError, type AxiosInstance } from 'axios';
import { PublicClientApplication, InteractionRequiredAuthError } from '@azure/msal-browser';
import { loginRequest } from '../auth/msalConfig';
import { toast } from 'sonner';
import { trackError, trackEvent } from '../lib/ai';
import { camelize } from './camelize';

/**
 * Singleton reference to the MSAL PublicClientApplication constructed and
 * initialized in main.tsx. The axios interceptors MUST use that exact instance
 * (not a new one) because MSAL.js v3 requires `.initialize()` before any token
 * acquisition call, and we only initialize once.
 *
 * main.tsx is responsible for calling setApiMsalInstance() after
 * `await msalInstance.initialize()` and BEFORE ReactDOM renders anything that
 * can trigger an API request.
 */
let pcaRef: PublicClientApplication | null = null;

export function setApiMsalInstance(instance: PublicClientApplication) {
  pcaRef = instance;
}

function getPca(): PublicClientApplication {
  if (!pcaRef) {
    // This is a programming error, not a user-facing condition. Surfacing
    // loudly here prevents the old silent-401 regression where requests were
    // shipped anonymously because a fallback PCA was never initialized.
    throw new Error(
      'MSAL instance not wired — call setApiMsalInstance() in main.tsx before rendering',
    );
  }
  return pcaRef;
}

export const api: AxiosInstance = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL,
  headers: { 'Content-Type': 'application/json' },
  timeout: 30_000,
});

api.interceptors.request.use(async (config) => {
  const pca = getPca();
  const accounts = pca.getAllAccounts();
  if (accounts.length === 0) return config;

  try {
    const result = await pca.acquireTokenSilent({
      ...loginRequest,
      account: accounts[0],
    });
    config.headers.set('Authorization', `Bearer ${result.accessToken}`);
    return config;
  } catch (err) {
    trackError(err as Error, { stage: 'acquireTokenSilent' });
    if (err instanceof InteractionRequiredAuthError) {
      await pca.acquireTokenRedirect(loginRequest);
    }
    // Never ship an unauthenticated request silently — failing loudly here
    // forces React Query to surface the error instead of rendering empty state.
    throw err;
  }
});

// Normalize response bodies from the backend's snake_case keys
// (created_at, thumbnail_url, is_read, etc.) to camelCase so they line up
// with the TypeScript types in webapp/src/models. Safe for primitive values,
// arrays, and plain objects; skips non-JSON responses (blob SAS PUTs etc.
// don't hit this interceptor since they go directly to Blob Storage).
api.interceptors.response.use((response) => {
  if (response.data && typeof response.data === 'object') {
    response.data = camelize(response.data);
  }
  return response;
});

api.interceptors.response.use(
  (response) => response,
  async (error: AxiosError<{ error?: { code?: string; message?: string } }>) => {
    const status = error.response?.status;
    const errorCode = error.response?.data?.error?.code;
    const errorMessage = error.response?.data?.error?.message;

    if (status === 403 && errorCode === 'AGE_VERIFICATION_FAILED') {
      toast.error(errorMessage ?? 'You must be at least 13 years old to use Clique Pix.');
      const pca = getPca();
      setTimeout(() => {
        pca.logoutRedirect({ postLogoutRedirectUri: '/' }).catch(console.error);
      }, 2500);
      return Promise.reject(error);
    }

    if (status === 401) {
      trackEvent('web_api_401', { url: error.config?.url });
      const pca = getPca();
      try {
        await pca.acquireTokenRedirect(loginRequest);
      } catch (e) {
        console.error('Token refresh on 401 failed', e);
        toast.error('Your session expired. Please sign in again.');
      }
    }

    return Promise.reject(error);
  },
);
