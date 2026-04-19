import * as Dialog from '@radix-ui/react-dialog';
import { Button } from './Button';

export function ConfirmDestructive({
  open,
  onOpenChange,
  title,
  message,
  confirmLabel = 'Delete',
  cancelLabel = 'Cancel',
  onConfirm,
  loading,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  onConfirm: () => void | Promise<void>;
  loading?: boolean;
}) {
  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-black/60 data-[state=open]:animate-in data-[state=open]:fade-in-0" />
        <Dialog.Content className="fixed left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 w-[90vw] max-w-md bg-dark-card rounded-lg p-6 border border-white/10 focus:outline-none">
          <Dialog.Title className="text-lg font-semibold text-white mb-2">{title}</Dialog.Title>
          <Dialog.Description className="text-sm text-white/70 mb-6">
            {message}
          </Dialog.Description>
          <div className="flex justify-end gap-2">
            <Dialog.Close asChild>
              <Button variant="ghost" disabled={loading}>
                {cancelLabel}
              </Button>
            </Dialog.Close>
            <Button variant="destructive" onClick={onConfirm} disabled={loading}>
              {loading ? 'Working…' : confirmLabel}
            </Button>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
