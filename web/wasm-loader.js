export async function createEngine() {
  const response = await fetch(new URL('./engine.wasm', import.meta.url));
  if (!response.ok) throw new Error('error.coreLoad');
  const module = await WebAssembly.compile(await response.arrayBuffer());
  if (WebAssembly.Module.imports(module).some(i => i.module !== 'env' || !['pow', 'log'].includes(i.name)))
    throw new Error('error.coreVersion');
  const e = new WebAssembly.Instance(module, {env: {pow: Math.pow, log: Math.log}}).exports;
  if (e.abi_version() !== 2) throw new Error('error.coreVersion');
  return {
    load(rgba, width, height) {
      if (!(rgba instanceof Uint8Array) || rgba.length !== width * height * 4) throw new Error('error.imageData');
      const pointer = e.configure_memory(width, height);
      if (!pointer) throw new Error('error.imageSize');
      new Uint8Array(e.memory.buffer, pointer, rgba.length).set(rgba);
      this.width = width + width % 2; this.height = height + height % 2;
    },
    prepare(options) {
      const o = options, frames = o.sound ? [] : (o.keyframes || []);
      frames.forEach((f, i) => { if (!e.set_keyframe(i, f.time, f.size)) throw new Error('error.keyframes'); });
      const b = o.box || [0, 0, this.width, this.height];
      const count = e.prepare(o.duration, o.fps, o.blank, o.hold, o.startSize, o.easing,
        o.boxMode, ...b, o.threshold, o.background, frames.length, o.sound ? 1 : 0);
      if (count === -1) throw new Error('error.region');
      if (count <= 0) throw new Error('error.timing');
      this.count = count; this.fps = o.fps; this.sound = !!o.sound; this.duration = e.timeline_value(0);
      return {count, duration: this.duration, revealEnd: e.timeline_value(1), blankDuration: e.timeline_value(2), revealDuration: e.timeline_value(3), width: this.width, height: this.height, box: [0, 1, 2, 3].map(i => e.box_coordinate(i))};
    },
    render(index) {
      const pointer = e.render(index);
      if (!pointer) throw new Error('error.frame');
      return new Uint8Array(e.memory.buffer, pointer, this.width * this.height * 4);
    }
  };
}
