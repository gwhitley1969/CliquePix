import { ReactNode } from 'react';
import { LucideIcon } from 'lucide-react';

export function EmptyState({
  icon: Icon,
  title,
  subtitle,
  action,
}: {
  icon?: LucideIcon;
  title: string;
  subtitle?: string;
  action?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 py-16 px-6 text-center">
      {Icon && (
        <div className="w-12 h-12 rounded-full bg-dark-card flex items-center justify-center text-aqua">
          <Icon size={22} />
        </div>
      )}
      <h3 className="text-lg font-semibold text-white">{title}</h3>
      {subtitle && <p className="text-sm text-white/60 max-w-sm">{subtitle}</p>}
      {action && <div className="mt-2">{action}</div>}
    </div>
  );
}
