import { ChangeEvent, DragEvent, useRef, useState } from 'react';
import { Upload } from 'lucide-react';
import { toast } from 'sonner';
import { useQueryClient } from '@tanstack/react-query';
import { compressPhoto } from '../../lib/compressPhoto';
import {
  confirmPhotoUpload,
  getPhotoUploadUrl,
} from '../../api/endpoints/photos';
import { trackEvent } from '../../lib/ai';

export function MediaUploader({ eventId }: { eventId: string }) {
  const qc = useQueryClient();
  const inputRef = useRef<HTMLInputElement>(null);
  const [dragOver, setDragOver] = useState(false);
  const [uploading, setUploading] = useState(false);

  const handleFiles = async (files: FileList | null) => {
    if (!files || files.length === 0) return;
    setUploading(true);
    try {
      await Promise.all(
        Array.from(files).map(async (file) => {
          if (file.type.startsWith('image/') || /\.(heic|heif)$/i.test(file.name)) {
            await uploadPhoto(eventId, file);
          } else if (file.type.startsWith('video/')) {
            toast.info('Video upload coming soon — stay tuned.');
          } else {
            toast.error(`${file.name}: unsupported file type`);
          }
        }),
      );
      qc.invalidateQueries({ queryKey: ['event', eventId, 'photos'] });
      toast.success('Upload complete');
    } catch (err) {
      console.error(err);
      toast.error(err instanceof Error ? err.message : 'Upload failed');
    } finally {
      setUploading(false);
    }
  };

  const onDrop = (e: DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    setDragOver(false);
    handleFiles(e.dataTransfer.files);
  };

  const onChange = (e: ChangeEvent<HTMLInputElement>) => {
    handleFiles(e.target.files);
    if (inputRef.current) inputRef.current.value = '';
  };

  return (
    <div
      onDragOver={(e) => {
        e.preventDefault();
        setDragOver(true);
      }}
      onDragLeave={() => setDragOver(false)}
      onDrop={onDrop}
      className={`rounded-lg border-2 border-dashed p-8 text-center transition-colors ${
        dragOver ? 'border-aqua bg-aqua/5' : 'border-white/10 bg-dark-card/50'
      }`}
    >
      <Upload className="mx-auto mb-3 text-white/60" size={28} />
      <p className="text-white/80 text-sm mb-1">Drop photos here to upload</p>
      <p className="text-white/40 text-xs mb-4">
        JPEG, PNG, HEIC — compressed on your device before upload
      </p>
      <input
        ref={inputRef}
        type="file"
        multiple
        accept="image/*,.heic,.heif"
        className="hidden"
        onChange={onChange}
      />
      <button
        type="button"
        onClick={() => inputRef.current?.click()}
        disabled={uploading}
        className="inline-flex items-center justify-center rounded bg-gradient-primary px-4 py-2 text-sm font-medium text-white hover:opacity-90 disabled:opacity-50"
      >
        {uploading ? 'Uploading…' : 'Choose photos'}
      </button>
    </div>
  );
}

async function uploadPhoto(eventId: string, file: File) {
  const { blob, width, height } = await compressPhoto(file);
  const { photoId, uploadUrl } = await getPhotoUploadUrl(eventId, {
    mime_type: 'image/jpeg',
    file_size_bytes: blob.size,
    width,
    height,
  });
  const put = await fetch(uploadUrl, {
    method: 'PUT',
    headers: {
      'x-ms-blob-type': 'BlockBlob',
      'Content-Type': 'image/jpeg',
    },
    body: blob,
  });
  if (!put.ok) throw new Error(`Upload failed (${put.status})`);
  await confirmPhotoUpload(eventId, photoId, {
    mime_type: 'image/jpeg',
    width,
    height,
    file_size_bytes: blob.size,
  });
  trackEvent('web_photo_upload_completed', { event_id: eventId });
}
