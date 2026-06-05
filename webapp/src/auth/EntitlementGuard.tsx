import type { ReactNode } from 'react';
import { Navigate } from 'react-router-dom';
import { useAuthVerify } from '../features/auth/useAuthVerify';

/** Render-gate for authenticated routes. Assumes AuthGuard already passed.
 *  Sends users without effective access (subscribed OR in trial) to /subscribe. */
export function EntitlementGuard({ children }: { children: ReactNode }) {
  const { data: user, isLoading, isError, refetch } = useAuthVerify();

  // Wait for the verify call before deciding — avoids a paywall flash.
  if (isLoading) return null;

  // A 401 self-heals via logoutRedirect inside useAuthVerify. Any OTHER verify
  // failure (transient 5xx / network / CORS blip) previously left a PERMANENT
  // blank screen for the whole authenticated app (isLoading=false + user
  // undefined => `return null` forever). Render a recoverable error instead.
  if (isError || !user) {
    return (
      <div className="min-h-screen bg-dark-bg flex flex-col items-center justify-center px-6 text-center text-white">
        <div className="max-w-sm w-full">
          <h1 className="text-lg font-semibold mb-2">Could not load your account</h1>
          <p className="text-white/60 text-sm mb-5">
            We could not reach Clique Pix. Check your connection and try again.
          </p>
          <button
            onClick={() => refetch()}
            className="rounded bg-gradient-primary px-4 py-2 text-white text-sm font-medium"
          >
            Try again
          </button>
        </div>
      </div>
    );
  }

  const hasAccess = user.entitlement?.effectiveActive === true;
  if (!hasAccess) return <Navigate to="/subscribe" replace />;

  return <>{children}</>;
}
