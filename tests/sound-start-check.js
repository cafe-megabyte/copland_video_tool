const reference = JSON.parse(readText('build/internal/tests/sound-start-frames.json'));
const images = reference.images.map(hex => Uint8Array.from(hex.match(/../g), s => parseInt(s, 16)));
const e = new WebAssembly.Instance(new WebAssembly.Module(Uint8Array.from(moduleBytes)), {env:{pow:Math.pow,log:Math.log}}).exports;
let compared = 0;
for (const c of reference.cases) {
  const pointer = e.configure_memory(128, 128);
  new Uint8Array(e.memory.buffer, pointer, 128 * 128 * 4).set(images[c.kind]);
  // Saved keyframes must not affect sound, including the automatic start.
  e.set_keyframe(0, 0, 500); e.set_keyframe(1, .1, 1);
  const prepare = sound => e.prepare(9, c.fps, c.blank, c.hold, c.start, c.easing,
    c.mode, 8, 9, 120, 126, 20, c.color, 2, sound);
  for (let repeat = 0; repeat < 2; ++repeat) {
    if (repeat) prepare(0); // Switching sound off and on must reset analysis.
    if (prepare(1) !== c.count || e.timeline_value(0) !== c.duration || e.timeline_value(1) !== c.cue)
      throw new Error('Sound-start preparation changed output timing');
    if (e.timeline_value(2) !== Math.round(c.blank * c.fps) / c.fps)
      throw new Error('Sound-start preparation changed the requested lead-in');
    for (const f of c.frames) {
      const data = new Uint8Array(e.memory.buffer, e.render(f.index), 128 * 128 * 4);
      let hash = 2166136261;
      for (const value of data) hash = Math.imul(hash ^ value, 16777619) >>> 0;
      if (hash !== f.hash) throw new Error(`Sound-start native/WASM frame mismatch ${compared}:${f.index}`);
    }
  }
  compared++;
}
report(`Sound-start native/WASM: ${compared} configurations, all curves, six FPS, custom starts/regions/backgrounds, smooth grids and repeated preparation passed.`);
var testDone = true;
