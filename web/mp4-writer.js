import {bytes, text, join, uint, box, fullBox, timestamp} from './binary.js';
const matrix = join(...[65536, 0, 0, 0, 65536, 0, 0, 0, 1073741824].map(n => uint(n)));
const zeros = n => new Uint8Array(n);
export class MP4Writer {
  constructor(width, height, fps) {
    this.width = width; this.height = height; this.fps = fps; this.samples = []; this.description = null; this.size = 0;
  }
  add(chunk, metadata) {
    if (!chunk.byteLength) throw new Error('error.emptyFrame');
    if (chunk.timestamp !== timestamp(this.samples.length, this.fps)) throw new Error('error.frameOrder');
    const description = metadata?.decoderConfig?.description;
    if (description) {
      const next = new Uint8Array(description instanceof ArrayBuffer ? description : description.buffer,
        description.byteOffset || 0, description.byteLength).slice();
      if (this.description && (next.length !== this.description.length || next.some((v, i) => v !== this.description[i])))
        throw new Error('error.encoderChanged');
      this.description = next;
    }
    const data = new Uint8Array(chunk.byteLength); chunk.copyTo(data);
    this.samples.push({data, key: chunk.type === 'key'}); this.size += data.length;
    if (this.size > 512 * 1024 * 1024) throw new Error('error.fileSize');
  }
  finish() {
    const count = this.samples.length, duration = timestamp(count, this.fps);
    if (!count || !this.samples[0].key || !this.description || this.description[0] !== 1)
      throw new Error('error.mp4Config');
    const ftyp = box('ftyp', text('isom'), uint(512), text('isomiso2avc1mp41'));
    const moov = offset => {
      const times = [];
      for (let i = 0; i < count; ++i) {
        const delta = timestamp(i + 1, this.fps) - timestamp(i, this.fps);
        const last = times[times.length - 1];
        if (last?.delta === delta) last.count++; else times.push({count: 1, delta});
      }
      const avc1 = box('avc1', zeros(6), uint(1, 2), zeros(16), uint(this.width, 2), uint(this.height, 2),
        uint(72 * 65536), uint(72 * 65536), zeros(4), uint(1, 2), zeros(32), uint(24, 2), uint(65535, 2), box('avcC', this.description));
      const stbl = box('stbl', fullBox('stsd', 0, uint(1), avc1),
        fullBox('stts', 0, uint(times.length), ...times.map(t => join(uint(t.count), uint(t.delta)))),
        fullBox('stsc', 0, uint(1), uint(1), uint(count), uint(1)),
        fullBox('stsz', 0, uint(0), uint(count), ...this.samples.map(s => uint(s.data.length))),
        fullBox('stco', 0, uint(1), uint(offset)),
        fullBox('stss', 0, uint(this.samples.filter(s => s.key).length),
          ...this.samples.flatMap((s, i) => s.key ? [uint(i + 1)] : [])));
      const minf = box('minf', fullBox('vmhd', 1, zeros(8)),
        box('dinf', fullBox('dref', 0, uint(1), fullBox('url ', 1))), stbl);
      const mdia = box('mdia', fullBox('mdhd', 0, uint(0), uint(0), uint(1000000), uint(duration), uint(0x55c4, 2), zeros(2)),
        fullBox('hdlr', 0, uint(0), text('vide'), zeros(12), text('Copland Video Tool\0')), minf);
      const trak = box('trak', fullBox('tkhd', 7, uint(0), uint(0), uint(1), uint(0), uint(duration), zeros(8),
        zeros(8), matrix, uint(this.width * 65536), uint(this.height * 65536)), mdia);
      return box('moov', fullBox('mvhd', 0, uint(0), uint(0), uint(1000000), uint(duration),
        uint(65536), uint(256, 2), zeros(10), matrix, zeros(24), uint(2)), trak);
    };
    const dummy = moov(0), metadata = moov(ftyp.length + dummy.length + 8);
    return new Blob([ftyp, metadata, uint(this.size + 8), text('mdat'), ...this.samples.map(s => s.data)], {type: 'video/mp4'});
  }
}
