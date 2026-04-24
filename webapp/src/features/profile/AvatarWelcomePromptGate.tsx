import { useEffect, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getMe } from '../../api/endpoints/auth';
import { AvatarEditor } from './AvatarEditor';
import { AvatarWelcomePromptModal, type AvatarWelcomeChoice } from './AvatarWelcomePromptModal';
import { useAvatarUpload } from './useAvatarUpload';

/**
 * Drop-in component that mounts the first-sign-in welcome prompt flow.
 * Mounts invisibly inside `AppLayout`; self-gates on:
 *   * Backend flag `shouldPromptForAvatar` (persistent, cross-device)
 *   * Session-local `hasShown` state (prevents re-prompt within session)
 *
 * Picks a file → opens `AvatarEditor` → upload → toast. Later/No tap
 * records the choice server-side so the prompt stops appearing.
 */
export function AvatarWelcomePromptGate() {
  const [hasShown, setHasShown] = useState(false);
  const [promptOpen, setPromptOpen] = useState(false);
  const [pickedFile, setPickedFile] = useState<File | null>(null);
  const [editorOpen, setEditorOpen] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const user = useQuery({ queryKey: ['users', 'me'], queryFn: getMe });
  const { setPrompt } = useAvatarUpload();

  useEffect(() => {
    if (hasShown) return;
    if (!user.data?.shouldPromptForAvatar) return;
    setHasShown(true);
    setPromptOpen(true);
  }, [hasShown, user.data?.shouldPromptForAvatar]);

  function onChoose(choice: AvatarWelcomeChoice) {
    setPromptOpen(false);
    switch (choice) {
      case 'yes':
        // Give the dialog a tick to close, then surface the file picker.
        setTimeout(() => fileInputRef.current?.click(), 150);
        break;
      case 'later':
        setPrompt.mutate('snooze');
        break;
      case 'no':
        setPrompt.mutate('dismiss');
        break;
    }
  }

  function onPickFile(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    if (!f) return;
    setPickedFile(f);
    setEditorOpen(true);
    e.target.value = '';
  }

  return (
    <>
      <input
        ref={fileInputRef}
        type="file"
        accept="image/jpeg,image/png,image/heic,image/heif"
        onChange={onPickFile}
        className="hidden"
      />
      <AvatarWelcomePromptModal
        open={promptOpen}
        onOpenChange={setPromptOpen}
        onChoose={onChoose}
      />
      <AvatarEditor
        file={pickedFile}
        currentFramePreset={user.data?.avatarFramePreset ?? 0}
        open={editorOpen}
        onOpenChange={setEditorOpen}
        onComplete={() => {
          // The onComplete side-effects (confetti, toast) live in ProfileScreen's
          // onComplete — the welcome-path just updates react-query cache via
          // useAvatarUpload and quietly closes the editor.
        }}
      />
    </>
  );
}
