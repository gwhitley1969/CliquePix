import clsx from 'clsx';

/**
 * Custom Google Play-styled badge. Lucide doesn't ship a Play-triangle glyph
 * that matches the official badge, so we inline a small SVG that evokes it
 * (four-color triangle). Replace href with the real Play Store URL when
 * available.
 */
export function PlayStoreBadge({ href = '#', className }: { href?: string; className?: string }) {
  return (
    <a
      href={href}
      className={clsx(
        'inline-flex items-center gap-3 rounded-lg bg-black px-5 py-2.5 text-white',
        'border border-white/20 hover:border-white/40 transition-colors',
        'focus:outline-none focus:ring-2 focus:ring-aqua/50',
        className,
      )}
      aria-label="Get Clique Pix on Google Play (link coming soon)"
    >
      <svg
        width="24"
        height="26"
        viewBox="0 0 24 26"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        aria-hidden="true"
        className="flex-shrink-0"
      >
        <path d="M1.5 1.2 13 13 1.5 24.8c-.35-.26-.58-.68-.58-1.16V2.36c0-.48.23-.9.58-1.16Z" fill="#00C2D1" />
        <path d="m17.5 9 3.7 2.1c.8.46.8 1.62 0 2.08L17.5 15.3 13 13 17.5 9Z" fill="#FFD43B" />
        <path d="M13 13 1.5 24.8c.35.26.83.28 1.24.05L17.5 15.3 13 13Z" fill="#EC4899" />
        <path d="M2.74 1.15c-.4-.23-.89-.2-1.24.05L13 13l4.5-4L2.74 1.15Z" fill="#16A34A" />
      </svg>
      <div className="text-left leading-tight">
        <div className="text-[10px] tracking-wide text-white/80">Get it on</div>
        <div className="text-lg font-semibold">Google Play</div>
      </div>
    </a>
  );
}
