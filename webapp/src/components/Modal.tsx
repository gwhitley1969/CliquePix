import * as Dialog from '@radix-ui/react-dialog';
import { ReactNode } from 'react';
import { X } from 'lucide-react';

export function Modal({
  open,
  onOpenChange,
  title,
  children,
  maxWidth = 'max-w-md',
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  children: ReactNode;
  maxWidth?: string;
}) {
  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-black/60" />
        <Dialog.Content
          className={`fixed left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 w-[92vw] ${maxWidth} bg-dark-card rounded-lg p-6 border border-white/10 focus:outline-none max-h-[85vh] overflow-auto`}
        >
          <div className="flex items-center justify-between mb-4">
            <Dialog.Title className="text-lg font-semibold text-white">{title}</Dialog.Title>
            <Dialog.Close className="text-white/60 hover:text-white">
              <X size={20} />
            </Dialog.Close>
          </div>
          {children}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
