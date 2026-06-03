import type { ReactNode } from 'react';
import { Navigate } from 'react-router-dom';
import { useAuthVerify } from '../features/auth/useAuthVerify';

/** Render-gate for authenticated routes. Assumes AuthGuard already passed.
 *  Sends users without effective access (subscribed OR in trial) to /subscribe. */
export function EntitlementGuard({ children }: { children: ReactNode }) {
  const { data: user, isLoading } = useAuthVerify();

  // Wait for the verify call before deciding — avoids a paywall flash.
  if (isLoading || !user) return null;

  const hasAccess = user.entitlement?.effectiveActive === true;
  if (!hasAccess) return <Navigate to="/subscribe" replace />;

  return <>{children}</>;
}
