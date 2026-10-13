// Deliberately limited to the bundled, non-fragmented AAC-LC M4A.
export function readM4A(buffer) {
  try {
    const data = new Uint8Array(buffer), view = new DataView(data.buffer, data.byteOffset, data.byteLength);
    const u32 = p => view.getUint32(p), tag = p => String.fromCharCode(...data.subarray(p, p + 4));
    function atoms(start, end) {
      const result = [];
      while (start < end) {
        if (start + 8 > end) throw new Error();
        const size = u32(start), type = tag(start + 4);
        if (size < 8 || start + size > end) throw new Error();
        result.push({start, end: start + size, payload: start + 8, type}); start += size;
      }
      return result;
    }
    const children = a => atoms(a.payload, a.end);
    const one = (list, type) => { const a = list.filter(a => a.type === type); if (a.length !== 1) throw new Error(); return a[0]; };
    const top = atoms(0, data.length), movie = children(one(top, 'moov'));
    const track = children(one(movie, 'trak')), media = children(one(track, 'mdia'));
    if (tag(one(media, 'hdlr').payload + 8) !== 'soun') throw new Error();
    const mdhd = one(media, 'mdhd'); if (data[mdhd.payload] !== 0) throw new Error();
    const rate = u32(mdhd.payload + 12);
    const table = children(one(children(one(media, 'minf')), 'stbl'));
    const stsd = one(table, 'stsd');
    if (u32(stsd.payload + 4) !== 1) throw new Error();
    const entry = one(atoms(stsd.payload + 8, stsd.end), 'mp4a');
    const channels = view.getUint16(entry.payload + 16);
    if (rate !== 44100 || channels !== 2 || view.getUint16(entry.payload + 8) !== 0) throw new Error();
    const stsz = one(table, 'stsz'), count = u32(stsz.payload + 8), uniform = u32(stsz.payload + 4);
    if (!count || count > 10000 || (!uniform && stsz.end !== stsz.payload + 12 + count * 4)) throw new Error();
    const sizes = Array.from({length: count}, (_, i) => uniform || u32(stsz.payload + 12 + i * 4));
    const stts = one(table, 'stts'), times = [], timeCount = u32(stts.payload + 4);
    if (stts.end !== stts.payload + 8 + timeCount * 8) throw new Error();
    for (let i = 0; i < timeCount; i++) {
      const n = u32(stts.payload + 8 + i * 8), duration = u32(stts.payload + 12 + i * 8);
      if (!n || !duration || times.length + n > count) throw new Error();
      for (let j = 0; j < n; j++) times.push(duration);
    }
    if (times.length !== count) throw new Error();
    const stsc = one(table, 'stsc'), runs = [], runCount = u32(stsc.payload + 4);
    if (!runCount || stsc.end !== stsc.payload + 8 + runCount * 12) throw new Error();
    for (let i = 0; i < runCount; i++) {
      const p = stsc.payload + 8 + i * 12, first = u32(p), samples = u32(p + 4);
      if (!samples || u32(p + 8) !== 1 || (i ? first <= runs[i - 1].first : first !== 1)) throw new Error();
      runs.push({first, samples});
    }
    const stco = one(table, 'stco'), chunkCount = u32(stco.payload + 4);
    if (!chunkCount || stco.end !== stco.payload + 8 + chunkCount * 4) throw new Error();
    const payloads = top.filter(a => a.type === 'mdat'), samples = []; let run = 0;
    for (let chunk = 1; chunk <= chunkCount; chunk++) {
      while (run + 1 < runs.length && chunk >= runs[run + 1].first) run++;
      let offset = u32(stco.payload + 4 + chunk * 4);
      for (let j = 0; j < runs[run].samples; j++) {
        const index = samples.length, size = sizes[index];
        if (!size || !payloads.some(a => offset >= a.payload && offset + size <= a.end)) throw new Error();
        samples.push({data: data.subarray(offset, offset + size), duration: times[index]}); offset += size;
      }
    }
    if (samples.length !== count) throw new Error();
    // afconvert records exact valid samples and priming in Apple's gapless metadata.
    const udta = one(movie, 'udta');
    const metadata = String.fromCharCode(...data.subarray(udta.payload, udta.end));
    const gapless = metadata.match(/iTunSMPB[\s\S]*? ([0-9A-Fa-f]{8}) ([0-9A-Fa-f]{8}) ([0-9A-Fa-f]{8}) ([0-9A-Fa-f]{16})/);
    if (!gapless) throw new Error();
    const priming = parseInt(gapless[2], 16), remainder = parseInt(gapless[3], 16), valid = parseInt(gapless[4], 16);
    const mediaDuration = times.reduce((a, b) => a + b, 0);
    if (valid !== 795756 || priming + valid + remainder !== mediaDuration) throw new Error();
    return {samples, entry: data.slice(entry.start, entry.end), rate, channels, priming, valid,
      mediaDuration, duration: valid / rate, size: sizes.reduce((a, b) => a + b, 0)};
  } catch { throw new Error('error.soundData'); }
}

let loading;
export function loadSoundtrack() {
  if (!loading) loading = (async () => {
    try {
      const response = await fetch(new URL('./copland-theme.m4a', import.meta.url));
      if (!response.ok) throw new Error();
      const buffer = await response.arrayBuffer();
      return {buffer, track: readM4A(buffer)};
    } catch { loading = undefined; throw new Error('error.soundLoad'); }
  })();
  return loading;
}
