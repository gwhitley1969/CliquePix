import axios, { AxiosError, type AxiosInstance } from 'axios';
import { PublicClientApplication, InteractionRequiredAuthError } from '@azure/msal-browser';
import { loginRequest, msalConfig } from '../auth/msalConfig';
import { toast } from 'sonner';

/**
 * We build a singleton PCA instance reference after the React-side instance has
 * been created and initialized in main.tsx. Because MSAL caches the account in
 * sessionStorage, constructing a second instance here that reads from the same
 * cache is safe for token acquisition only (not for interactive flows).
 */
let pcaRef: PublicClientApplication | null = null;

export function setApiMsalInstance(instance: PublicClientApplication) {
  pcaRef = instance;
}

function getPca(): PublicClientApplication {
  if (!pcaRef) {
    // Fallback: build a reader instance. Safe because MSAL state lives in
    // sessionStorage shared with the React-side instance.
    pcaRef = new PublicClientApplication(msalConfig);
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
  } catch (err) {
    if (err instanceof InteractionRequiredAuthError) {
      await pca.acquireTokenRedirect(loginRequest);
    }
  }
  return config;
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
      const pca = getPca();
      try {
        await pca.acquireTokenRedirect(loginRequest);
      } catch (e) {
        console.error('Token refresh on 401 failed', e);
      }
    }

    return Promise.reject(error);
  },
);
