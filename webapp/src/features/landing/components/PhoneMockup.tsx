import { ReactNode } from 'react';
import clsx from 'clsx';

/**
 * Decorative phone frame. Just chrome — consumers render whatever UI they
 * want inside. Sized to visually balance the hero's left-column text at
 * desktop widths; scales down on mobile.
 */
export function PhoneMockup({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={clsx('relative mx-auto w-full max-w-[320px]', className)}>
      {/* Soft glow behind the device */}
      <div
        className="absolute inset-0 -m-8 rounded-[48px] opacity-40 blur-2xl pointer-events-none"
        style={{
          background:
            'radial-gradient(ellipse at center, rgba(0,194,209,0.6), rgba(124,58,237,0.4), transparent 70%)',
        }}
        aria-hidden="true"
      />

      {/* Device chassis */}
      <div className="relative rounded-[40px] bg-gradient-to-b from-zinc-800 to-zinc-900 p-2 shadow-2xl shadow-black/50 border border-white/10">
        <div className="relative rounded-[32px] overflow-hidden bg-dark-bg">
          {/* Notch */}
          <div className="absolute top-0 left-1/2 -translate-x-1/2 w-28 h-5 bg-black rounded-b-2xl z-10" />
          {/* Screen content area */}
          <div className="pt-8 pb-4">{children}</div>
        </div>
      </div>
    </div>
  );
}
