import * as Dialog from '@radix-ui/react-dialog';
import { Camera } from 'lucide-react';
import { Button } from '../../components/Button';

export type AvatarWelcomeChoice = 'yes' | 'later' | 'no';

/**
 * First-sign-in welcome prompt. Non-dismissible via overlay click —
 * requires an explicit button choice, matching mobile UX. Tapping
 * outside or hitting Escape defaults to "later" (safer default than
 * permanent dismiss from an accidental tap).
 */
export function AvatarWelcomePromptModal({
  open,
  onOpenChange,
  onChoose,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  onChoose: (choice: AvatarWelcomeChoice) => void;
}) {
  return (
    <Dialog.Root
      open={open}
      onOpenChange={(v) => {
        if (!v) onChoose('later');
        onOpenChange(v);
      }}
    >
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-black/70 backdrop-blur-sm z-40" />
        <Dialog.Content
          onPointerDownOutside={(e) => e.preventDefault()}
          className="fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 z-50
                     bg-dark-card border border-white/10 rounded-3xl
                     w-[min(92vw,420px)] p-8 flex flex-col items-center text-center"
        >
          <div
            className="w-18 h-18 rounded-full flex items-center justify-center mb-5"
            style={{
              width: 72,
              height: 72,
              background: 'linear-gradient(135deg, #00C2D1, #2563EB, #7C3AED)',
            }}
          >
            <Camera size={32} className="text-white" />
          </div>
          <Dialog.Title className="text-xl font-extrabold mb-2">
            Make yourself known
          </Dialog.Title>
          <Dialog.Description className="text-white/70 text-sm leading-relaxed mb-6">
            Add a photo so friends recognize who's sharing. You can always change it later.
          </Dialog.Description>

          <Button
            className="w-full mb-3"
            onClick={() => onChoose('yes')}
          >
            Add a Photo
          </Button>
          <Button
            variant="secondary"
            className="w-full mb-1"
            onClick={() => onChoose('later')}
          >
            Maybe Later
          </Button>
          <button
            onClick={() => onChoose('no')}
            className="mt-2 text-xs text-white/40 hover:text-white/60 transition"
          >
            No Thanks
          </button>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
