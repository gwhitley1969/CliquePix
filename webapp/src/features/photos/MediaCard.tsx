import { useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useMsal } from '@azure/msal-react';
import { Download, MoreVertical, Play, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import * as DropdownMenu from '@radix-ui/react-dropdown-menu';
import { Avatar } from '../../components/Avatar';
import { ConfirmDestructive } from '../../components/ConfirmDestructive';
import { ReactionBar } from './ReactionBar';
import type { Media, Photo, ReactionType, Video } from '../../models';
import { formatRelative } from '../../lib/formatDate';
import { downloadBlob } from '../../lib/downloadBlob';
import {
  addPhotoReaction,
  deletePhoto,
  removePhotoReaction,
} from '../../api/endpoints/photos';
import {
  addVideoReaction,
  deleteVideo,
  getVideoPlayback,
  removeVideoReaction,
} from '../../api/endpoints/videos';

export function MediaCard({ item, onOpen }: { item: Media; onOpen: () => void }) {
  const qc = useQueryClient();
  const { accounts } = useMsal();
  const myOid = accounts[0]?.localAccountId;
  // Fallback to the /api/users/me result if available — MSAL's localAccountId is
  // the Entra oid, which equals the JWT sub our backend uses as external_auth_id,
  // but the users.id UUID is different. We compare UUIDs, so grab the cached
  // verified user id from React Query instead.
  const verifiedUser = qc.getQueryData<{ id: string }>(['auth', 'verify']);
  const myUserId = verifiedUser?.id ?? myOid;
  const isOwner = myUserId != null && item.uploadedByUserId === myUserId;

  const [confirmDelete, setConfirmDelete] = useState(false);
  const [downloading, setDownloading] = useState(false);

  const deleteMut = useMutation({
    mutationFn: () =>
      item.mediaType === 'photo' ? deletePhoto(item.id) : deleteVideo(item.id),
    onSuccess: () => {
      toast.success(item.mediaType === 'photo' ? 'Photo deleted' : 'Video deleted');
      qc.invalidateQueries({
        queryKey: ['event', item.eventId, item.mediaType === 'photo' ? 'photos' : 'videos'],
      });
    },
    onError: () => toast.error('Delete failed'),
  });

  const onReactAdd = (type: ReactionType) =>
    item.mediaType === 'photo'
      ? addPhotoReaction(item.id, type)
      : addVideoReaction(item.id, type);

  const onReactRemove = (reactionId: string) =>
    item.mediaType === 'photo'
      ? removePhotoReaction(item.id, reactionId)
      : removeVideoReaction(item.id, reactionId);

  const onDownload = async () => {
    if (downloading) return;
    setDownloading(true);
    try {
      if (item.mediaType === 'photo') {
        const url = (item as Photo).originalUrl ?? (item as Photo).thumbnailUrl;
        if (!url) throw new Error('no_url');
        await downloadBlob(url, `cliquepix-${item.id.slice(0, 8)}.jpg`);
      } else {
        const { mp4FallbackUrl } = await getVideoPlayback(item.id);
        await downloadBlob(mp4FallbackUrl, `cliquepix-${item.id.slice(0, 8)}.mp4`);
      }
      toast.success('Saved');
    } catch {
      toast.error('Download failed');
    } finally {
      setDownloading(false);
    }
  };

  const thumb =
    item.mediaType === 'photo'
      ? (item as Photo).thumbnailUrl ?? (item as Photo).originalUrl
      : (item as Video).posterUrl;

  return (
    <article className="bg-dark-card rounded-lg border border-white/10 overflow-hidden">
      {/* Header */}
      <header className="flex items-center gap-3 px-4 py-3">
        <Avatar name={item.uploadedByName ?? 'User'} size={36} />
        <div className="flex-1 min-w-0">
          <div className="text-sm font-semibold text-white truncate">
            {item.uploadedByName ?? 'User'}
          </div>
          <div className="text-xs text-white/50">{formatRelative(item.createdAt)}</div>
        </div>
        {isOwner && (
          <DropdownMenu.Root>
            <DropdownMenu.Trigger
              className="p-1.5 -mr-1 rounded text-white/60 hover:text-white hover:bg-white/5 focus:outline-none focus:ring-2 focus:ring-aqua/50"
              aria-label="Options"
            >
              <MoreVertical size={18} />
            </DropdownMenu.Trigger>
            <DropdownMenu.Portal>
              <DropdownMenu.Content
                align="end"
                sideOffset={4}
                className="bg-dark-card border border-white/10 rounded-md py-1 min-w-[160px] shadow-lg z-50"
              >
                <DropdownMenu.Item
                  onSelect={() => setConfirmDelete(true)}
                  className="flex items-center gap-2 px-3 py-2 text-sm text-error hover:bg-white/5 cursor-pointer focus:outline-none focus:bg-white/5"
                >
                  <Trash2 size={14} /> Delete
                </DropdownMenu.Item>
              </DropdownMenu.Content>
            </DropdownMenu.Portal>
          </DropdownMenu.Root>
        )}
      </header>

      {/* Media */}
      <button
        type="button"
        onClick={onOpen}
        className="block w-full relative bg-dark-bg focus:outline-none"
      >
        {thumb ? (
          <img
            src={thumb}
            alt=""
            loading="lazy"
            className="w-full h-auto max-h-[70vh] object-contain"
          />
        ) : (
          <div className="w-full aspect-video flex items-center justify-center text-sm text-white/40">
            {item.mediaType === 'video' && item.status === 'processing'
              ? 'Processing…'
              : 'Loading'}
          </div>
        )}
        {item.mediaType === 'video' && (
          <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
            <div className="w-14 h-14 rounded-full bg-black/50 flex items-center justify-center">
              <Play className="text-white" size={24} />
            </div>
          </div>
        )}
      </button>

      {/* Footer: reactions + download */}
      <footer className="flex items-center justify-between px-4 py-3 gap-3">
        <ReactionBar
          reactionCounts={item.reactionCounts}
          userReactions={item.userReactions}
          onAdd={onReactAdd}
          onRemove={onReactRemove}
        />
        <button
          type="button"
          onClick={onDownload}
          disabled={downloading}
          className="p-2 rounded text-white/60 hover:text-white hover:bg-white/5 disabled:opacity-40 focus:outline-none focus:ring-2 focus:ring-aqua/50"
          aria-label="Download"
          title="Download"
        >
          <Download size={18} />
        </button>
      </footer>

      <ConfirmDestructive
        open={confirmDelete}
        onOpenChange={setConfirmDelete}
        title={item.mediaType === 'photo' ? 'Delete this photo?' : 'Delete this video?'}
        message="This permanently removes it for everyone in the event. This cannot be undone."
        confirmLabel="Delete"
        onConfirm={() => {
          deleteMut.mutate();
          setConfirmDelete(false);
        }}
        loading={deleteMut.isPending}
      />
    </article>
  );
}
