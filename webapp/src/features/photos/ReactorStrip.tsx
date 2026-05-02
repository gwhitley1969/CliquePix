import { Avatar } from '../../components/Avatar';
import { ChevronRight } from 'lucide-react';
import type { ReactorAvatar } from '../../models';

/**
 * Compact "who reacted?" affordance rendered above the reaction pill row
 * inside the MediaCard footer. Up to 3 most-recent reactor avatars
 * overlapping into a horizontal stack, followed by "N reactions" text.
 *
 * Renders nothing when [totalReactions] is 0 — parents include this
 * unconditionally and it stays out of the way until someone reacts.
 */
export function ReactorStrip({
  totalReactions,
  topReactors,
  onClick,
}: {
  totalReactions: number;
  topReactors: ReactorAvatar[] | undefined;
  onClick: () => void;
}) {
  if (totalReactions <= 0) return null;
  const label = totalReactions === 1 ? '1 reaction' : `${totalReactions} reactions`;
  const visible = (topReactors ?? []).slice(0, 3);

  return (
    <button
      type="button"
      onClick={onClick}
      className="inline-flex items-center gap-2 rounded px-1 py-1 text-sm text-white/70 hover:text-white hover:bg-white/5 focus:outline-none focus:ring-2 focus:ring-aqua/50 transition-colors"
      aria-label={`See who reacted (${totalReactions})`}
    >
      {visible.length > 0 && (
        <div className="relative flex items-center" style={{ width: stackWidth(visible.length) }}>
          {visible.map((r, i) => (
            <span
              key={r.userId}
              className="absolute rounded-full ring-2 ring-dark-card"
              style={{ left: i * (AVATAR_PX - OVERLAP_PX) }}
            >
              <Avatar
                name={r.displayName}
                imageUrl={r.avatarUrl}
                thumbUrl={r.avatarThumbUrl}
                framePreset={r.avatarFramePreset}
                cacheBuster={
                  r.avatarUpdatedAt
                    ? `${r.userId}_${new Date(r.avatarUpdatedAt).getTime()}`
                    : undefined
                }
                size={AVATAR_PX}
              />
            </span>
          ))}
        </div>
      )}
      <span className="font-medium">{label}</span>
      <ChevronRight size={14} className="text-white/40" />
    </button>
  );
}

const AVATAR_PX = 22;
const OVERLAP_PX = 8;

function stackWidth(count: number): number {
  if (count === 0) return 0;
  return AVATAR_PX + (count - 1) * (AVATAR_PX - OVERLAP_PX);
}
