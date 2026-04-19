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
import { validateVideoFile } from '../videos/videoValidation';
import { uploadVideo, type UploadProgress } from '../videos/videoUpload';

interface VideoUploadState {
  filename: string;
  progress: UploadProgress;
}

export function MediaUploader({ eventId }: { eventId: string }) {
  const qc = useQueryClient();
  const inputRef = useRef<HTMLInputElement>(null);
  const [dragOver, setDragOver] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [videoUpload, setVideoUpload] = useState<VideoUploadState | null>(null);

  const isVideoFile = (file: File) =>
    file.type.startsWith('video/') || /\.(mp4|mov)$/i.test(file.name);
  const isImageFile = (file: File) =>
    file.type.startsWith('image/') || /\.(heic|heif)$/i.test(file.name);

  const handleFiles = async (files: FileList | null) => {
    if (!files || files.length === 0) return;
    setUploading(true);
    let anyPhotoCompleted = false;
    let anyVideoCommitted = false;
    try {
      // Photos in parallel (small, compressed on-device), videos sequentially
      // (large, block-based, and progress tracking is per-file).
      const list = Array.from(files);
      const images = list.filter(isImageFile);
      const videos = list.filter(isVideoFile);
      const unknown = list.filter((f) => !isImageFile(f) && !isVideoFile(f));

      unknown.forEach((f) => toast.error(`${f.name}: unsupported file type`));

      if (images.length > 0) {
        const results = await Promise.allSettled(images.map((f) => uploadPhoto(eventId, f)));
        results.forEach((r, i) => {
          if (r.status === 'rejected') {
            console.error(r.reason);
            toast.error(`${images[i].name}: photo upload failed`);
          } else {
            anyPhotoCompleted = true;
          }
        });
      }

      for (const file of videos) {
        const validation = await validateVideoFile(file);
        if (!validation.ok) {
          toast.error(`${file.name}: ${validation.reason}`);
          continue;
        }
        try {
          setVideoUpload({
            filename: file.name,
            progress: {
              uploadedBlocks: 0,
              totalBlocks: 0,
              bytesUploaded: 0,
              totalBytes: file.size,
              percent: 0,
            },
          });
          await uploadVideo({
            file,
            eventId,
            durationSeconds: validation.durationSeconds,
            onProgress: (progress) =>
              setVideoUpload((prev) => (prev ? { ...prev, progress } : prev)),
          });
          anyVideoCommitted = true;
        } catch (err) {
          console.error(err);
          toast.error(`${file.name}: video upload failed`);
        } finally {
          setVideoUpload(null);
        }
      }

      if (anyPhotoCompleted) {
        qc.invalidateQueries({ queryKey: ['event', eventId, 'photos'] });
        toast.success('Photos uploaded');
      }
      if (anyVideoCommitted) {
        qc.invalidateQueries({ queryKey: ['event', eventId, 'videos'] });
        toast.success('Video uploaded — processing will complete shortly');
      }
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
      <p className="text-white/80 text-sm mb-1">Drop photos or videos here to upload</p>
      <p className="text-white/40 text-xs mb-4">
        JPEG, PNG, HEIC · MP4, MOV up to 5 minutes
      </p>
      <input
        ref={inputRef}
        type="file"
        multiple
        accept="image/*,.heic,.heif,video/mp4,video/quicktime"
        className="hidden"
        onChange={onChange}
      />
      <button
        type="button"
        onClick={() => inputRef.current?.click()}
        disabled={uploading}
        className="inline-flex items-center justify-center rounded bg-gradient-primary px-4 py-2 text-sm font-medium text-white hover:opacity-90 disabled:opacity-50"
      >
        {uploading ? 'Uploading…' : 'Choose files'}
      </button>

      {videoUpload && (
        <div className="mt-4 text-left max-w-md mx-auto">
          <div className="flex justify-between text-xs text-white/60 mb-1">
            <span className="truncate pr-2" title={videoUpload.filename}>
              {videoUpload.filename}
            </span>
            <span className="flex-shrink-0">{videoUpload.progress.percent}%</span>
          </div>
          <div className="h-1.5 rounded-full bg-white/10 overflow-hidden">
            <div
              className="h-full bg-gradient-primary transition-all duration-200"
              style={{ width: `${videoUpload.progress.percent}%` }}
            />
          </div>
          <div className="text-[10px] text-white/40 mt-1 text-right">
            {formatBytes(videoUpload.progress.bytesUploaded)} /{' '}
            {formatBytes(videoUpload.progress.totalBytes)}
          </div>
        </div>
      )}
    </div>
  );
}

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(0)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
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
