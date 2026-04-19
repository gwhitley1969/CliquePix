export function LoadingSpinner({ label }: { label?: string }) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 py-12 text-white/60">
      <div className="w-8 h-8 rounded-full border-2 border-white/20 border-t-aqua animate-spin" />
      {label && <span className="text-sm">{label}</span>}
    </div>
  );
}
