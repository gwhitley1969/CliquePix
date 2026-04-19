import { useState } from 'react';
import type { Media } from '../../models';
import { Lightbox } from './Lightbox';
import { MediaCard } from './MediaCard';

export function MediaFeed({ media }: { media: Media[] }) {
  const [activeIndex, setActiveIndex] = useState<number | null>(null);

  return (
    <>
      <div className="flex flex-col gap-4">
        {media.map((item, idx) => (
          <MediaCard key={item.id} item={item} onOpen={() => setActiveIndex(idx)} />
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
