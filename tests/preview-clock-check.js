const createClock=new Function(readText('web/preview-clock.js').replace(/^export /mg,'')+'\nreturn createPreviewClock;')();
function assert(value,message){if(!value)throw new Error(message);}
let now=1000;
const audio={currentTime:1,ended:false}, clock=createClock(audio,1,3,()=>now);
now+=5000;assert(clock()===1,'Audio must drive the reveal');
audio.currentTime=2;assert(clock()===2,'Audio clock did not advance');
audio.currentTime=3;audio.ended=true;assert(clock()===3,'Audio-to-tail transition jumped');
now+=1250;assert(clock()===4.25,'Silent tail did not advance after audio end');
const resume=createClock(audio,4.5,3,()=>now);
assert(resume()===4.5,'Seeking into silent tail restarted audio');
now+=500;assert(resume()===5,'Resumed tail did not advance');
const silent=createClock(null,.25,0,()=>now);
now+=750;assert(silent()===1,'Silent preview clock changed');
report('Preview clock: audio synchronization, transition, silent tail, seeking and resume passed.');
var testDone=true;
