import { useState } from 'react';
import { useMutation, useQuery } from '@tanstack/react-query';
import { useMsal } from '@azure/msal-react';
import { LogOut, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import { deleteAccount, getMe } from '../../api/endpoints/auth';
import { Button } from '../../components/Button';
import { ConfirmDestructive } from '../../components/ConfirmDestructive';
import { LoadingSpinner } from '../../components/LoadingSpinner';

export function ProfileScreen() {
  const { instance } = useMsal();
  const [confirmDelete, setConfirmDelete] = useState(false);
  const user = useQuery({ queryKey: ['users', 'me'], queryFn: getMe });

  const deleteMut = useMutation({
    mutationFn: deleteAccount,
    onSuccess: () => {
      toast.success('Your account has been deleted');
      instance.logoutRedirect({ postLogoutRedirectUri: '/' }).catch(console.error);
    },
    onError: () => toast.error('Failed to delete account'),
  });

  if (user.isLoading) return <LoadingSpinner />;

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">
      <h1 className="text-2xl font-bold mb-6">Profile</h1>

      <div className="p-4 rounded-lg bg-dark-card border border-white/10 mb-6">
        <div className="flex items-center gap-4">
          {user.data?.avatarUrl ? (
            <img
              src={user.data.avatarUrl}
              alt=""
              className="w-16 h-16 rounded-full object-cover"
            />
          ) : (
            <div className="w-16 h-16 rounded-full bg-gradient-primary flex items-center justify-center text-xl font-bold text-white">
              {user.data?.displayName?.[0]?.toUpperCase() ?? '?'}
            </div>
          )}
          <div>
            <div className="text-lg font-semibold">{user.data?.displayName}</div>
            <div className="text-sm text-white/60">{user.data?.emailOrPhone}</div>
          </div>
        </div>
      </div>

      <div className="space-y-2">
        <Button
          variant="secondary"
          className="w-full justify-start"
          onClick={() =>
            instance.logoutRedirect({ postLogoutRedirectUri: '/' }).catch(console.error)
          }
        >
          <LogOut size={16} className="mr-2" /> Sign out
        </Button>
        <Button
          variant="ghost"
          className="w-full justify-start text-error hover:text-error"
          onClick={() => setConfirmDelete(true)}
        >
          <Trash2 size={16} className="mr-2" /> Delete account
        </Button>
      </div>

      <div className="mt-8 text-xs text-white/40 text-center space-x-3">
        <a href="/docs/privacy" className="hover:underline">
          Privacy Policy
        </a>
        <span>·</span>
        <a href="/docs/terms" className="hover:underline">
          Terms of Service
        </a>
      </div>

      <ConfirmDestructive
        open={confirmDelete}
        onOpenChange={setConfirmDelete}
        title="Delete your Clique Pix account?"
        message="This permanently removes your account, your photos, your videos, your messages, and your clique memberships. Shared cliques and events are preserved for other members. This cannot be undone."
        confirmLabel="Delete account"
        onConfirm={() => deleteMut.mutate()}
        loading={deleteMut.isPending}
      />
    </div>
  );
}
