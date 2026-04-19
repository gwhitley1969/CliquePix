import clsx from 'clsx';

export function BetaChip({ className }: { className?: string }) {
  return (
    <span
      className={clsx(
        'inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[10px] font-semibold uppercase tracking-[0.14em] text-white',
        'border border-white/20 bg-white/5 backdrop-blur-sm',
        className,
      )}
    >
      <span className="inline-block w-1.5 h-1.5 rounded-full bg-gradient-primary" />
      Now in beta
    </span>
  );
}
