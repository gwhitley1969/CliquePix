import { AlertCircle, RefreshCw } from 'lucide-react';
import { Button } from './Button';

export function ErrorState({
  title = 'Something went wrong',
  subtitle,
  onRetry,
}: {
  title?: string;
  subtitle?: string;
  onRetry?: () => void;
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 py-16 px-6 text-center">
      <div className="w-12 h-12 rounded-full bg-dark-card flex items-center justify-center text-error">
        <AlertCircle size={22} />
      </div>
      <h3 className="text-lg font-semibold text-white">{title}</h3>
      {subtitle && <p className="text-sm text-white/60 max-w-sm">{subtitle}</p>}
      {onRetry && (
        <Button variant="secondary" onClick={onRetry} className="mt-2">
          <RefreshCw size={14} className="mr-1" /> Try again
        </Button>
      )}
    </div>
  );
}
