// Exercise real import/worker/probe code with native operations that never settle.
// Fake time keeps these failure checks fast and deterministic in JavaScriptCore.
function assert(value, message) { if (!value) throw new Error(message); }
async function drain() { for (let i = 0; i < 40; i++) await Promise.resolve(); }
function clock() {
  let now = 0, id = 0;
  const jobs = new Map();
  return {
    setTimeout(fn, delay) { const key = ++id; jobs.set(key, {fn, at: now + delay}); return key; },
    clearTimeout(key) { jobs.delete(key); },
    async advance(delay) {
      now += delay;
      for (;;) {
        const due = [...jobs].find(([, job]) => job.at <= now);
        if (!due) break;
        jobs.delete(due[0]); due[1].fn(); await drain();
      }
      await drain();
    },
    get pending() { return jobs.size; }
  };
}
function moduleSource(path) { return readText(path).replace(/^import .*\n/mg, '').replace(/^export /mg, ''); }
function timeoutFor(time) {
  return new Function('setTimeout', 'clearTimeout', moduleSource('web/async-operation.js') + '\nreturn withTimeout;')(time.setTimeout, time.clearTimeout);
}
function probes(time, modes) {
  const encoders = [], frames = [], checks = [];
  class Encoder {
    static isConfigSupported(config) {
      const format = config.codec === 'vp8' ? 'webm' : 'mp4'; checks.push(format);
      return modes[format] === 'support-hang' ? new Promise(() => {}) : Promise.resolve({supported: true});
    }
    constructor(callbacks) { this.callbacks = callbacks; this.state = 'unconfigured'; encoders.push(this); }
    configure(config) { this.format = config.codec === 'vp8' ? 'webm' : 'mp4'; this.state = 'configured'; }
    encode() { if (modes[this.format] !== 'flush-hang') this.callbacks.output(); }
    flush() { return modes[this.format] === 'flush-hang' ? new Promise(() => {}) : Promise.resolve(); }
    close() { this.state = 'closed'; }
  }
  class Frame { constructor() { frames.push(this); } close() { this.closed = true; } }
  const availableFormats = new Function('VideoEncoder', 'VideoFrame', 'withTimeout', 'console',
    moduleSource('web/video-export.js') + '\nreturn availableFormats;')(Encoder, Frame, timeoutFor(time), {warn() {}});
  return {availableFormats, encoders, frames, checks};
}
function app(time, modes = {}) {
  const nodes = new Map(), workers = [], audios = [], messages = [];
  function node(id) {
    if (!nodes.has(id)) nodes.set(id, {
      value: '', checked: false, disabled: ['export', 'play', 'position'].includes(id), type: '', textContent: '',
      classList: {toggle() {}}, options: [], addEventListener() {}, setAttribute() {}, removeAttribute() {},
      load() {}, checkValidity() { return true; }, querySelectorAll() { return []; },
      replaceChildren(...children) { this.options = children; this.value = children[0]?.value || ''; },
      append(child) { this.options.push(child); }, getContext() { return {putImageData() {}}; }
    });
    return nodes.get(id);
  }
  const values = {duration: '9', fps: '60', blank: '.1', hold: '1', easing: '0', 'box-mode': '0', threshold: '20', background: '#ffffff', position: '0', x0: '0', y0: '0', x1: '1', y1: '1'};
  for (const [id, value] of Object.entries(values)) node(id).value = value;
  node('sound').checked = modes.sound !== false; node('sound').type = 'checkbox'; node('auto-background').checked = true;
  const profile = {revealStart: .878, revealEnd: 14.3, duration: 18.044};
  class Worker {
    constructor() { workers.push(this); }
    postMessage(data) {
      messages.push(data.type);
      if (modes.throwPost) throw new Error('postMessage failed');
      if (data.type === modes.hang) return;
      let result;
      if (data.type === 'sound-profile') result = {profile};
      else if (data.type === 'preview') result = {width: 2, height: 2, rgba: new ArrayBuffer(16)};
      else result = {count: 1200, duration: 20, revealDuration: 13.4, revealEnd: 14.3, blankDuration: .9, box: [0, 0, 2, 2], formats: modes.formats || ['mp4']};
      Promise.resolve().then(() => this.onmessage({data: {id: data.id, type: data.type, ...result}}));
    }
    terminate() { this.terminated = true; }
  }
  class Audio {
    constructor(src) { this.src = src; this.currentTime = 0; audios.push(this); }
    // Intentionally never emit loadeddata, canplay, or error during preload.
    load() {}
    play() { assert(modes.gesture, 'Audio.play() lost the click gesture'); this.played = true; return Promise.resolve(); }
    pause() {}
  }
  const document = {getElementById: node, createElement: () => node('option'), addEventListener() {}};
  const text = readText('web/app.js').replace(/^import .*\n/mg, '').replace(/import\.meta/g, '({url: "https://example.test/releases/test/app.js"})');
  const names = ['document', 'window', 'navigator', 'localStorage', 'Worker', 'Audio', 'URL', 'ImageData', 'applyTranslations', 't', 'number', 'errorMessage', 'readImage', 'loadSoundtrack', 'createPreviewClock', 'setTimeout', 'clearTimeout'];
  const valuesForApp = [document, {addEventListener() {}}, {}, {getItem() { return null; }, setItem() {}}, Worker, Audio,
    class URL { constructor(path, base) { this.href = base.slice(0, base.lastIndexOf('/') + 1) + path; } static createObjectURL() { return 'blob:audio'; } },
    class ImageData {}, () => {}, key => key, String, error => error.message,
    async () => ({rgba: new Uint8Array(16), width: 2, height: 2, originalWidth: 2, originalHeight: 2}),
    async () => ({buffer: new ArrayBuffer(1)}), () => () => 100, time.setTimeout, time.clearTimeout];
  const api = new Function(...names, text + '\nreturn {importFile, request, get importing() {return importing;}, get pending() {return pending.size;}};')(...valuesForApp);
  return {api, node, workers, audios, messages};
}
async function checks() {
  for (const mode of ['support-hang', 'flush-hang']) {
    const time = clock(), test = probes(time, {mp4: mode});
    let result;
    test.availableFormats(2, 2, 60).then(value => result = value);
    await drain(); assert(result === undefined, 'Stalled probe unexpectedly completed');
    await time.advance(5001);
    assert(JSON.stringify(result) === '["webm"]', `${mode} blocked the next format and image preview`);
    assert(test.encoders.every(encoder => encoder.state === 'closed'), 'Timed-out encoder leaked');
    assert(test.frames.every(frame => frame.closed), 'Probe frame leaked');
    assert(time.pending === 0, 'Probe timeout leaked');
  }
  {
    const time = clock(), test = probes(time, {mp4: 'flush-hang', webm: 'flush-hang'});
    let result; test.availableFormats(2, 2, 60).then(value => result = value);
    await drain(); await time.advance(5001); await time.advance(5001);
    assert(result?.length === 0, 'Two stalled codecs prevented preview-only operation');
    assert(test.encoders.every(encoder => encoder.state === 'closed'), 'Unavailable codecs leaked');
    const normal = probes(time, {});
    assert(JSON.stringify(await normal.availableFormats(2, 2, 60)) === '["mp4","webm"]', 'Working codecs changed');
    assert(JSON.stringify(await normal.availableFormats(2, 2, 60, true)) === '["mp4"]', 'Sound offered WebM');
  }
  {
    const time = clock(); let finish, closed = 0;
    const image = {width: 2, height: 2, close() { closed++; }};
    const document = {createElement() { return {getContext() { return {drawImage() {}, getImageData() { return {data: new Uint8ClampedArray(16)}; }}; }}; }};
    let decode = () => new Promise(resolve => finish = resolve);
    const {readImage} = new Function('createImageBitmap', 'document', 'withTimeout', moduleSource('web/image-import.js') + '\nreturn {readImage};')(() => decode(), document, timeoutFor(time));
    let error; readImage({}).catch(value => error = value);
    await time.advance(30001);
    assert(error?.message === 'error.imageTimeout', 'Hung image decode never released the import');
    finish(image); await drain(); assert(closed === 1, 'Late bitmap leaked after timeout');
    decode = () => Promise.resolve(image);
    assert((await readImage({})).width === 2 && closed === 2, 'Decode could not recover');
    assert(time.pending === 0, 'Image timeout leaked');
  }
  const file = {name: 'same.png'};
  for (const hang of ['sound-profile', 'load', 'preview']) {
    const time = clock(), modes = {hang, sound: false}, test = app(time, modes);
    let finished = false; test.api.importFile(file).then(() => finished = true);
    await drain(); assert(test.api.importing && !finished, `${hang}: import did not stall`);
    await time.advance(60001);
    assert(finished && !test.api.importing && test.api.pending === 0, `${hang}: import stayed locked`);
    assert(test.workers[0].terminated && test.node('export').disabled && test.node('play').disabled, `${hang}: dead worker remained usable`);
    assert(test.node('status').textContent === 'error.workerTimeout', `${hang}: timeout was hidden`);
    modes.hang = undefined;
    await test.api.importFile(file);
    assert(test.workers.length === 2 && !test.node('export').disabled && !test.node('play').disabled, `${hang}: same image could not recover without reloading`);
    assert(test.node('status').textContent === 'imageReady' && time.pending === 0, `${hang}: recovery left stale state`);
  }
  {
    const time = clock(), modes = {sound: true}, test = app(time, modes);
    let finished = false; test.api.importFile(file).then(() => finished = true); await drain();
    assert(finished && !test.api.importing && !test.node('export').disabled, 'Audio preload blocked image import');
    assert(test.audios.length === 0, 'Import unnecessarily started an audio player');
    modes.gesture = true; const playback = test.node('play').onclick(); modes.gesture = false;
    assert(test.audios.length === 1 && test.audios[0].played, 'Play was deferred outside the user gesture');
    await playback;
    test.workers[0].onerror();
    await test.api.importFile(file);
    assert(test.workers.length === 2 && !test.node('export').disabled, 'Worker error prevented retry');
    modes.throwPost = true;
    await test.api.request('preview').catch(() => {});
    assert(test.api.pending === 0 && time.pending === 0, 'Failed postMessage leaked a pending request');
  }
  {
    const time = clock(), test = app(time, {formats: []});
    await test.api.importFile(file);
    assert(test.node('export').disabled && !test.node('play').disabled, 'Missing encoder disabled image preview');
    assert(test.node('status').textContent === 'encoderHint', 'Missing encoder status was overwritten');
  }
  report('Import lifecycle: stalled encoder support/flush, late bitmap cleanup, silent worker loss/retry, audio without loadeddata and preview without encoders passed.');
}
var testDone = false;
checks().then(() => { testDone = true; }).catch(error => { report(error.message + '\n' + (error.stack || '')); });
