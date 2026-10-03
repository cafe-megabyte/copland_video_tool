const expected = JSON.parse(readText('build/internal/tests/native-frames.json'));
const e = new WebAssembly.Instance(new WebAssembly.Module(Uint8Array.from(moduleBytes)), {env:{pow:Math.pow,log:Math.log}}).exports;
let mode = -1;
for (const fixture of expected) {
  if (mode !== fixture.mode) {
    mode = fixture.mode;
    const pointer = e.configure_memory(5,3), rgba = new Uint8Array(e.memory.buffer,pointer,60);
    for(let i=0;i<15;i++) rgba.set([i*13,210-i*5,i*7,255],i*4);
    if(mode===4) [[0,5],[.23,2],[.61,1]].forEach((p,i)=>e.set_keyframe(i,...p));
    const count=e.prepare(.61,29.97,.05,.1,5,mode%4,mode===5?1:2,1,0,4,3,20,0x173363,mode===4?3:0);
    if(count!==fixture.count) throw new Error('Frame count mismatch');
  }
  const pointer=e.render(fixture.index), data=new Uint8Array(e.memory.buffer,pointer,96);
  const hex=[...data].map(x=>x.toString(16).padStart(2,'0')).join('');
  if(hex!==fixture.hex) throw new Error(`Native/WASM mismatch ${mode}:${fixture.index}`);
}
report(`${expected.length} complete native/WASM frames compared byte for byte, including easing, keyframes, regions and padding.`);
var testDone=true;
