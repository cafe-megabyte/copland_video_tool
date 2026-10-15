import {createEngine} from './wasm-loader.js';
import {availableFormats, fittedVideoSize, exportVideo} from './video-export.js';
const ready = createEngine(); let cancelled = false, running = false, engine, importProbe;
self.onmessage = async ({data}) => {
  if (data.type === 'cancel') { cancelled = true; return; }
  const id = data.id;
  try {
    engine ||= await ready;
    if (data.type === 'sound-profile') {
      self.postMessage({id, type: 'sound-profile', profile: engine.soundProfile});
    } else if (data.type === 'fit-image') {
      if (running) throw new Error('error.exportRunning');
      const size = await fittedVideoSize(data.width, data.height, data.fps, data.sound);
      importProbe = {...size, width: size.width + size.width % 2, height: size.height + size.height % 2, fps: data.fps, sound: !!data.sound};
      self.postMessage({id, type: 'image-size', ...size});
    } else if (data.type === 'load') {
      if (running) throw new Error('error.exportRunning');
      engine.load(new Uint8Array(data.rgba), data.width, data.height);
      const details = engine.prepare(data.options);
      const probe = importProbe; importProbe = undefined;
      const formats = probe && probe.width === details.width && probe.height === details.height && probe.fps === data.options.fps && probe.sound === !!data.options.sound
        ? probe.formats : await availableFormats(details.width, details.height, data.options.fps, data.options.sound);
      self.postMessage({id, type: 'loaded', ...details, formats});
    } else if (data.type === 'prepare') {
      if (running) throw new Error('error.exportRunning');
      const details = engine.prepare(data.options);
      self.postMessage({id, type: 'prepared', ...details, formats: await availableFormats(details.width, details.height, data.options.fps, data.options.sound)});
    } else if (data.type === 'preview') {
      if (running) return;
      const rgba = engine.render(data.index).slice().buffer;
      self.postMessage({id, type: 'preview', width: engine.width, height: engine.height, rgba}, [rgba]);
    } else if (data.type === 'export') {
      if (running) throw new Error('error.exportRunning');
      const details = engine.prepare(data.options);
      if (details.count > 18000 || details.count / data.options.fps > 600) throw new Error('error.durationLimit');
      running = true; cancelled = false;
      try {
        const blob = await exportVideo(engine, data.format,
          (done, total) => self.postMessage({id, type: 'progress', done, total}), () => cancelled);
        self.postMessage({id, type: 'complete', blob, format: data.format});
      } finally { running = false; }
    }
  } catch (error) { self.postMessage({id, type: 'error', message: error.message, aborted: error.name === 'AbortError'}); }
};
