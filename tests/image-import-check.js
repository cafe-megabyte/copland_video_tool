const {fittedImageSize} = new Function(readText('web/image-import.js').replace(/^import .*\n/mg, '').replace(/^export /mg, '') + '\nreturn {fittedImageSize};')();
function assert(value, message) { if (!value) throw new Error(message); }
const cases = [
  [65, 49, 65, 49], [3840, 2160, 3840, 2160], [4096, 2160, 4096, 2160], [2160, 4096, 2160, 4096],
  [4096, 2161, 4095, 2160],
  [5000, 100, 4096, 81], [100, 5000, 81, 4096],
  [4000, 3000, 3434, 2575], [4096, 4096, 2974, 2974],
  [6000, 4000, 3642, 2428], [100000, 1, 4096, 1]
];
for (const [w, h, expectedWidth, expectedHeight] of cases) {
  const {width, height} = fittedImageSize(w, h);
  assert(width === expectedWidth && height === expectedHeight, `Unexpected size for ${w} × ${h}: ${width} × ${height}`);
}
for (const w of [1, 3, 2048, 2160, 2161, 2974, 2975, 4095, 4096, 4097, 65535]) {
  for (const h of [1, 3, 2048, 2160, 2161, 2974, 2975, 4095, 4096, 4097, 65535]) {
    const {width, height} = fittedImageSize(w, h);
    assert(width >= 1 && height >= 1 && width <= w && height <= h, 'Upscaling or empty output');
    assert(width <= 4096 && height <= 4096 && width * height <= 8847360, 'Processing limits exceeded');
    assert(Math.abs(width * h - height * w) <= Math.max(w, h), 'Aspect ratio changed beyond whole-pixel rounding');
  }
}
for (const [w, h] of [[0, 1], [1, 0], [-1, 1], [1, NaN], [Infinity, 1], [1.5, 3]]) {
  let rejected = false;
  try { fittedImageSize(w, h); } catch (error) { rejected = error.message === 'error.imageData'; }
  assert(rejected, 'Invalid dimensions accepted');
}
report('Image import: unchanged small images, side/pixel limits, aspect ratio and invalid dimensions passed.');
var testDone = true;
