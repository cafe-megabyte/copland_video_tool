// Test device-specific limits through both capability reports and real encode outcomes.
function assert(value, message) { if (!value) throw new Error(message); }
const source = readText('web/video-export.js').replace(/^import .*\n/mg, '').replace(/^export /mg, '');
function device(supports, reportsSupport = supports) {
  const checks = [], encoded = [], frames = [], encoders = [];
  class Encoder {
    static async isConfigSupported(config) { checks.push(config); return {supported: reportsSupport(config)}; }
    constructor(callbacks) { this.callbacks = callbacks; this.state = 'unconfigured'; encoders.push(this); }
    configure(config) { this.config = config; this.state = 'configured'; }
    encode(frame) {
      encoded.push(this.config);
      if (supports(this.config)) this.callbacks.output();
      else this.callbacks.error(new Error('Device rejected this size'));
    }
    async flush() {}
    close() { this.state = 'closed'; }
  }
  class Frame {
    constructor(data, options) {
      assert(data.length === options.codedWidth * options.codedHeight * 4, 'Wrong probe buffer size');
      frames.push(this);
    }
    close() { this.closed = true; }
  }
  const api = new Function('VideoEncoder', 'VideoFrame', 'withTimeout', source + '\nreturn {fittedVideoSize};')(Encoder, Frame, operation => operation);
  return {...api, checks, encoded, clean() {
    assert(encoders.every(encoder => encoder.state === 'closed'), 'Encoder leaked after sizing');
    assert(frames.every(frame => frame.closed), 'Probe frame leaked after sizing');
  }};
}
async function checks() {
  {
    const test = device(() => true), size = await test.fittedVideoSize(4096, 2160, 60);
    assert(size.width === 4096 && size.height === 2160 && size.formats.join() === 'mp4,webm', 'Supported 4K image changed');
    assert(test.checks.length === 2 && test.encoded.length === 2, 'Supported size was not test-encoded once per format');
    test.clean();
  }
  for (const [width, height, targetWidth, targetHeight] of [[3840,2160,1920,1080], [2160,3840,1080,1920], [3000,3000,1080,1080], [1921,1081,1920,1080]]) {
    const test = device(c => c.width <= targetWidth && c.height <= targetHeight);
    const size = await test.fittedVideoSize(width, height, 60);
    assert(size.width === targetWidth && size.height === targetHeight, `Did not reach device limit for ${width} x ${height}: ${size.width} x ${size.height}`);
    assert(test.checks.every(c => !(c.width % 2) && !(c.height % 2) && c.framerate === 60), 'Wrong video dimensions or frame rate probed');
    test.clean();
  }
  {
    let limit = 1920;
    const test = device(c => c.width <= (c.framerate <= 30 ? 3840 : limit));
    const low = await test.fittedVideoSize(3840, 2160, 30, true);
    const high = await test.fittedVideoSize(3840, 2160, 60, true);
    assert(low.width === 3840 && high.width === 1920, 'Current frame rate ignored');
    limit = 2560;
    const next = await test.fittedVideoSize(3840, 2160, 60, true);
    assert(next.width === 2560 && next.height === 1440, 'Device limit cached across imports');
    assert(test.checks.every(c => c.codec.startsWith('avc1.')), 'Sound mode probed a silent-only codec');
    test.clean();
  }
  {
    const test = device(c => c.codec === 'vp8' || c.width <= 1920);
    const silent = await test.fittedVideoSize(3840, 2160, 60);
    const sound = await test.fittedVideoSize(3840, 2160, 60, true);
    assert(silent.width === 3840 && silent.formats.join() === 'webm', 'Usable full-size silent encoder ignored');
    assert(sound.width === 1920 && sound.height === 1080 && sound.formats.join() === 'mp4', 'Sound did not fit the MP4 encoder');
    test.clean();
  }
  {
    const test = device(c => c.width <= 1280 && c.height <= 720, () => true);
    const size = await test.fittedVideoSize(3840, 2160, 29.97, true);
    assert(size.width === 1280 && size.height === 720 && size.formats.join() === 'mp4', 'Capability report trusted despite failed test encode');
    test.clean();
  }
  {
    const test = device(c => c.width <= 1920 && c.height <= 1080);
    const size = await test.fittedVideoSize(1919, 1079, 60);
    assert(size.width === 1919 && size.height === 1079, 'Supported odd source dimensions changed');
    assert(test.checks.every(c => c.width === 1920 && c.height === 1080), 'Padding ignored during probe');
    test.clean();
  }
  {
    const test = device(() => false), size = await test.fittedVideoSize(4096, 2160, 120);
    assert(size.width === 4096 && size.height === 2160 && !size.formats.length, 'Missing codecs shrank the preview');
    assert(test.checks.length <= 26 && !test.encoded.length, 'Unavailable codecs caused an unbounded search');
    test.clean();
    const {fittedVideoSize} = new Function('VideoEncoder', 'VideoFrame', source + '\nreturn {fittedVideoSize};')(undefined, undefined);
    assert((await fittedVideoSize(4096,2160,60)).width === 4096, 'Missing WebCodecs changed preview dimensions');
  }
  report('Video sizing: encoder limits, landscape/portrait/square, even padding, frame rate, sound, failed test encoding, fresh imports and preview without codecs passed.');
}
var testDone = false;
checks().then(() => { testDone = true; }).catch(error => report(error.message + '\n' + (error.stack || '')));
