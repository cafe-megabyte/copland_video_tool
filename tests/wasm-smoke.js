function assert(value, message) { if (!value) throw new Error(message); }
const module = new WebAssembly.Module(Uint8Array.from(moduleBytes));
assert(WebAssembly.Module.imports(module).every(i => i.module === 'env' && ['pow', 'log'].includes(i.name)), 'Unexpected runtime import');
const e = new WebAssembly.Instance(module, {env: {pow: Math.pow, log: Math.log}}).exports;
assert(e.abi_version() === 1, 'ABI');
assert(!e.configure_memory(0, 3) && !e.configure_memory(99999, 3), 'Invalid dimensions accepted');
const ptr = e.configure_memory(5, 3);
assert(ptr === e.heap_start() && ptr >= 65536, 'Heap overlaps stack/static data');
let data = new Uint8Array(e.memory.buffer);
for (let i = 0; i < 15; i++) data.set([i * 7, 100, 210, 255], ptr + i * 4);
assert(e.prepare(9, 30, .1, 1, 0, 0, 0, 0, 0, 5, 3, 20, -1, 0) === 304, 'Standard frame count');
assert(e.render(0) && e.render(303) && !e.render(304), 'Frame bounds');
let out = new Uint8Array(e.memory.buffer, e.output_address(), 6 * 4 * 4);
assert(out[0] === 0 && out[4 * 4] === 28 && out[4 * 5] === 0 && out[3] === 255, 'Source/padding');
assert(e.configure_memory(1920, 1080) >= 65536, 'Memory growth');
assert(e.set_keyframe(0, 0, 10) && e.set_keyframe(1, 1, 1) && !e.set_keyframe(256, 2, 1), 'Keyframe bounds');
assert(e.prepare(9, 30, .1, 1, 0, 0, 0, 0, 0, 1920, 1080, 20, 0xffffff, 2) === 64, 'Keyframe timing');
report('WASM: imports, ABI, memory growth, padding, 304 frames and keyframe timing passed.');
var testDone = true;
