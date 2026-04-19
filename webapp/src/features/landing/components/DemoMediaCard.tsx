import { useState } from 'react';
import { Download } from 'lucide-react';
import clsx from 'clsx';
import { Avatar } from '../../../components/Avatar';

type ReactionKey = 'heart' | 'laugh' | 'fire' | 'wow';
const REACTIONS: { key: ReactionKey; emoji: string; seed: number }[] = [
  { key: 'heart', emoji: '❤️', seed: 12 },
  { key: 'laugh', emoji: '😂', seed: 3 },
  { key: 'fire', emoji: '🔥', seed: 7 },
  { key: 'wow', emoji: '😮', seed: 0 },
];

/**
 * Visual replica of features/photos/MediaCard — header, image, reactions,
 * download icon — with hardcoded demo data. Tappable emoji reactions are
 * client-side-only counters so landing-page visitors can feel the interaction
 * without any auth or API calls.
 */
export function DemoMediaCard() {
  const [counts, setCounts] = useState<Record<ReactionKey, number>>(() =>
    Object.fromEntries(REACTIONS.map((r) => [r.key, r.seed])) as Record<ReactionKey, number>,
  );
  const [active, setActive] = useState<Set<ReactionKey>>(new Set(['heart']));

  const toggle = (key: ReactionKey) => {
    setActive((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
    setCounts((prev) => {
      const isActive = active.has(key);
      return {
        ...prev,
        [key]: Math.max(0, (prev[key] ?? 0) + (isActive ? -1 : 1)),
      };
    });
  };

  return (
    <article className="mx-3 bg-dark-card rounded-lg border border-white/10 overflow-hidden">
      {/* Header */}
      <header className="flex items-center gap-2.5 px-3 py-2.5">
        <Avatar name="Paula Whitley" size={30} />
        <div className="flex-1 min-w-0">
          <div className="text-xs font-semibold text-white truncate">Paula Whitley</div>
          <div className="text-[10px] text-white/50">2m ago</div>
        </div>
      </header>

      {/* Photo — a rich SVG gradient "photo" stand-in so we don't need a stock image */}
      <div className="relative w-full aspect-[4/3] overflow-hidden">
        <svg
          viewBox="0 0 400 300"
          preserveAspectRatio="xMidYMid slice"
          className="w-full h-full"
          aria-hidden="true"
        >
          <defs>
            <linearGradient id="demoCardBg" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stopColor="#EC4899" />
              <stop offset="50%" stopColor="#7C3AED" />
              <stop offset="100%" stopColor="#2563EB" />
            </linearGradient>
            <radialGradient id="demoCardGlow" cx="0.7" cy="0.3" r="0.8">
              <stop offset="0%" stopColor="#FFFFFF" stopOpacity="0.5" />
              <stop offset="60%" stopColor="#FFFFFF" stopOpacity="0" />
            </radialGradient>
          </defs>
          <rect width="400" height="300" fill="url(#demoCardBg)" />
          <rect width="400" height="300" fill="url(#demoCardGlow)" />
          {/* Subtle "figures" silhouettes to evoke a party / event scene */}
          <circle cx="140" cy="200" r="55" fill="rgba(0,0,0,0.2)" />
          <circle cx="220" cy="185" r="65" fill="rgba(0,0,0,0.22)" />
          <circle cx="300" cy="210" r="50" fill="rgba(0,0,0,0.2)" />
        </svg>
      </div>

      {/* Footer — reactions + download */}
      <footer className="flex items-center justify-between px-3 py-2.5 gap-2">
        <div className="flex items-center gap-1.5 flex-wrap">
          {REACTIONS.map((r) => {
            const isActive = active.has(r.key);
            const count = counts[r.key] ?? 0;
            return (
              <button
                key={r.key}
                type="button"
                onClick={() => toggle(r.key)}
                aria-pressed={isActive}
                className={clsx(
                  'inline-flex items-center gap-1 rounded-full px-2 py-1 text-xs transition-colors',
                  isActive
                    ? 'bg-deepBlue/20 border border-deepBlue text-white'
                    : 'bg-white/5 border border-white/10 text-white/80 hover:bg-white/10',
                )}
              >
                <span className="text-sm leading-none">{r.emoji}</span>
                {count > 0 && (
                  <span className={isActive ? 'font-semibold' : 'text-white/60'}>{count}</span>
                )}
              </button>
            );
          })}
        </div>
        <div className="text-white/40 flex-shrink-0">
          <Download size={14} />
        </div>
      </footer>
    </article>
  );
}

