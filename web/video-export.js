import {MP4Writer} from './mp4-writer.js';
import {WebMWriter} from './webm-writer.js';
import {timestamp} from './binary.js';
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
export async function availableFormats(width, height, fps) {
  if (typeof VideoEncoder === 'undefined' || typeof VideoFrame === 'undefined') return [];
  const formats = [];
  for (const format of ['mp4', 'webm']) {
    try {
      const candidate = config(format, width, height, fps);
      if (!(await VideoEncoder.isConfigSupported(candidate)).supported) continue;
      let outputCount = 0, failure;
      const encoder = new VideoEncoder({output: () => outputCount++, error: error => failure = error});
      try {
        encoder.configure(candidate);
        const data = new Uint8Array(width * height * 4); for (let i = 3; i < data.length; i += 4) data[i] = 255;
        const frame = new VideoFrame(data, {format: 'RGBA', codedWidth: width, codedHeight: height, timestamp: 0, duration: Math.round(1e6 / fps)});
        try { encoder.encode(frame, {keyFrame: true}); } finally { frame.close(); }
        await encoder.flush();
        if (!failure && outputCount) formats.push(format);
      } finally { if (encoder.state !== 'closed') encoder.close(); }
    } catch { /* This format is unavailable for the actual configuration. */ }
  }
  return formats;
}
export async function exportVideo(engine, format, progress, cancelled) {
  const writer = format === 'mp4' ? new MP4Writer(engine.width, engine.height, engine.fps) : new WebMWriter(engine.width, engine.height, engine.fps);
  let failure;
  const encoder = new VideoEncoder({output: (chunk, metadata) => { try { writer.add(chunk, metadata); } catch (error) { failure = error; } }, error: error => failure = error});
  try {
    encoder.configure(config(format, engine.width, engine.height, engine.fps));
    for (let i = 0; i < engine.count; ++i) {
      if (cancelled()) throw new DOMException('error.cancelled', 'AbortError');
      if (failure) throw failure;
      if (encoder.encodeQueueSize >= 3) await encoder.flush();
      const frame = new VideoFrame(engine.render(i), {format: 'RGBA', codedWidth: engine.width,
        codedHeight: engine.height, timestamp: timestamp(i, engine.fps), duration: timestamp(i + 1, engine.fps) - timestamp(i, engine.fps)});
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
