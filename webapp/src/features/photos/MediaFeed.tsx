import type { Media } from '../../models';
import { formatRelative } from '../../lib/formatDate';
import { Play } from 'lucide-react';
import { useState } from 'react';
import { Lightbox } from './Lightbox';

export function MediaFeed({ media }: { media: Media[] }) {
  const [activeIndex, setActiveIndex] = useState<number | null>(null);

  return (
    <>
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
        {media.map((item, idx) => (
          <button
            key={item.id}
            onClick={() => setActiveIndex(idx)}
            className="relative aspect-square rounded overflow-hidden bg-dark-card group"
          >
            {item.mediaType === 'photo' && item.thumbnailUrl ? (
              <img
                src={item.thumbnailUrl}
                alt=""
                loading="lazy"
                className="w-full h-full object-cover"
              />
            ) : item.mediaType === 'video' && item.posterUrl ? (
              <>
                <img
                  src={item.posterUrl}
                  alt=""
                  loading="lazy"
                  className="w-full h-full object-cover"
                />
                <div className="absolute inset-0 flex items-center justify-center bg-black/30">
                  <Play className="text-white drop-shadow" size={28} />
                </div>
              </>
            ) : (
              <div className="w-full h-full flex items-center justify-center text-xs text-white/50">
                {item.mediaType === 'video' && item.status === 'processing'
                  ? 'Processing…'
                  : 'Loading'}
              </div>
            )}
            <div className="absolute bottom-0 inset-x-0 bg-gradient-to-t from-black/70 to-transparent px-2 py-1 text-left opacity-0 group-hover:opacity-100 transition-opacity">
              <div className="text-xs text-white/90 truncate">
                {item.uploaderDisplayName ?? 'Someone'}
              </div>
              <div className="text-[10px] text-white/60">{formatRelative(item.createdAt)}</div>
            </div>
          </button>
        ))}
      </div>
      {activeIndex !== null && (
        <Lightbox
          media={media}
          initialIndex={activeIndex}
          onClose={() => setActiveIndex(null)}
        />
      )}
    </>
  );
}
