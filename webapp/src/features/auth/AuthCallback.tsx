import { useEffect } from 'react';
import { useIsAuthenticated, useMsal } from '@azure/msal-react';
import { useNavigate } from 'react-router-dom';
import { LoadingSpinner } from '../../components/LoadingSpinner';

export function AuthCallback() {
  const isAuthenticated = useIsAuthenticated();
  const { inProgress } = useMsal();
  const navigate = useNavigate();

  useEffect(() => {
    if (inProgress === 'none') {
      const redirect = sessionStorage.getItem('post_login_redirect') ?? '/events';
      sessionStorage.removeItem('post_login_redirect');
      navigate(isAuthenticated ? redirect : '/login', { replace: true });
    }
  }, [inProgress, isAuthenticated, navigate]);

  return (
    <div className="min-h-screen flex items-center justify-center">
      <LoadingSpinner label="Signing you in…" />
    </div>
  );
}
