import {bytes, text, join, uint, timestamp} from './binary.js';
function vint(n) {
  for (let length = 1; length <= 7; ++length) if (n < 2 ** (length * 7) - 1) {
    const result = uint(n, length); result[0] |= 1 << (8 - length); return result;
  }
  throw new Error('error.fileSize');
}
function id(n) { return uint(n, Math.ceil(Math.log2(n + 1) / 8)); }
function element(n, ...parts) { const payload = join(...parts); return join(id(n), vint(payload.length), payload); }
function integer(n, v) { return element(n, uint(v, Math.max(1, Math.ceil(Math.log2(v + 1) / 8)))); }
function float(n, v) { const b = new Uint8Array(8); new DataView(b.buffer).setFloat64(0, v); return element(n, b); }
export class WebMWriter {
  constructor(width, height, fps) { this.width = width; this.height = height; this.fps = fps; this.samples = []; this.size = 0; }
  add(chunk) {
    if (!chunk.byteLength) throw new Error('error.emptyFrame');
    if (chunk.timestamp !== timestamp(this.samples.length, this.fps)) throw new Error('error.frameOrder');
    const data = new Uint8Array(chunk.byteLength); chunk.copyTo(data);
    this.samples.push({data, key: chunk.type === 'key'}); this.size += data.length;
    if (this.size > 512 * 1024 * 1024) throw new Error('error.fileSize');
  }
  finish() {
    if (!this.samples.length || !this.samples[0].key) throw new Error('error.webmFrames');
    // 1 microsecond ticks; BlockDuration preserves non-integer rates. Clusters
    // start anew before signed 16-bit relative block timecodes overflow.
    const header = element(0x1a45dfa3, integer(0x4286, 1), integer(0x42f7, 1), integer(0x42f2, 4),
      integer(0x42f3, 8), element(0x4282, text('webm')), integer(0x4287, 4), integer(0x4285, 2));
    const info = element(0x1549a966, integer(0x2ad7b1, 1000),
      float(0x4489, timestamp(this.samples.length, this.fps)), element(0x4d80, text('Copland Video Tool')), element(0x5741, text('Copland Video Tool')));
    const tracks = element(0x1654ae6b, element(0xae, integer(0xd7, 1), integer(0x73c5, 1), integer(0x83, 1),
      integer(0x9c, 0), element(0x86, text('V_VP8')), integer(0x23e383, Math.round(1e9 / this.fps)),
      element(0xe0, integer(0xb0, this.width), integer(0xba, this.height))));
    const clusters = [], cues = []; let position = info.length + tracks.length;
    let blocks = [], start = -1, cueTimes = [];
    const flush = () => {
      if (!blocks.length) return;
      const cluster = element(0x1f43b675, integer(0xe7, start), ...blocks);
      for (const time of cueTimes) cues.push(element(0xbb, integer(0xb3, time),
        element(0xb7, integer(0xf7, 1), integer(0xf1, position))));
      clusters.push(cluster); position += cluster.length; blocks = []; cueTimes = [];
    };
    this.samples.forEach((sample, i) => {
      const time = timestamp(i, this.fps);
      if (start < 0 || time - start > 32767 || (sample.key && blocks.length)) { flush(); start = time; }
      const block = element(0xa1, bytes(0x81), uint(time - start, 2), bytes(0), sample.data);
      const duration = integer(0x9b, timestamp(i + 1, this.fps) - time);
      // ReferenceBlock distinguishes delta frames from independently decodable ones.
      const previousDelta = i ? timestamp(i - 1, this.fps) - time : 0;
      const reference = sample.key ? [] : [element(0xfb, uint(2 ** 32 + previousDelta, 4))];
      blocks.push(element(0xa0, block, duration, ...reference));
      if (sample.key) cueTimes.push(time);
    }); flush();
    const cueData = element(0x1c53bb6b, ...cues);
    const size = position + cueData.length;
    return new Blob([header, id(0x18538067), vint(size), info, tracks, ...clusters, cueData], {type: 'video/webm'});
  }
}
