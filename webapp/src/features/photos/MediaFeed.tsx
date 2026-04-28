import { useState } from 'react';
import type { Media } from '../../models';
import { Lightbox } from './Lightbox';
import { MediaCard } from './MediaCard';

export function MediaFeed({
  media,
  eventCreatedByUserId,
}: {
  media: Media[];
  /** Event organizer's user ID — passed through to each card so organizers
   * see the 3-dot delete menu on others' uploads (moderation). */
  eventCreatedByUserId?: string | null;
}) {
  const [activeIndex, setActiveIndex] = useState<number | null>(null);

  return (
    <>
      <div className="flex flex-col gap-4">
        {media.map((item, idx) => (
          <MediaCard
            key={item.id}
            item={item}
            onOpen={() => setActiveIndex(idx)}
            eventCreatedByUserId={eventCreatedByUserId}
          />
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
