import { useMsal, useIsAuthenticated } from '@azure/msal-react';
import { Navigate, useNavigate } from 'react-router-dom';
import { useEffect } from 'react';
import { Camera } from 'lucide-react';
import { loginRequest } from '../../auth/msalConfig';
import { Button } from '../../components/Button';

export function LoginScreen() {
  const { instance } = useMsal();
  const isAuthenticated = useIsAuthenticated();
  const navigate = useNavigate();

  useEffect(() => {
    if (isAuthenticated) {
      const redirect = sessionStorage.getItem('post_login_redirect');
      sessionStorage.removeItem('post_login_redirect');
      navigate(redirect ?? '/events', { replace: true });
    }
  }, [isAuthenticated, navigate]);

  if (isAuthenticated) return <Navigate to="/events" replace />;

  const onSignIn = () => {
    instance.loginRedirect(loginRequest).catch(console.error);
  };

  return (
    <div className="min-h-screen bg-dark-bg flex items-center justify-center px-6">
      <div className="w-full max-w-md text-center">
        <div className="w-20 h-20 mx-auto rounded-2xl bg-gradient-primary flex items-center justify-center mb-8">
          <Camera size={36} className="text-white" />
        </div>
        <h1 className="text-4xl font-bold mb-2 bg-gradient-primary bg-clip-text text-transparent">
          Clique Pix
        </h1>
        <p className="text-white/60 mb-10">
          Private, instant photo and video sharing for your group.
        </p>
        <Button size="lg" onClick={onSignIn} className="w-full">
          Get Started
        </Button>
        <p className="text-xs text-white/40 mt-8">
          By continuing you agree to our{' '}
          <a href="/docs/terms" className="underline hover:text-white">
            Terms
          </a>{' '}
          and{' '}
          <a href="/docs/privacy" className="underline hover:text-white">
            Privacy Policy
          </a>
          . You must be at least 13 years old.
        </p>
      </div>
    </div>
  );
}
