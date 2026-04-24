import { useRef, useState } from 'react';
import { useMutation, useQuery } from '@tanstack/react-query';
import { useMsal } from '@azure/msal-react';
import { Camera, LogOut, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import confetti from 'canvas-confetti';
import { deleteAccount, getMe } from '../../api/endpoints/auth';
import { Avatar } from '../../components/Avatar';
import { Button } from '../../components/Button';
import { ConfirmDestructive } from '../../components/ConfirmDestructive';
import { LoadingSpinner } from '../../components/LoadingSpinner';
import { AvatarEditor } from './AvatarEditor';
import { useAvatarUpload } from './useAvatarUpload';

const FIRST_CELEBRATED_KEY = 'first_avatar_celebrated';

export function ProfileScreen() {
  const { instance } = useMsal();
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [confirmRemoveAvatar, setConfirmRemoveAvatar] = useState(false);
  const [editorOpen, setEditorOpen] = useState(false);
  const [pickedFile, setPickedFile] = useState<File | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const user = useQuery({ queryKey: ['users', 'me'], queryFn: getMe });
  const { remove: removeMut } = useAvatarUpload();

  const deleteMut = useMutation({
    mutationFn: deleteAccount,
    onSuccess: () => {
      toast.success('Your account has been deleted');
      instance.logoutRedirect({ postLogoutRedirectUri: '/' }).catch(console.error);
    },
    onError: () => toast.error('Failed to delete account'),
  });

  function onPickFile(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    if (!f) return;
    setPickedFile(f);
    setEditorOpen(true);
    // Reset the input so picking the same file twice still triggers onChange
    e.target.value = '';
  }

  function onEditorComplete() {
    const already = localStorage.getItem(FIRST_CELEBRATED_KEY) === '1';
    if (!already) {
      localStorage.setItem(FIRST_CELEBRATED_KEY, '1');
      confetti({
        particleCount: 80,
        spread: 70,
        startVelocity: 42,
        origin: { y: 0.35 },
        colors: ['#00C2D1', '#2563EB', '#7C3AED', '#EC4899', '#FBBF24'],
      });
    }
    toast.success('Avatar updated');
  }

  if (user.isLoading) return <LoadingSpinner />;

  const u = user.data;
  const hasAvatar = Boolean(u?.avatarUrl);
  const cacheKey = u && u.avatarUpdatedAt
    ? `${u.id}_${new Date(u.avatarUpdatedAt).getTime()}`
    : u?.id;

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">
      <h1 className="text-2xl font-bold mb-6">Profile</h1>

      <div className="p-4 rounded-lg bg-dark-card border border-white/10 mb-6">
        <div className="flex items-center gap-4">
          <button
            type="button"
            onClick={() => fileInputRef.current?.click()}
            className="relative group"
            aria-label="Change avatar"
          >
            <Avatar
              name={u?.displayName}
              imageUrl={u?.avatarUrl}
              thumbUrl={u?.avatarThumbUrl}
              framePreset={u?.avatarFramePreset}
              cacheBuster={cacheKey}
              size={72}
            />
            <span
              className="absolute inset-0 rounded-full bg-black/50 opacity-0 group-hover:opacity-100
                         flex items-center justify-center transition"
            >
              <Camera size={20} className="text-white" />
            </span>
          </button>
          <div className="flex-1">
            <div className="text-lg font-semibold">{u?.displayName}</div>
            <div className="text-sm text-white/60">{u?.emailOrPhone}</div>
            <div className="mt-1 flex gap-3 text-xs">
              <button
                onClick={() => fileInputRef.current?.click()}
                className="text-electric-aqua hover:underline"
              >
                {hasAvatar ? 'Change photo' : 'Add photo'}
              </button>
              {hasAvatar && (
                <button
                  onClick={() => setConfirmRemoveAvatar(true)}
                  className="text-white/50 hover:text-white/70"
                >
                  Remove
                </button>
              )}
            </div>
          </div>
        </div>
      </div>

      <input
        ref={fileInputRef}
        type="file"
        accept="image/jpeg,image/png,image/heic,image/heif"
        onChange={onPickFile}
        className="hidden"
      />

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

      <ConfirmDestructive
        open={confirmRemoveAvatar}
        onOpenChange={setConfirmRemoveAvatar}
        title="Remove avatar?"
        message="Your initials will be shown on photos, videos, and messages instead."
        confirmLabel="Remove"
        onConfirm={() => removeMut.mutate()}
        loading={removeMut.isPending}
      />

      <AvatarEditor
        file={pickedFile}
        currentFramePreset={u?.avatarFramePreset ?? 0}
        open={editorOpen}
        onOpenChange={setEditorOpen}
        onComplete={onEditorComplete}
      />
    </div>
  );
}
