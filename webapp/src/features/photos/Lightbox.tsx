import { useEffect, useState } from 'react';
import { ChevronLeft, ChevronRight, Download, X } from 'lucide-react';
import type { Media } from '../../models';
import { downloadBlob } from '../../lib/downloadBlob';
import { toast } from 'sonner';
import { VideoPlayer } from '../videos/VideoPlayer';

export function Lightbox({
  media,
  initialIndex,
  onClose,
}: {
  media: Media[];
  initialIndex: number;
  onClose: () => void;
}) {
  const [index, setIndex] = useState(initialIndex);
  const item = media[index];

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
      if (e.key === 'ArrowRight') setIndex((i) => Math.min(media.length - 1, i + 1));
      if (e.key === 'ArrowLeft') setIndex((i) => Math.max(0, i - 1));
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [media.length, onClose]);

  const onDownload = async () => {
    const url =
      item.mediaType === 'photo'
        ? item.originalUrl ?? item.thumbnailUrl
        : item.posterUrl;
    if (!url) {
      toast.error('Nothing to download yet');
      return;
    }
    try {
      await downloadBlob(url, `cliquepix-${item.id}.jpg`);
    } catch {
      toast.error('Download failed');
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 bg-black/90 flex flex-col"
      role="dialog"
      aria-modal="true"
    >
      <header className="flex items-center justify-between p-4">
        <span className="text-sm text-white/60">
          {index + 1} / {media.length}
        </span>
        <div className="flex items-center gap-2">
          <button
            onClick={onDownload}
            className="p-2 text-white/70 hover:text-white"
            aria-label="Download"
          >
            <Download size={20} />
          </button>
          <button
            onClick={onClose}
            className="p-2 text-white/70 hover:text-white"
            aria-label="Close"
          >
            <X size={20} />
          </button>
        </div>
      </header>
      <div className="flex-1 flex items-center justify-center relative px-4">
        {index > 0 && (
          <button
            onClick={() => setIndex(index - 1)}
            className="absolute left-2 p-3 text-white/70 hover:text-white"
          >
            <ChevronLeft size={28} />
          </button>
        )}
        {item.mediaType === 'photo' ? (
          <img
            src={item.originalUrl ?? item.thumbnailUrl ?? ''}
            alt=""
            className="max-w-full max-h-full object-contain"
          />
        ) : item.status === 'active' ? (
          <VideoPlayer videoId={item.id} posterHint={item.posterUrl} />
        ) : (
          <div className="text-center text-white/70 text-sm max-w-md">
            {item.status === 'processing'
              ? 'This video is still transcoding — check back in a minute.'
              : 'This video isn\u2019t ready to play yet.'}
          </div>
        )}
        {index < media.length - 1 && (
          <button
            onClick={() => setIndex(index + 1)}
            className="absolute right-2 p-3 text-white/70 hover:text-white"
          >
            <ChevronRight size={28} />
          </button>
        )}
      </div>
    </div>
  );
}
