import { useEffect } from 'react';
import { useIsAuthenticated, useMsal } from '@azure/msal-react';
import { useMutation } from '@tanstack/react-query';
import { useNavigate, useParams } from 'react-router-dom';
import { toast } from 'sonner';
import { Camera } from 'lucide-react';
import { joinCliqueByCode } from '../../api/endpoints/cliques';
import { loginRequest } from '../../auth/msalConfig';
import { Button } from '../../components/Button';
import { LoadingSpinner } from '../../components/LoadingSpinner';

const PENDING_INVITE_KEY = 'pending_invite_code';

export function InviteAcceptScreen() {
  const { code } = useParams<{ code: string }>();
  const isAuthenticated = useIsAuthenticated();
  const { instance } = useMsal();
  const navigate = useNavigate();

  const joinMut = useMutation({
    mutationFn: (inviteCode: string) => joinCliqueByCode(inviteCode),
    onSuccess: (clique) => {
      sessionStorage.removeItem(PENDING_INVITE_KEY);
      toast.success(`Joined ${clique.name}`);
      navigate(`/cliques/${clique.id}`, { replace: true });
    },
    onError: (err) => {
      sessionStorage.removeItem(PENDING_INVITE_KEY);
      console.error(err);
      toast.error('That invite is no longer valid.');
      navigate('/cliques', { replace: true });
    },
  });

  useEffect(() => {
    if (isAuthenticated && code) {
      joinMut.mutate(code);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isAuthenticated, code]);

  const onSignIn = () => {
    if (code) sessionStorage.setItem(PENDING_INVITE_KEY, code);
    sessionStorage.setItem('post_login_redirect', `/invite/${code}`);
    instance.loginRedirect(loginRequest).catch(console.error);
  };

  if (isAuthenticated) {
    return <LoadingSpinner label="Accepting invite…" />;
  }

  return (
    <div className="min-h-screen flex items-center justify-center px-6 text-center">
      <div className="max-w-md w-full">
        <div className="w-16 h-16 mx-auto mb-6 rounded-2xl bg-gradient-primary flex items-center justify-center">
          <Camera size={28} className="text-white" />
        </div>
        <h1 className="text-2xl font-bold mb-2">You've been invited to a Clique</h1>
        <p className="text-white/60 mb-6">
          Sign in or create a Clique Pix account to accept this invite.
        </p>
        <Button size="lg" onClick={onSignIn} className="w-full">
          Sign in to accept
        </Button>
      </div>
    </div>
  );
}
