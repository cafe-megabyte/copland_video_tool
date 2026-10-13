const e=new WebAssembly.Instance(new WebAssembly.Module(Uint8Array.from(moduleBytes)),{env:{pow:Math.pow,log:Math.log}}).exports;
if(e.sound_time(0)!==.25||e.sound_time(1)!==2||e.sound_time(2)!==120017/48000)throw new Error('Replacement audio profile');
report('Replacement audio duration and both cue times reached WASM.');
var testDone=true;
