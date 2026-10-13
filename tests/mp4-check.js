function source(path) {return readText(path).replace(/^import .*$/mg,'').replace(/^export /mg,'');}
eval(source('web/binary.js').replace(/const /g,'var '));
eval(source('web/mp4-writer.js').replace('class MP4Writer', 'var MP4Writer = class MP4Writer'));
// A minimal Blob captures writer bytes for independent AVFoundation decoding.
var Blob = class {constructor(parts){this.parts=parts;this.size=parts.reduce((n,p)=>n+p.length,0);}};
const fixture=JSON.parse(readText('build/internal/tests/avc-samples.json'));
const writer=new MP4Writer(66,50,10);
fixture.samples.forEach((s,i)=>writer.add({timestamp:i*100000,byteLength:s.data.length,type:s.key?'key':'delta',copyTo:p=>p.set(s.data)},i===0?{decoderConfig:{description:Uint8Array.from(fixture.configuration)}}:{}));
const blob=writer.finish();const data=join(...blob.parts);
if(!writeBytes('build/internal/tests/js-writer.mp4',[...data]))throw new Error('Cannot save writer fixture');
eval(source('web/m4a-reader.js').replace(/import\.meta/g,'({url: "file:///test/"})'));
const audioBytes=Uint8Array.from(readBytes('assets/copland-theme.m4a'));
const audio=readM4A(audioBytes.buffer);
const e=new WebAssembly.Instance(new WebAssembly.Module(Uint8Array.from(moduleBytes)),{env:{pow:Math.pow,log:Math.log}}).exports;
if(!audio.samples.length||audio.duration!==e.sound_time(2)||audio.valid+audio.priming>audio.mediaDuration)throw new Error('M4A metadata');
const replacement=readM4A(Uint8Array.from(readBytes('build/internal/tests/replacement.m4a')).buffer);
if(replacement.rate!==48000||replacement.channels!==1||replacement.valid!==120017)throw new Error('Replacement M4A metadata');
for(const corrupt of [new Uint8Array(4),audioBytes.slice(0,100),audioBytes.slice(0,-1)]) {
  let rejected=false;try{readM4A(corrupt.buffer);}catch{rejected=true;}if(!rejected)throw new Error('Corrupt M4A accepted');
}
for(const [name,track] of [['sound',audio],['replacement',replacement]])for(const fps of [1,24,29.97,30,60,120])for(const hold of [0,6.125]){
 const cue=name==='sound'?e.sound_time(1):2;
 const duration=Math.max(track.duration,Math.round(cue*fps)/fps+hold);
 const soundWriter=new MP4Writer(66,50,fps,track,duration);
 for(let i=0;i<Math.ceil(duration*fps);i++){
  const s=fixture.samples[i%fixture.samples.length];
  soundWriter.add({timestamp:timestamp(i,fps),byteLength:s.data.length,type:s.key?'key':'delta',copyTo:p=>p.set(s.data)},i===0?{decoderConfig:{description:Uint8Array.from(fixture.configuration)}}:{});
 }
 const result=join(...soundWriter.finish().parts);
 // Hide the video track without moving any payload. This leaves an audio-only
 // M4A with the writer's standard edit list and no Apple gapless metadata.
 const audioOnly=result.slice(), view=new DataView(audioOnly.buffer);
 for(let p=0;p<audioOnly.length;p+=view.getUint32(p))if(String.fromCharCode(...audioOnly.subarray(p+4,p+8))==='moov'){
  for(let q=p+8;q<p+view.getUint32(p);q+=view.getUint32(q))if(String.fromCharCode(...audioOnly.subarray(q+4,q+8))==='trak'){
   audioOnly.set([102,114,101,101],q+4);break;
  }
  break;
 }
 const roundtrip=readM4A(audioOnly.buffer);
 if(roundtrip.rate!==track.rate||roundtrip.channels!==track.channels||roundtrip.valid!==track.valid||roundtrip.priming!==track.priming)throw new Error('M4A edit-list timing');
 if(!writeBytes(`build/internal/tests/js-${hold?'extended-':''}${name}-${fps}.mp4`,[...result]))throw new Error('Cannot save sound fixture');
}
report('M4A reader and MP4 sound fixtures passed at 1, 24, 29.97, 30, 60 and 120 fps.');
report('MP4 writer created a native-encoded fixture for independent decoding.');var testDone=true;
