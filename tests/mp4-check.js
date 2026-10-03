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
report('MP4 writer created a native-encoded fixture for independent decoding.');var testDone=true;
