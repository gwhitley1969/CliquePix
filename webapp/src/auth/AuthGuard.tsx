import { ReactNode, useEffect } from 'react';
import { useIsAuthenticated, useMsal } from '@azure/msal-react';
import { useLocation } from 'react-router-dom';
import { loginRequest } from './msalConfig';

export function AuthGuard({ children }: { children: ReactNode }) {
  const isAuthenticated = useIsAuthenticated();
  const { instance, inProgress } = useMsal();
  const location = useLocation();

  useEffect(() => {
    if (!isAuthenticated && inProgress === 'none') {
      // Preserve the intended post-login destination.
      sessionStorage.setItem('post_login_redirect', location.pathname + location.search);
    }
  }, [isAuthenticated, inProgress, location]);

  if (inProgress !== 'none' && !isAuthenticated) {
    return null; // MSAL is resolving; render nothing for a frame or two
  }

  if (!isAuthenticated) {
    // Kick off redirect sign-in instead of showing a login page for protected routes.
    instance.loginRedirect(loginRequest).catch(console.error);
    return null;
  }

  return <>{children}</>;
}
