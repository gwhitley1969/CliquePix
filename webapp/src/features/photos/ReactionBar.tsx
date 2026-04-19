import { useMemo, useState } from 'react';
import clsx from 'clsx';
import type { ReactionRecord, ReactionType } from '../../models';

const REACTION_TYPES: ReactionType[] = ['heart', 'laugh', 'fire', 'wow'];
const EMOJI: Record<ReactionType, string> = {
  heart: '❤️',
  laugh: '😂',
  fire: '🔥',
  wow: '😮',
};

type AddResult = Pick<ReactionRecord, 'id' | 'reactionType'>;

export function ReactionBar({
  reactionCounts,
  userReactions,
  onAdd,
  onRemove,
}: {
  reactionCounts?: Record<string, number>;
  userReactions?: string[];
  onAdd: (type: ReactionType) => Promise<AddResult>;
  onRemove: (reactionId: string) => Promise<void>;
}) {
  const [counts, setCounts] = useState<Record<string, number>>(
    () => ({ ...(reactionCounts ?? {}) }),
  );
  // Map of reaction type -> reaction id. Seeded from props (IDs start empty
  // because the enriched list endpoint only returns types); populated as the
  // user adds reactions in this session.
  const [userIds, setUserIds] = useState<Record<string, string>>(() => {
    const seed: Record<string, string> = {};
    for (const t of userReactions ?? []) seed[t] = '';
    return seed;
  });

  const active = useMemo(() => new Set(Object.keys(userIds)), [userIds]);

  const toggle = async (type: ReactionType) => {
    const wasActive = active.has(type);

    // Optimistic UI update.
    setCounts((prev) => {
      const next = { ...prev };
      if (wasActive) {
        next[type] = Math.max(0, (next[type] ?? 1) - 1);
        if (next[type] === 0) delete next[type];
      } else {
        next[type] = (next[type] ?? 0) + 1;
      }
      return next;
    });
    setUserIds((prev) => {
      const next = { ...prev };
      if (wasActive) delete next[type];
      else next[type] = prev[type] ?? '';
      return next;
    });

    try {
      if (wasActive) {
        const id = userIds[type];
        if (id) {
          await onRemove(id);
        }
        // If we had no ID (e.g. the reaction was loaded from the server without
        // one), we can't DELETE. The optimistic UI still reflects the unreact;
        // the next feed refresh will reconcile from the server. This matches
        // the mobile reaction_bar_widget behavior.
      } else {
        const { id } = await onAdd(type);
        setUserIds((prev) => ({ ...prev, [type]: id }));
      }
    } catch {
      // Roll back optimistic update on network/server failure.
      setCounts((prev) => {
        const next = { ...prev };
        if (wasActive) {
          next[type] = (next[type] ?? 0) + 1;
        } else {
          next[type] = Math.max(0, (next[type] ?? 1) - 1);
          if (next[type] === 0) delete next[type];
        }
        return next;
      });
      setUserIds((prev) => {
        const next = { ...prev };
        if (wasActive) next[type] = '';
        else delete next[type];
        return next;
      });
    }
  };

  return (
    <div className="flex items-center gap-2 flex-wrap">
      {REACTION_TYPES.map((type) => {
        const isActive = active.has(type);
        const count = counts[type] ?? 0;
        return (
          <button
            key={type}
            type="button"
            onClick={() => toggle(type)}
            aria-pressed={isActive}
            aria-label={`React with ${type}`}
            className={clsx(
              'inline-flex items-center gap-1 rounded-full px-3 py-1.5 text-sm transition-colors',
              'focus:outline-none focus:ring-2 focus:ring-aqua/50',
              isActive
                ? 'bg-deepBlue/20 border border-deepBlue text-white'
                : 'bg-soft-aqua/10 border border-white/10 text-white/80 hover:bg-soft-aqua/20',
            )}
          >
            <span className="text-base leading-none">{EMOJI[type]}</span>
            {count > 0 && (
              <span
                className={clsx(
                  'text-xs',
                  isActive ? 'font-semibold' : 'text-white/60',
                )}
              >
                {count}
              </span>
            )}
          </button>
        );
      })}
    </div>
  );
}
