import React from 'react';
import ReactDOM from 'react-dom/client';
import { RouterProvider } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MsalProvider } from '@azure/msal-react';
import { PublicClientApplication } from '@azure/msal-browser';
import { Toaster } from 'sonner';
import { msalConfig } from './auth/msalConfig';
import { router } from './app/router';
import { initAppInsights } from './lib/ai';
import './styles/globals.css';

const msalInstance = new PublicClientApplication(msalConfig);

// MSAL v3 requires initialize() before any other API call.
await msalInstance.initialize();

// Attach the handler for redirect responses. Must be called before rendering
// so handleRedirectPromise picks up the `?code=...` on /auth/callback.
await msalInstance.handleRedirectPromise().catch((err) => {
  console.error('MSAL redirect handling failed', err);
});

initAppInsights();

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      refetchOnWindowFocus: false,
      retry: 1,
    },
  },
});

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <MsalProvider instance={msalInstance}>
      <QueryClientProvider client={queryClient}>
        <RouterProvider router={router} />
        <Toaster theme="dark" position="top-center" richColors />
      </QueryClientProvider>
    </MsalProvider>
  </React.StrictMode>,
);
