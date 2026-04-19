import { Apple } from 'lucide-react';
import clsx from 'clsx';

/**
 * Custom App Store-styled badge. Dark background, Apple glyph, two-line copy.
 * Inspired by Apple's official badge but uses our own typography + the
 * lucide Apple glyph — we're not distributing Apple's trademarked SVG until
 * we're authorized. Replace href with the real App Store URL when available.
 */
export function AppStoreBadge({ href = '#', className }: { href?: string; className?: string }) {
  return (
    <a
      href={href}
      className={clsx(
        'inline-flex items-center gap-3 rounded-lg bg-black px-5 py-2.5 text-white',
        'border border-white/20 hover:border-white/40 transition-colors',
        'focus:outline-none focus:ring-2 focus:ring-aqua/50',
        className,
      )}
      aria-label="Download Clique Pix on the App Store (link coming soon)"
    >
      <Apple size={28} className="flex-shrink-0" strokeWidth={1.6} />
      <div className="text-left leading-tight">
        <div className="text-[10px] tracking-wide text-white/80">Download on the</div>
        <div className="text-lg font-semibold">App Store</div>
      </div>
    </a>
  );
}
