import {withTimeout} from './async-operation.js';
// Keep UHD and DCI 4K at their original resolution.
const MAX_SIDE = 4096, MAX_PIXELS = 4096 * 2160;

export function fittedImageSize(width, height) {
  if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0)
    throw new Error('error.imageData');
  const scale = Math.min(1, MAX_SIDE / width, MAX_SIDE / height, Math.sqrt(MAX_PIXELS / (width * height)));
  return {width: Math.max(1, Math.floor(width * scale)), height: Math.max(1, Math.floor(height * scale))};
}

export async function readImage(file, fit = size => size) {
  let waiting = true, bitmap;
  const decoding = createImageBitmap(file).then(image => {
    // A timed-out native decode can still finish after the next import starts.
    if (!waiting) image.close();
    return image;
  });
  try { bitmap = await withTimeout(decoding, 30000, 'error.imageTimeout'); }
  finally { waiting = false; }
  let canvas;
  try {
    const originalWidth = bitmap.width, originalHeight = bitmap.height;
    const {width, height} = await fit(fittedImageSize(originalWidth, originalHeight));
    canvas = document.createElement('canvas'); canvas.width = width; canvas.height = height;
    const ctx = canvas.getContext('2d', {willReadFrequently: true, colorSpace: 'srgb'});
    if (!ctx) throw new Error('error.imageData');
    ctx.imageSmoothingEnabled = true; ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(bitmap, 0, 0, width, height);
    const rgba = new Uint8Array(ctx.getImageData(0, 0, width, height).data.buffer);
    return {rgba, width, height, originalWidth, originalHeight};
  } finally {
    bitmap.close();
    if (canvas) canvas.width = canvas.height = 0;
  }
}
