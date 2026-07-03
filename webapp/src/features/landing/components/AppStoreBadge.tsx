import { Apple } from 'lucide-react';
import clsx from 'clsx';

/**
 * Custom App Store-styled badge. Dark background, Apple glyph, two-line copy.
 * Inspired by Apple's official badge but uses our own typography + the
 * lucide Apple glyph — we're not distributing Apple's trademarked SVG until
 * we're authorized.
 */
export function AppStoreBadge({
  href = '#',
  className,
  onClick,
}: {
  href?: string;
  className?: string;
  onClick?: () => void;
}) {
  const isPlaceholder = href === '#';
  return (
    <a
      href={href}
      onClick={onClick}
      className={clsx(
        'inline-flex items-center gap-3 rounded-lg bg-black px-5 py-2.5 text-white',
        'border border-white/20 hover:border-white/40 transition-colors',
        'focus:outline-none focus:ring-2 focus:ring-aqua/50',
        className,
      )}
      aria-label={
        isPlaceholder
          ? 'Download CLIQUE Pix on the App Store (link coming soon)'
          : 'Download CLIQUE Pix on the App Store'
      }
    >
      <Apple size={28} className="flex-shrink-0" strokeWidth={1.6} />
      <div className="text-left leading-tight">
        <div className="text-[10px] tracking-wide text-white/80">Download on the</div>
        <div className="text-lg font-semibold">App Store</div>
      </div>
    </a>
  );
}
