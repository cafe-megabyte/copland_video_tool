import {MP4Writer} from './mp4-writer.js';
import {WebMWriter} from './webm-writer.js';
import {loadSoundtrack} from './m4a-reader.js';
import {timestamp} from './binary.js';
import {withTimeout} from './async-operation.js';
function config(format, width, height, fps) {
  const base = {width, height, framerate: fps, bitrate: Math.min(30000000, Math.max(4000000, Math.round(width * height * fps * .8))), latencyMode: 'realtime'};
  if (format === 'webm') return {...base, codec: 'vp8'};
  // Constrained baseline: no B frames. Try levels sufficient for the selected size.
  const macroblocks = Math.ceil(width / 16) * Math.ceil(height / 16);
  const levels = [
    ['1f', 3600, 108000, 14000000], ['28', 8192, 245760, 20000000],
    ['29', 8192, 245760, 50000000], ['2a', 8704, 522240, 50000000],
    ['32', 22080, 589824, 135000000], ['33', 36864, 983040, 240000000],
    ['34', 36864, 2073600, 240000000], ['3c', 139264, 4177920, 240000000]
  ];
  const level = levels.find(([, frame, rate, bitrate]) => macroblocks <= frame && macroblocks * fps <= rate && base.bitrate <= bitrate)?.[0] || '3c';
  return {...base, codec: `avc1.42E0${level}`, avc: {format: 'avc'}};
}
export async function availableFormats(width, height, fps, sound = false) {
  return probeFormats(width, height, fps, sound);
}
async function probeFormats(width, height, fps, sound, deadline = Infinity) {
  if (typeof VideoEncoder === 'undefined' || typeof VideoFrame === 'undefined') return [];
  const formats = [];
  const wait = operation => withTimeout(operation, Math.min(5000, Math.max(1, deadline - Date.now())), 'error.encoderTimeout');
  for (const format of (sound ? ['mp4'] : ['mp4', 'webm'])) {
    if (Date.now() >= deadline) break;
    let encoder;
    try {
      const candidate = config(format, width, height, fps);
      if (!(await wait(VideoEncoder.isConfigSupported(candidate))).supported) continue;
      let outputCount = 0, failure;
      encoder = new VideoEncoder({output: () => outputCount++, error: error => failure = error});
      encoder.configure(candidate);
      const data = new Uint8Array(width * height * 4); for (let i = 3; i < data.length; i += 4) data[i] = 255;
      const frame = new VideoFrame(data, {format: 'RGBA', codedWidth: width, codedHeight: height, timestamp: 0, duration: Math.round(1e6 / fps)});
      try { encoder.encode(frame, {keyFrame: true}); } finally { frame.close(); }
      await wait(encoder.flush());
      if (!failure && outputCount) formats.push(format);
    } catch (error) {
      if (error.message === 'error.encoderTimeout') console.warn('Video encoder probe timed out:', format);
      // An unavailable encoder must not prevent image import or preview.
    } finally { if (encoder && encoder.state !== 'closed') encoder.close(); }
  }
  return formats;
}
export async function fittedVideoSize(width, height, fps, sound = false) {
  const original = {width, height, formats: []};
  if (typeof VideoEncoder === 'undefined' || typeof VideoFrame === 'undefined') return original;
  // Keep the entire search below the worker request timeout, even if codecs hang.
  const deadline = Date.now() + 25000, longest = Math.max(width, height), checked = new Map();
  async function check(side) {
    const w = Math.max(1, Math.floor(width * side / longest));
    const h = Math.max(1, Math.floor(height * side / longest));
    // The engine pads odd image dimensions; probe the actual video dimensions.
    const videoWidth = w + w % 2, videoHeight = h + h % 2, key = `${videoWidth}x${videoHeight}`;
    if (!checked.has(key)) checked.set(key, await probeFormats(videoWidth, videoHeight, fps, sound, deadline));
    return {width: w, height: h, formats: checked.get(key)};
  }
  let best = await check(longest);
  if (best.formats.length) return best;
  let upper = longest, lower = 0;
  // First bracket a working size quickly, then approach the encoder's limit.
  for (let side = Math.floor(longest / 2); side >= 1 && Date.now() < deadline; side = Math.floor(side / 2)) {
    const candidate = await check(side);
    if (candidate.formats.length) { best = candidate; lower = side; break; }
    upper = side;
  }
  // Missing codecs or an unsupported frame rate must not shrink the preview.
  if (!lower) return original;
  while (upper - lower > 1 && Date.now() < deadline) {
    const side = Math.floor((lower + upper) / 2), candidate = await check(side);
    if (candidate.formats.length) { best = candidate; lower = side; }
    else upper = side;
  }
  return best;
}
export async function exportVideo(engine, format, progress, cancelled) {
  if (engine.sound && format !== 'mp4') throw new Error('error.soundFormat');
  const audio = engine.sound ? (await loadSoundtrack()).track : null;
  if (audio && (Math.abs(audio.duration - engine.soundProfile.duration) > 1 / audio.rate ||
      engine.duration < audio.duration)) throw new Error('error.soundData');
  const writer = format === 'mp4' ? new MP4Writer(engine.width, engine.height, engine.fps, audio, engine.duration) : new WebMWriter(engine.width, engine.height, engine.fps);
  let failure;
  const encoder = new VideoEncoder({output: (chunk, metadata) => { try { writer.add(chunk, metadata); } catch (error) { failure = error; } }, error: error => failure = error});
  try {
    encoder.configure(config(format, engine.width, engine.height, engine.fps));
    for (let i = 0; i < engine.count; ++i) {
      if (cancelled()) throw new DOMException('error.cancelled', 'AbortError');
      if (failure) throw failure;
      if (encoder.encodeQueueSize >= 3) await encoder.flush();
      const frame = new VideoFrame(engine.render(i), {format: 'RGBA', codedWidth: engine.width,
        codedHeight: engine.height, timestamp: timestamp(i, engine.fps), duration: Math.min(Math.round(engine.duration * 1e6), timestamp(i + 1, engine.fps)) - timestamp(i, engine.fps)});
      try { encoder.encode(frame, {keyFrame: i % Math.max(1, Math.round(engine.fps * 2)) === 0}); } finally { frame.close(); }
      progress(i + 1, engine.count);
      if (i % 4 === 0) await new Promise(resolve => setTimeout(resolve, 0));
    }
    await encoder.flush(); if (failure) throw failure;
    if (cancelled()) throw new DOMException('error.cancelled', 'AbortError');
    if (writer.samples.length !== engine.count) throw new Error('error.skippedFrames');
    return writer.finish();
  } finally { if (encoder.state !== 'closed') encoder.close(); }
}
