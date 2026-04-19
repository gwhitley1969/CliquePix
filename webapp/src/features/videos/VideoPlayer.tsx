import { useEffect, useRef, useState } from 'react';
import { getVideoPlayback } from '../../api/endpoints/videos';
import { LoadingSpinner } from '../../components/LoadingSpinner';
import { ErrorState } from '../../components/ErrorState';
import { trackError, trackEvent } from '../../lib/ai';

type PlayerMode = 'hls' | 'mp4';

/**
 * Video player with HLS + MP4 fallback + SAS-expiry recovery. Uses native HLS
 * on Safari (supports application/vnd.apple.mpegurl directly) and hls.js
 * elsewhere. The backend returns HLS as raw M3U8 TEXT (not a URL) with
 * per-segment SAS tokens embedded, so we wrap the manifest in a Blob URL
 * before handing it to either player path. On mid-playback errors (likely
 * SAS expiry after 15 min), we save currentTime, re-fetch /playback, and
 * reinitialize at the saved position. Matches the mobile player's recovery
 * pattern.
 */
export function VideoPlayer({ videoId, posterHint }: { videoId: string; posterHint?: string }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const hlsRef = useRef<{ destroy: () => void } | null>(null);
  const manifestBlobUrlRef = useRef<string | null>(null);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  // Survives across the initial mount and any SAS recovery re-init.
  const [mode, setMode] = useState<PlayerMode>('hls');

  useEffect(() => {
    let cancelled = false;
    let recoveryInFlight = false;

    const cleanup = () => {
      if (hlsRef.current) {
        hlsRef.current.destroy();
        hlsRef.current = null;
      }
      if (manifestBlobUrlRef.current) {
        URL.revokeObjectURL(manifestBlobUrlRef.current);
        manifestBlobUrlRef.current = null;
      }
    };

    async function init(seekTo?: number): Promise<void> {
      if (cancelled) return;
      try {
        const playback = await getVideoPlayback(videoId);
        if (cancelled) return;

        const video = videoRef.current;
        if (!video) return;

        const canNativeHls = video.canPlayType('application/vnd.apple.mpegurl') !== '';
        if (mode === 'mp4') {
          video.src = playback.mp4FallbackUrl;
        } else if (canNativeHls) {
          const blobUrl = URL.createObjectURL(
            new Blob([playback.hlsManifest], { type: 'application/vnd.apple.mpegurl' }),
          );
          manifestBlobUrlRef.current = blobUrl;
          video.src = blobUrl;
        } else {
          // Dynamic import keeps hls.js out of the initial bundle — only
          // loaded when a user actually opens a video on a non-Safari browser.
          const { default: Hls } = await import('hls.js');
          if (cancelled) return;
          if (!Hls.isSupported()) {
            video.src = playback.mp4FallbackUrl;
            setMode('mp4');
          } else {
            const hls = new Hls();
            hlsRef.current = hls;
            const blobUrl = URL.createObjectURL(
              new Blob([playback.hlsManifest], { type: 'application/vnd.apple.mpegurl' }),
            );
            manifestBlobUrlRef.current = blobUrl;
            hls.loadSource(blobUrl);
            hls.attachMedia(video);
            hls.on(Hls.Events.ERROR, (_evt, data) => {
              if (!data.fatal) return;
              trackError(new Error(`hls_fatal_${data.type}`), { videoId });
              // Fall back to MP4 for fatal HLS errors (network/media).
              if (!cancelled) {
                hls.destroy();
                hlsRef.current = null;
                setMode('mp4');
                video.src = playback.mp4FallbackUrl;
                video.play().catch(() => {/* autoplay blocked is fine */});
              }
            });
          }
        }

        if (seekTo != null && Number.isFinite(seekTo)) {
          video.currentTime = seekTo;
        }
        setStatus('ready');
        trackEvent('web_video_played', { video_id: videoId, mode });
      } catch (err) {
        if (!cancelled) {
          trackError(err as Error, { stage: 'video_playback_init', videoId });
          setErrorMessage('Could not load this video.');
          setStatus('error');
        }
      }
    }

    async function recoverFromError(): Promise<void> {
      if (recoveryInFlight) return;
      recoveryInFlight = true;
      const video = videoRef.current;
      const position = video?.currentTime ?? 0;
      trackEvent('web_playback_sas_recovered', { video_id: videoId, position });
      cleanup();
      await init(position);
      recoveryInFlight = false;
    }

    const video = videoRef.current;
    const onError = () => {
      // Mid-playback errors are most commonly SAS expiry (15-min window). The
      // manifest blob URL itself is local and doesn't expire, but per-segment
      // SAS tokens inside it do; hls.js surfaces that as a network error. Try
      // a single recovery before giving up.
      if (status === 'ready' && !recoveryInFlight) {
        recoverFromError();
      }
    };
    video?.addEventListener('error', onError);

    init();

    return () => {
      cancelled = true;
      video?.removeEventListener('error', onError);
      cleanup();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [videoId, mode]);

  if (status === 'error') {
    return <ErrorState title="Couldn't play this video" subtitle={errorMessage ?? undefined} />;
  }

  return (
    <div className="relative w-full max-w-4xl mx-auto bg-black">
      <video
        ref={videoRef}
        controls
        playsInline
        poster={posterHint}
        className="w-full max-h-[85vh] bg-black"
      />
      {status === 'loading' && (
        <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
          <LoadingSpinner />
        </div>
      )}
    </div>
  );
}
