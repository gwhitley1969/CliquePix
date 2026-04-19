import type { Configuration, RedirectRequest } from '@azure/msal-browser';
import { LogLevel } from '@azure/msal-browser';

const isDev = import.meta.env.DEV;
const redirectBase = isDev ? 'http://localhost:5173' : 'https://clique-pix.com';

export const msalConfig: Configuration = {
  auth: {
    clientId: import.meta.env.VITE_MSAL_CLIENT_ID,
    authority: import.meta.env.VITE_MSAL_AUTHORITY,
    knownAuthorities: [import.meta.env.VITE_MSAL_KNOWN_AUTHORITY],
    redirectUri: `${redirectBase}/auth/callback`,
    postLogoutRedirectUri: `${redirectBase}/`,
    navigateToLoginRequestUrl: true,
  },
  cache: {
    cacheLocation: 'sessionStorage',
    storeAuthStateInCookie: false,
  },
  system: {
    allowNativeBroker: false,
    loggerOptions: {
      loggerCallback: (level, message) => {
        if (level === LogLevel.Error) console.error('[MSAL]', message);
      },
      logLevel: isDev ? LogLevel.Info : LogLevel.Warning,
      piiLoggingEnabled: false,
    },
  },
};

export const loginRequest: RedirectRequest = {
  scopes: [import.meta.env.VITE_MSAL_SCOPE],
};
