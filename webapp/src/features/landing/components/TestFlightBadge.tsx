import { Apple } from 'lucide-react';
import clsx from 'clsx';

/**
 * TestFlight-styled badge used for the iOS install path while Clique Pix is
 * pre-public-App-Store. Same visual chassis as AppStoreBadge so the install
 * banner reads consistently across platforms; copy differentiates that this
 * is the beta channel. Replace with AppStoreBadge once the public App Store
 * listing is approved.
 */
export function TestFlightBadge({
  href,
  className,
  onClick,
}: {
  href: string;
  className?: string;
  onClick?: () => void;
}) {
  return (
    <a
      href={href}
      onClick={onClick}
      target="_blank"
      rel="noopener noreferrer"
      className={clsx(
        'inline-flex items-center gap-3 rounded-lg bg-black px-5 py-2.5 text-white',
        'border border-white/20 hover:border-white/40 transition-colors',
        'focus:outline-none focus:ring-2 focus:ring-aqua/50',
        className,
      )}
      aria-label="Join the Clique Pix iOS Beta on TestFlight"
    >
      <Apple size={28} className="flex-shrink-0" strokeWidth={1.6} />
      <div className="text-left leading-tight">
        <div className="text-[10px] tracking-wide text-white/80">Get it via</div>
        <div className="text-lg font-semibold">TestFlight</div>
      </div>
    </a>
  );
}
