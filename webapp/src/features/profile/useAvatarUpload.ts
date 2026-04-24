import { useCallback, useState } from 'react';
import imageCompression from 'browser-image-compression';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import {
  confirmAvatar,
  deleteAvatar,
  getAvatarUploadUrl,
  recordAvatarPrompt,
  updateAvatarFrame,
  type AvatarPromptAction,
} from '../../api/endpoints/avatar';
import type { User } from '../../models';

/** Filter presets we offer in the crop step. Matches mobile 1:1. */
export type AvatarFilter = 'original' | 'bw' | 'warm' | 'cool';

/**
 * Everything the `AvatarEditor` modal needs to orchestrate a single
 * upload: compress → SAS → PUT → confirm → invalidate ['users', 'me'].
 *
 * The hook does not own the crop state — `react-easy-crop` handles that
 * and hands us a final cropped blob. We compress, filter, PUT, confirm.
 */
export function useAvatarUpload() {
  const queryClient = useQueryClient();
  const [uploading, setUploading] = useState(false);

  const upload = useCallback(
    async (croppedBlob: Blob, filter: AvatarFilter, framePreset: number): Promise<User | null> => {
      setUploading(true);
      try {
        // 1. Apply filter (if any) via a canvas pass. No external deps.
        const filtered = filter === 'original'
          ? croppedBlob
          : await applyFilter(croppedBlob, filter);

        // 2. Compress to JPEG. browser-image-compression handles EXIF
        //    strip (default) and respects maxWidthOrHeight.
        const compressedFile = await imageCompression(
          new File([filtered], 'avatar.jpg', { type: 'image/jpeg' }),
          {
            maxSizeMB: 0.5,
            maxWidthOrHeight: 512,
            useWebWorker: true,
            fileType: 'image/jpeg',
          },
        );

        // 3. Get SAS + PUT the blob directly.
        const sas = await getAvatarUploadUrl();
        const putResp = await fetch(sas.uploadUrl, {
          method: 'PUT',
          headers: {
            'x-ms-blob-type': 'BlockBlob',
            'Content-Type': 'image/jpeg',
          },
          body: compressedFile,
        });
        if (!putResp.ok) {
          throw new Error(`Azure upload failed (${putResp.status})`);
        }

        // 4. Confirm — backend generates thumb + returns updated user.
        let updated = await confirmAvatar();

        // 5. Apply the frame preset separately if it changed from the
        //    baseline. Keeps the upload payload purely media-related.
        if (framePreset !== updated.avatarFramePreset) {
          updated = await updateAvatarFrame(framePreset);
        }

        queryClient.setQueryData(['users', 'me'], updated);
        return updated;
      } catch (e) {
        console.error('[avatar] upload failed', e);
        toast.error('Upload failed. Please try again.');
        return null;
      } finally {
        setUploading(false);
      }
    },
    [queryClient],
  );

  const remove = useMutation({
    mutationFn: deleteAvatar,
    onSuccess: (user) => {
      queryClient.setQueryData(['users', 'me'], user);
      toast.success('Avatar removed');
    },
    onError: () => toast.error('Failed to remove avatar'),
  });

  const setPrompt = useMutation({
    mutationFn: (action: AvatarPromptAction) => recordAvatarPrompt(action),
    onSuccess: (user) => queryClient.setQueryData(['users', 'me'], user),
  });

  const setFrame = useMutation({
    mutationFn: updateAvatarFrame,
    onSuccess: (user) => queryClient.setQueryData(['users', 'me'], user),
  });

  return { upload, uploading, remove, setPrompt, setFrame };
}

/**
 * Apply a color-matrix filter to a JPEG blob using an off-screen canvas.
 * Output is a JPEG blob at the input dimensions. Mirrors the mobile
 * app's `AvatarRepository._bakeFilter` matrices 1:1.
 */
async function applyFilter(blob: Blob, filter: AvatarFilter): Promise<Blob> {
  const bitmap = await createImageBitmap(blob);
  const canvas = document.createElement('canvas');
  canvas.width = bitmap.width;
  canvas.height = bitmap.height;
  const ctx = canvas.getContext('2d');
  if (!ctx) return blob;

  // Disable smoothing so we read/write byte-exact pixels.
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(bitmap, 0, 0);
  bitmap.close?.();

  const imgData = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const px = imgData.data;
  applyMatrix(px, matrixFor(filter));
  ctx.putImageData(imgData, 0, 0);

  return new Promise<Blob>((resolve) => {
    canvas.toBlob((b) => resolve(b ?? blob), 'image/jpeg', 0.95);
  });
}

type Matrix = [
  number, number, number, number, number, // R row
  number, number, number, number, number, // G row
  number, number, number, number, number, // B row
  number, number, number, number, number, // A row
];

function matrixFor(f: AvatarFilter): Matrix {
  switch (f) {
    case 'bw':
      return [
        0.299, 0.587, 0.114, 0, 0,
        0.299, 0.587, 0.114, 0, 0,
        0.299, 0.587, 0.114, 0, 0,
        0,     0,     0,     1, 0,
      ];
    case 'warm':
      return [
        1.10, 0,    0,    0, 5,
        0,    1.05, 0,    0, 0,
        0,    0,    0.90, 0, 0,
        0,    0,    0,    1, 0,
      ];
    case 'cool':
      return [
        0.90, 0,    0,    0, 0,
        0,    1.02, 0,    0, 0,
        0,    0,    1.10, 0, 5,
        0,    0,    0,    1, 0,
      ];
    case 'original':
      return [
        1, 0, 0, 0, 0,
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
      ];
  }
}

function applyMatrix(px: Uint8ClampedArray, m: Matrix) {
  for (let i = 0; i < px.length; i += 4) {
    const r = px[i];
    const g = px[i + 1];
    const b = px[i + 2];
    const a = px[i + 3];
    px[i]     = clamp(m[0] * r + m[1] * g + m[2] * b + m[3] * a + m[4]);
    px[i + 1] = clamp(m[5] * r + m[6] * g + m[7] * b + m[8] * a + m[9]);
    px[i + 2] = clamp(m[10] * r + m[11] * g + m[12] * b + m[13] * a + m[14]);
    // alpha (m[15..19]) — identity matrix for all our presets
    px[i + 3] = clamp(m[15] * r + m[16] * g + m[17] * b + m[18] * a + m[19]);
  }
}

function clamp(v: number): number {
  return v < 0 ? 0 : v > 255 ? 255 : v;
}
