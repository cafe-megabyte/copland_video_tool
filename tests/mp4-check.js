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
if(audio.samples.length!==780||audio.priming!==2112||audio.valid!==795756)throw new Error('M4A metadata');
for(const corrupt of [new Uint8Array(4),audioBytes.slice(0,100),audioBytes.slice(0,-1)]) {
  let rejected=false;try{readM4A(corrupt.buffer);}catch{rejected=true;}if(!rejected)throw new Error('Corrupt M4A accepted');
}
for(const fps of [1,24,29.97,30,60,120]){
 const soundWriter=new MP4Writer(66,50,fps,audio,audio.duration);
 for(let i=0;i<Math.ceil(audio.duration*fps);i++){
  const s=fixture.samples[i%fixture.samples.length];
  soundWriter.add({timestamp:timestamp(i,fps),byteLength:s.data.length,type:s.key?'key':'delta',copyTo:p=>p.set(s.data)},i===0?{decoderConfig:{description:Uint8Array.from(fixture.configuration)}}:{});
 }
 const result=join(...soundWriter.finish().parts);
 if(!writeBytes(`build/internal/tests/js-sound-${fps}.mp4`,[...result]))throw new Error('Cannot save sound fixture');
}
report('M4A reader and MP4 sound fixtures passed at 1, 24, 29.97, 30, 60 and 120 fps.');
report('MP4 writer created a native-encoded fixture for independent decoding.');var testDone=true;
