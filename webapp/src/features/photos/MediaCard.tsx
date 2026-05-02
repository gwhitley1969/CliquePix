import { useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useMsal } from '@azure/msal-react';
import { Download, MoreVertical, Play, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import * as DropdownMenu from '@radix-ui/react-dropdown-menu';
import { Avatar } from '../../components/Avatar';
import { ConfirmDestructive } from '../../components/ConfirmDestructive';
import { ReactionBar } from './ReactionBar';
import { ReactorStrip } from './ReactorStrip';
import { ReactorListDialog } from './ReactorListDialog';
import type { Media, Photo, ReactionType, Video } from '../../models';
import { formatRelative } from '../../lib/formatDate';
import { downloadBlob } from '../../lib/downloadBlob';
import {
  addPhotoReaction,
  deletePhoto,
  listPhotoReactions,
  removePhotoReaction,
} from '../../api/endpoints/photos';
import {
  addVideoReaction,
  deleteVideo,
  getVideoPlayback,
  listVideoReactions,
  removeVideoReaction,
} from '../../api/endpoints/videos';

export function MediaCard({
  item,
  onOpen,
  eventCreatedByUserId,
}: {
  item: Media;
  onOpen: () => void;
  /** Event organizer's user ID — enables organizer moderation deletes. */
  eventCreatedByUserId?: string | null;
}) {
  const qc = useQueryClient();
  const { accounts } = useMsal();
  const myOid = accounts[0]?.localAccountId;
  // Fallback to the /api/users/me result if available — MSAL's localAccountId is
  // the Entra oid, which equals the JWT sub our backend uses as external_auth_id,
  // but the users.id UUID is different. We compare UUIDs, so grab the cached
  // verified user id from React Query instead.
  const verifiedUser = qc.getQueryData<{ id: string }>(['auth', 'verify']);
  const myUserId = verifiedUser?.id ?? myOid;
  const isUploader = myUserId != null && item.uploadedByUserId === myUserId;
  const isOrganizerDeletingOthers =
    myUserId != null &&
    eventCreatedByUserId != null &&
    eventCreatedByUserId === myUserId &&
    item.uploadedByUserId !== myUserId;
  const canDelete = isUploader || isOrganizerDeletingOthers;

  const [confirmDelete, setConfirmDelete] = useState(false);
  const [downloading, setDownloading] = useState(false);
  const [reactorsOpen, setReactorsOpen] = useState(false);

  const totalReactions = Object.values(item.reactionCounts ?? {}).reduce<number>(
    (sum, count) => sum + (count ?? 0),
    0,
  );

  const fetchReactors = () =>
    item.mediaType === 'photo'
      ? listPhotoReactions(item.id)
      : listVideoReactions(item.id);

  const deleteMut = useMutation({
    mutationFn: () =>
      item.mediaType === 'photo' ? deletePhoto(item.id) : deleteVideo(item.id),
    onSuccess: () => {
      const noun = item.mediaType === 'photo' ? 'Photo' : 'Video';
      const verb = isOrganizerDeletingOthers ? 'removed' : 'deleted';
      toast.success(`${noun} ${verb}`);
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
        <Avatar
          name={item.uploadedByName ?? 'User'}
          imageUrl={item.uploadedByAvatarUrl}
          thumbUrl={item.uploadedByAvatarThumbUrl}
          framePreset={item.uploadedByAvatarFramePreset}
          cacheBuster={
            item.uploadedByAvatarUpdatedAt
              ? `${item.uploadedByUserId}_${new Date(item.uploadedByAvatarUpdatedAt).getTime()}`
              : undefined
          }
          size={36}
        />
        <div className="flex-1 min-w-0">
          <div className="text-sm font-semibold text-white truncate">
            {item.uploadedByName ?? 'User'}
          </div>
          <div className="text-xs text-white/50">{formatRelative(item.createdAt)}</div>
        </div>
        {canDelete && (
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
                  <Trash2 size={14} /> {isOrganizerDeletingOthers ? 'Remove' : 'Delete'}
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

      {/* Footer: who-reacted strip, reactions + download */}
      <footer className="flex flex-col gap-1 px-4 py-3">
        <ReactorStrip
          totalReactions={totalReactions}
          topReactors={item.topReactors}
          onClick={() => setReactorsOpen(true)}
        />
        <div className="flex items-center justify-between gap-3">
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
        </div>
      </footer>

      <ReactorListDialog
        open={reactorsOpen}
        onOpenChange={setReactorsOpen}
        mediaId={item.id}
        mediaType={item.mediaType}
        fetchReactors={fetchReactors}
      />

      <ConfirmDestructive
        open={confirmDelete}
        onOpenChange={setConfirmDelete}
        title={
          isOrganizerDeletingOthers
            ? item.mediaType === 'photo'
              ? 'Remove this photo?'
              : 'Remove this video?'
            : item.mediaType === 'photo'
              ? 'Delete this photo?'
              : 'Delete this video?'
        }
        message={
          isOrganizerDeletingOthers
            ? `You're removing this ${item.mediaType}. It will be permanently deleted for everyone in this event. This cannot be undone.`
            : 'This permanently removes it for everyone in the event. This cannot be undone.'
        }
        confirmLabel={isOrganizerDeletingOthers ? 'Remove' : 'Delete'}
        onConfirm={() => {
          deleteMut.mutate();
          setConfirmDelete(false);
        }}
        loading={deleteMut.isPending}
      />
    </article>
  );
}
