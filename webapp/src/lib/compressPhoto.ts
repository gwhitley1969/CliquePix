import imageCompression from 'browser-image-compression';

const isSafari = /^((?!chrome|android).)*safari/i.test(navigator.userAgent);

export interface CompressedPhoto {
  blob: Blob;
  width: number;
  height: number;
}

export async function compressPhoto(file: File): Promise<CompressedPhoto> {
  let input: Blob = file;

  // HEIC pre-convert on non-Safari (Chrome/Firefox/Edge can't decode HEIC in canvas)
  if (/\.(heic|heif)$/i.test(file.name) && !isSafari) {
    const heic2any = (await import('heic2any')).default;
    const converted = (await heic2any({ blob: file, toType: 'image/jpeg', quality: 0.9 })) as Blob;
    input = converted;
  }

  const compressed = await imageCompression(input as File, {
    maxWidthOrHeight: 2048,
    initialQuality: 0.8,
    fileType: 'image/jpeg',
    useWebWorker: true,
    alwaysKeepResolution: false,
  });

  const { width, height } = await readImageDimensions(compressed);
  return { blob: compressed, width, height };
}

function readImageDimensions(blob: Blob): Promise<{ width: number; height: number }> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(blob);
    const img = new Image();
    img.onload = () => {
      const dims = { width: img.naturalWidth, height: img.naturalHeight };
      URL.revokeObjectURL(url);
      resolve(dims);
    };
    img.onerror = (e) => {
      URL.revokeObjectURL(url);
      reject(e);
    };
    img.src = url;
  });
}
