import { useCallback, useState } from 'react';
import Cropper from 'react-easy-crop';
import type { Area } from 'react-easy-crop';
import * as Dialog from '@radix-ui/react-dialog';
import { X } from 'lucide-react';
import clsx from 'clsx';
import { Button } from '../../components/Button';
import { useAvatarUpload, type AvatarFilter } from './useAvatarUpload';
import type { User } from '../../models';

/**
 * Square-crop editor with filter + frame selection. Mirrors the Flutter
 * `AvatarEditorScreen` so users get a cohesive cross-platform experience.
 *
 * File flow: user picks a File via the parent → we turn it into an
 * object URL, let them pan/zoom, then use `createImageBitmap` + a
 * canvas to extract the cropped region as a Blob before handing it to
 * `useAvatarUpload.upload`.
 */
export function AvatarEditor({
  file,
  currentFramePreset,
  open,
  onOpenChange,
  onComplete,
}: {
  file: File | null;
  currentFramePreset: number;
  open: boolean;
  onOpenChange: (v: boolean) => void;
  onComplete: (user: User) => void;
}) {
  const { upload, uploading } = useAvatarUpload();
  const [filter, setFilter] = useState<AvatarFilter>('original');
  const [framePreset, setFramePreset] = useState<number>(currentFramePreset);
  const [crop, setCrop] = useState({ x: 0, y: 0 });
  const [zoom, setZoom] = useState(1);
  const [croppedPixels, setCroppedPixels] = useState<Area | null>(null);

  const srcUrl = file ? URL.createObjectURL(file) : null;

  const onCropComplete = useCallback((_c: Area, pixels: Area) => {
    setCroppedPixels(pixels);
  }, []);

  async function handleSave() {
    if (!file || !croppedPixels) return;
    const blob = await getCroppedBlob(file, croppedPixels);
    if (!blob) return;
    const user = await upload(blob, filter, framePreset);
    if (user) {
      onComplete(user);
      onOpenChange(false);
    }
  }

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-black/70 backdrop-blur-sm z-40" />
        <Dialog.Content
          className="fixed inset-0 sm:inset-auto sm:top-1/2 sm:left-1/2 sm:-translate-x-1/2 sm:-translate-y-1/2
                     bg-dark-card sm:rounded-2xl sm:w-[540px] sm:h-[640px] border border-white/10 z-50
                     flex flex-col"
        >
          <div className="flex items-center justify-between p-4 border-b border-white/10">
            <Dialog.Title className="text-lg font-bold">Your Avatar</Dialog.Title>
            <Dialog.Close asChild>
              <button className="p-2 hover:bg-white/10 rounded-full" aria-label="Close">
                <X size={18} />
              </button>
            </Dialog.Close>
          </div>

          {srcUrl && (
            <div className="relative bg-black/50" style={{ height: 320 }}>
              <Cropper
                image={srcUrl}
                crop={crop}
                zoom={zoom}
                aspect={1}
                cropShape="round"
                showGrid={false}
                onCropChange={setCrop}
                onZoomChange={setZoom}
                onCropComplete={onCropComplete}
              />
            </div>
          )}

          <div className="p-4 space-y-4 flex-1 overflow-auto">
            {/* Zoom slider */}
            <div>
              <label className="block text-xs font-semibold text-white/60 uppercase tracking-wider mb-2">
                Zoom
              </label>
              <input
                type="range"
                min={1}
                max={3}
                step={0.01}
                value={zoom}
                onChange={(e) => setZoom(Number(e.target.value))}
                className="w-full accent-electric-aqua"
              />
            </div>

            {/* Filter */}
            <div>
              <label className="block text-xs font-semibold text-white/60 uppercase tracking-wider mb-2">
                Filter
              </label>
              <div className="flex gap-2">
                {(['original', 'bw', 'warm', 'cool'] as AvatarFilter[]).map((f) => (
                  <button
                    key={f}
                    onClick={() => setFilter(f)}
                    className={clsx(
                      'px-3 py-1.5 rounded-full text-sm border transition',
                      f === filter
                        ? 'border-electric-aqua text-electric-aqua bg-electric-aqua/10'
                        : 'border-white/15 text-white/70 hover:border-white/30',
                    )}
                  >
                    {filterLabel(f)}
                  </button>
                ))}
              </div>
            </div>

            {/* Frame preset */}
            <div>
              <label className="block text-xs font-semibold text-white/60 uppercase tracking-wider mb-2">
                Frame color
              </label>
              <div className="flex gap-3">
                {[0, 1, 2, 3, 4].map((p) => (
                  <button
                    key={p}
                    onClick={() => setFramePreset(p)}
                    className={clsx(
                      'w-11 h-11 rounded-full border-2 transition',
                      p === framePreset ? 'border-white' : 'border-white/20',
                    )}
                    style={{ background: framePreview(p) }}
                    aria-label={`Frame preset ${p}`}
                  >
                    {p === 0 && <span className="text-xs text-white/70">Auto</span>}
                  </button>
                ))}
              </div>
            </div>
          </div>

          <div className="flex gap-2 p-4 border-t border-white/10">
            <Button
              variant="secondary"
              className="flex-1"
              onClick={() => onOpenChange(false)}
              disabled={uploading}
            >
              Cancel
            </Button>
            <Button
              className="flex-1"
              onClick={handleSave}
              disabled={uploading || !croppedPixels}
            >
              {uploading ? 'Uploading…' : 'Save'}
            </Button>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

function filterLabel(f: AvatarFilter): string {
  switch (f) {
    case 'original': return 'Original';
    case 'bw': return 'B & W';
    case 'warm': return 'Warm';
    case 'cool': return 'Cool';
  }
}

function framePreview(p: number): string {
  const palettes = [
    'rgba(255,255,255,0.08)', // 0 auto (neutral swatch)
    'linear-gradient(135deg, #00C2D1, #2563EB)',
    'linear-gradient(135deg, #2563EB, #7C3AED)',
    'linear-gradient(135deg, #7C3AED, #EC4899)',
    'linear-gradient(135deg, #00C2D1, #7C3AED)',
  ];
  return palettes[p] ?? palettes[0];
}

/**
 * Extract the cropped area from the source file as a PNG blob. PNG is
 * lossless so we don't compound JPEG artifacts before the downstream
 * filter + compression pass.
 */
async function getCroppedBlob(file: File, area: Area): Promise<Blob | null> {
  const bitmap = await createImageBitmap(file);
  const canvas = document.createElement('canvas');
  canvas.width = area.width;
  canvas.height = area.height;
  const ctx = canvas.getContext('2d');
  if (!ctx) return null;
  ctx.drawImage(
    bitmap,
    area.x, area.y, area.width, area.height,
    0, 0, area.width, area.height,
  );
  bitmap.close?.();
  return new Promise<Blob | null>((resolve) => {
    canvas.toBlob((b) => resolve(b), 'image/png');
  });
}
