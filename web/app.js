import {loadSoundtrack} from './m4a-reader.js';
import {createPreviewClock} from './preview-clock.js';
import {readImage} from './image-import.js';
import {applyTranslations, t, number, errorMessage} from './i18n.js';
applyTranslations(document);
const $ = id => document.getElementById(id);
const fields = ['sound', 'duration', 'fps', 'blank', 'hold', 'start-size', 'easing', 'box-mode', 'threshold', 'background', 'auto-background', 'keyframes'];
const timingFields = ['duration', 'blank', 'hold', 'keyframes'];
let manualTiming, soundBlank, soundHold, soundProfile, profileReady, preferredFormat = 'mp4', soundAudio, soundLoading, playbackRevision = 0, playbackDuration = 0;
let worker, source, count = 0, busy = false, importing = false, playing = false, prepared = false, nextId = 0, pending = new Map(), debounce, prepareRevision = 0, previewToken = 0, resultURL, resultBlob, resultName, deferredInstall, swRegistration;
function status(message, error = false) { $('status').textContent = message; $('status').classList.toggle('error', error); }
function startWorker() {
  worker = new Worker(new URL('./engine-worker.js', import.meta.url), {type: 'module'});
  worker.onmessage = ({data}) => {
    if (data.type === 'progress') {
      $('progress').value = data.done / data.total * 100;
      $('progress-text').textContent = t('progress', {done: number(data.done), total: number(data.total)}); return;
    }
    const job = pending.get(data.id); if (!job) return;
    pending.delete(data.id);
    data.type === 'error' ? job.reject(new Error(data.message)) : job.resolve(data);
  };
  worker.onerror = () => { for (const job of pending.values()) job.reject(new Error('error.worker')); pending.clear(); };
  profileReady = request('sound-profile').then(data => { soundProfile = data.profile; updateFields(); });
  profileReady.catch(error => status(errorMessage(error), true));
}
function request(type, data = {}, transfer = []) {
  const id = ++nextId; return new Promise((resolve, reject) => { pending.set(id, {resolve, reject}); worker.postMessage({id, type, ...data}, transfer); });
}
function options() {
  if (!$('settings').checkValidity()) throw new Error('error.settings');
  const keyframes = !$('sound').checked && $('keyframes').value.trim() ? $('keyframes').value.trim().split(',').map(part => {
    const pair = part.trim().split(':');
    if (pair.length !== 2 || !pair.every(s => s.trim() && Number.isFinite(Number(s)))) throw new Error('error.keyframeSyntax');
    return {time: Number(pair[0]), size: Number(pair[1])};
  }) : [];
  if (keyframes.length > 256) throw new Error('error.keyframeCount');
  return {sound: $('sound').checked, duration: Number($('duration').value), fps: Number($('fps').value), blank: Number($('blank').value), hold: $('sound').checked && soundHold === undefined ? 0 : Number($('hold').value),
    startSize: Number($('start-size').value) || 0, easing: Number($('easing').value), boxMode: Number($('box-mode').value),
    box: ['x0', 'y0', 'x1', 'y1'].map(id => Number($(id).value)), threshold: Number($('threshold').value),
    background: $('auto-background').checked ? -1 : parseInt($('background').value.slice(1), 16), keyframes};
}
function saveSettings() {
  try { localStorage.setItem('copland-settings-v1', JSON.stringify(Object.fromEntries([...fields.map(id => [id, $(id).type === 'checkbox' ? $(id).checked : (manualTiming && id in manualTiming ? manualTiming[id] : $(id).value)]), ['format', preferredFormat], ['soundBlank', soundBlank], ['soundHold', soundHold]]))); } catch { /* Storage may be unavailable. */ }
}
function restoreSettings() {
  try { const saved = JSON.parse(localStorage.getItem('copland-settings-v1') || '{}'); preferredFormat = saved.format === 'webm' ? 'webm' : 'mp4'; if (saved.soundBlank !== '' && saved.soundBlank != null && Number.isFinite(Number(saved.soundBlank)) && Number(saved.soundBlank) >= 0) soundBlank = String(saved.soundBlank); if (saved.soundHold !== '' && saved.soundHold != null && Number.isFinite(Number(saved.soundHold)) && Number(saved.soundHold) >= 0) soundHold = String(saved.soundHold); for (const id of fields) if (id in saved) { if ($(id).type === 'checkbox') $(id).checked = !!saved[id]; else $(id).value = saved[id]; } } catch { /* Defaults remain usable. */ }
}
function updateFields() {
  const sound = $('sound').checked;
  if (sound && !manualTiming) {
    manualTiming = Object.fromEntries(timingFields.map(id => [id, $(id).value]));
    for (const id of timingFields) $(id).value = '';
  } else if (!sound && manualTiming) {
    for (const id of timingFields) $(id).value = manualTiming[id];
    manualTiming = undefined;
  }
  for (const id of timingFields) $(id).disabled = busy || (sound && ['duration', 'keyframes'].includes(id));
  if (sound) $('blank').value = soundBlank ?? soundProfile?.revealStart ?? '';
  if (sound) $('hold').value = soundHold ?? (soundProfile ? Math.max(0, soundProfile.duration - soundProfile.revealEnd).toFixed(3) : '');
  $('blank').disabled = busy || (sound && !soundProfile);
  $('hold').disabled = busy || (sound && !soundProfile);
  $('blank').max = sound && soundProfile ? soundProfile.revealEnd : 600;
  $('sound-hint').hidden = !sound;
  $('format').disabled = busy || sound || !['mp4', 'webm'].includes($('format').value);

  $('background').disabled = busy || $('auto-background').checked;
  $('box-fields').hidden = $('box-mode').value !== '2'; $('threshold-field').hidden = $('box-mode').value !== '1';
  for (const field of $('box-fields').querySelectorAll('input')) field.disabled = busy || $('box-mode').value !== '2';
  $('threshold').disabled = busy || $('box-mode').value !== '1';
  $('preview').classList.toggle('selecting', $('box-mode').value === '2');
}
function updatePrepared(data) {
  prepared = true; count = data.count; playbackDuration = data.duration; $('position').max = count - 1; $('position').disabled = false;
  $('position').value = Math.min(Number($('position').value), count - 1); $('play').disabled = false;
  const chosen = $('sound').checked ? 'mp4' : preferredFormat;
  $('format').replaceChildren(...data.formats.map(f => { const o = document.createElement('option'); o.value = f; o.textContent = f === 'mp4' ? 'MP4 · H.264' : 'WebM · VP8'; return o; }));
  if (data.formats.includes(chosen)) $('format').value = chosen;
  if (!data.formats.length) { const option = document.createElement('option'); option.textContent = t('noEncoder'); $('format').append(option); }
  $('format').disabled = busy || !data.formats.length || $('sound').checked; $('export').disabled = busy || !data.formats.length;
  $('summary').textContent = t('summary', {count: number(count), seconds: number(data.duration, {maximumFractionDigits: 3})});
  if ($('sound').checked) {
    $('duration').value = data.revealDuration.toFixed(3);
    if (soundHold === undefined) $('hold').value = Math.max(0, soundProfile.duration - data.revealEnd).toFixed(3);
    $('sound-hint').textContent = t('soundTiming', {start: number(data.blankDuration, {maximumFractionDigits: 3}), cue: number(data.revealEnd, {maximumFractionDigits: 3}), seconds: number(soundProfile.duration, {maximumFractionDigits: 3}), end: number(data.duration, {maximumFractionDigits: 3})});
  }
  $('preview-hint').textContent = $('box-mode').value === '1' ? t('detectedRegion', {box: data.box.join(', '), hint: t('previewHint')}) : t('previewHint');
  if (!data.formats.length) status(t('encoderHint'), true);
}
async function prepare() {
  if (!source || busy || importing) return;
  prepared = false; $('export').disabled = true; stopPlayback();
  const revision = ++prepareRevision;
  try { await profileReady; const o = options(); if (o.sound) await ensureSound(); const data = await request('prepare', {options: o}); if (revision !== prepareRevision) return; updatePrepared(data); await preview(); if (revision === prepareRevision && data.formats.length) status(t('imageReady')); saveSettings(); }
  catch (error) { if (revision === prepareRevision) status(errorMessage(error), true); }
}
async function preview() {
  if (!source || !prepared || busy) return;
  const token = ++previewToken, index = Number($('position').value);
  const data = await request('preview', {index}); if (token !== previewToken || busy) return;
  const canvas = $('preview'); canvas.width = data.width; canvas.height = data.height;
  canvas.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(data.rgba), data.width, data.height), 0, 0);
  $('time').value = `${number(index / Number($('fps').value), {minimumFractionDigits: 2, maximumFractionDigits: 2})} s`;
}
async function importFile(file) {
  if (!file || busy || importing) return;
  importing = true; prepareRevision++; clearTimeout(debounce); prepared = false; $('export').disabled = true;
  stopPlayback(); status(t('openingImage'));
  try {
    options();
    const {rgba, width, height, originalWidth, originalHeight} = await readImage(file);
    source = {rgba, width, height, name: file.name.replace(/\.[^.]+$/, '') || 'Copland Video Tool'};
    $('x0').value = $('y0').value = 0; $('x1').value = width; $('y1').value = height;
    $('empty').hidden = true; $('preview').hidden = false;
    const size = `${width} × ${height}`;
    $('image-info').textContent = `${file.name} · ` + (width !== originalWidth || height !== originalHeight
      ? t('imageResized', {original: `${originalWidth} × ${originalHeight}`, size}) : size);
    $('position').value = 0;
    if (resultURL) URL.revokeObjectURL(resultURL);
    resultURL = undefined; resultBlob = undefined; $('result').hidden = true;
    $('video').removeAttribute('src'); $('video').load();
    await loadSource();
    await preview(); if (!$('export').disabled) status(t('imageReady'));
  } catch (error) { prepared = false; $('export').disabled = true; status(errorMessage(error), true); }
  finally { importing = false; }
}
async function loadSource() {
  await profileReady;
  const rgba = source.rgba.slice().buffer;
  const o = options(); if (o.sound) await ensureSound();
  const data = await request('load', {rgba, width: source.width, height: source.height, options: o}, [rgba]); updatePrepared(data);
}
function ensureSound() {
  if (soundAudio) return Promise.resolve();
  if (soundLoading) return soundLoading;
  soundLoading = prepareSoundAudio().finally(() => { soundLoading = undefined; });
  return soundLoading;
}
async function prepareSoundAudio() {
  const {buffer} = await loadSoundtrack();
  const url = URL.createObjectURL(new Blob([buffer], {type: 'audio/mp4'}));
  const audio = new Audio(); audio.preload = 'auto';
  try {
    await new Promise((resolve, reject) => {
      audio.onloadeddata = resolve; audio.onerror = () => reject(new Error('error.soundPlayback'));
      audio.src = url; audio.load();
    });
    soundAudio = audio;
    audio.onerror = () => { stopPlayback(); status(t('error.soundPlayback'), true); };
  } catch (error) { URL.revokeObjectURL(url); throw error; }
}
function stopPlayback() {
  playing = false; playbackRevision++; previewToken++; soundAudio?.pause();
  $('play').textContent = '▶'; $('play').setAttribute('aria-label', t('play'));
}
async function play() {
  if (playing) { stopPlayback(); return; } if (!prepared || busy) return;
  playing = true; const revision = ++playbackRevision;
  $('play').textContent = 'Ⅱ'; $('play').setAttribute('aria-label', t('pause'));
  if (Number($('position').value) >= count - 1) $('position').value = 0;
  const initial = Number($('position').value), fps = Number($('fps').value), start = initial / fps;
  const audio = $('sound').checked ? soundAudio : null;
  try {
    if ($('sound').checked && !audio) throw new Error('error.soundPlayback');
    if (audio) {
      audio.currentTime = Math.min(start, soundProfile.duration);
      if (start < soundProfile.duration) await audio.play(); else audio.pause();
    }
    const time = createPreviewClock(audio, start, soundProfile?.duration || 0);
    // A pending play() can resolve after a pause or an option change.
    if (revision !== playbackRevision) { if (!playing) audio?.pause(); return; }
    while (playing && !busy && revision === playbackRevision) {
      const seconds = time(), index = Math.min(count - 1, Math.floor(seconds * fps));
      $('position').value = index;
      await preview();
      if (revision !== playbackRevision) break;
      if (seconds >= playbackDuration) { stopPlayback(); break; }
      await new Promise(resolve => setTimeout(resolve, 16));
    }
  } catch (error) {
    if (revision === playbackRevision) { stopPlayback(); status(audio ? t('error.soundPlayback') : errorMessage(error), true); }
  }
}
function setBusy(value) {
  busy = value;
  for (const input of $('settings').querySelectorAll('input, select, textarea, button')) input.disabled = value;
  $('cancel').disabled = false; $('reset').disabled = value;
  $('replace').disabled = value; $('play').disabled = value || !prepared; $('position').disabled = value || !prepared;
  $('progress-area').hidden = !value; $('export').disabled = value || !prepared || !['mp4', 'webm'].includes($('format').value);
  $('format').disabled = value || $('sound').checked || !$('format').options.length || !['mp4', 'webm'].includes($('format').value);
  updateFields();
}
async function cancelExport(message = t('cancelled')) {
  if (!busy) return;
  worker.terminate(); for (const job of pending.values()) job.reject(new DOMException(t('cancelled'), 'AbortError')); pending.clear();
  setBusy(false); startWorker(); status(message);
  try { await loadSource(); } catch (error) { status(errorMessage(error), true); }
}
$('settings').onsubmit = async event => {
  event.preventDefault(); if (!prepared || busy) return;
  try {
    const o = options(), format = $('format').value; stopPlayback(); setBusy(true); $('progress').value = 0; $('progress-text').textContent = t('preparing');
    status(t('exporting'));
    const data = await request('export', {options: o, format});
    resultBlob = data.blob; resultName = `${source.name}.${data.format}`;
    if (resultURL) URL.revokeObjectURL(resultURL); resultURL = URL.createObjectURL(resultBlob);
    $('video').src = resultURL; $('download').href = resultURL; $('download').download = resultName;
    $('result-info').textContent = `${data.format === 'mp4' ? 'MP4' : 'WebM'} · ${resultBlob.size < 1048576 ? number(Math.ceil(resultBlob.size / 1024)) + ' KB' : number(resultBlob.size / 1048576, {maximumFractionDigits: 1}) + ' MB'} · ${source.width + source.width % 2} × ${source.height + source.height % 2}`;
    $('result').hidden = false;
    const file = new File([resultBlob], resultName, {type: resultBlob.type}); $('share').hidden = !navigator.canShare?.({files: [file]});
    status(t('finished'));
  } catch (error) { if (error.name !== 'AbortError') status(errorMessage(error), true); }
  finally { setBusy(false); }
};
$('share').onclick = async () => { try { await navigator.share({files: [new File([resultBlob], resultName, {type: resultBlob.type})]}); } catch (error) { if (error.name !== 'AbortError') status(t('shareUnavailable'), true); } };
$('cancel').onclick = () => cancelExport();
$('play').onclick = play; $('position').oninput = () => { stopPlayback(); if (soundAudio && $('sound').checked) soundAudio.currentTime = Math.min(Number($('position').value) / Number($('fps').value), soundProfile.duration); preview().catch(error => status(errorMessage(error), true)); };
$('image-file').onchange = event => { const file = event.target.files[0]; event.target.value = ''; importFile(file); };
$('replace').onclick = () => $('image-file').click();
$('drop-zone').onclick = () => { if (!$('empty').hidden && !busy) $('image-file').click(); };
$('drop-zone').onkeydown = event => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); if (!busy) $('image-file').click(); } };
for (const name of ['dragenter', 'dragover']) $('drop-zone').addEventListener(name, e => { e.preventDefault(); $('drop-zone').classList.add('drag-over'); });
for (const name of ['dragleave', 'drop']) $('drop-zone').addEventListener(name, e => { e.preventDefault(); $('drop-zone').classList.remove('drag-over'); if (name === 'drop') importFile(e.dataTransfer.files[0]); });
$('settings').addEventListener('input', event => {
  if (event.target.id === 'format') { preferredFormat = $('format').value; saveSettings(); return; }
  stopPlayback();
  if (event.target.id === 'blank' && $('sound').checked) soundBlank = $('blank').value;
  if (event.target.id === 'hold' && $('sound').checked) soundHold = $('hold').value;
  updateFields(); saveSettings(); prepareRevision++; prepared = false; $('export').disabled = true; clearTimeout(debounce); debounce = setTimeout(prepare, 300);
});
$('reset').onclick = () => { stopPlayback(); manualTiming = undefined; soundBlank = undefined; soundHold = undefined; preferredFormat = 'mp4'; HTMLFormElement.prototype.reset.call($('settings')); if (source) { $('x1').value = source.width; $('y1').value = source.height; } updateFields(); prepare(); saveSettings(); };
let selectionStart;
function point(event) { const r = $('preview').getBoundingClientRect(); return [Math.max(0, Math.min(source.width, Math.floor((event.clientX - r.left) / r.width * ($('preview').width)))), Math.max(0, Math.min(source.height, Math.floor((event.clientY - r.top) / r.height * ($('preview').height))))]; }
$('preview').onpointerdown = event => { if (source && !busy && $('box-mode').value === '2') { stopPlayback(); selectionStart = point(event); $('preview').setPointerCapture(event.pointerId); } };
$('preview').onpointerup = event => {
  if (!selectionStart) return; const end = point(event), start = selectionStart; selectionStart = null;
  $('x0').value = Math.min(start[0], end[0]); $('y0').value = Math.min(start[1], end[1]);
  $('x1').value = Math.min(source.width, Math.max(start[0], end[0]) + 1); $('y1').value = Math.min(source.height, Math.max(start[1], end[1]) + 1); prepare();
};
$('preview').onpointercancel = () => selectionStart = null;
document.addEventListener('visibilitychange', () => { if (document.hidden) { stopPlayback(); if (busy) cancelExport(t('interrupted')); } });
window.addEventListener('beforeunload', event => { if (busy) { event.preventDefault(); event.returnValue = ''; } });
window.addEventListener('beforeinstallprompt', event => { event.preventDefault(); deferredInstall = event; $('install').hidden = false; });
$('install').onclick = async () => { if (deferredInstall) { await deferredInstall.prompt(); deferredInstall = null; } else $('install-help').showModal(); };
$('close-help').onclick = () => $('install-help').close();
$('update').onclick = () => { if (!busy && swRegistration?.waiting) swRegistration.waiting.postMessage({type: 'activate'}); };
async function offlineStatus() {
  if (!('serviceWorker' in navigator)) { $('offline-status').textContent = t('offlineUnavailable'); return; }
  try {
    const scopeURL = new URL('../../', import.meta.url);
    const wasControlled = !!navigator.serviceWorker.controller;
    swRegistration = await navigator.serviceWorker.register(new URL('service-worker.js', scopeURL), {scope: scopeURL.pathname});
    let refreshing = false;
    navigator.serviceWorker.addEventListener('controllerchange', () => { if (wasControlled && !refreshing && !busy && navigator.serviceWorker.controller) { refreshing = true; location.reload(); } });
    navigator.serviceWorker.addEventListener('message', ({data}) => { if (data?.type === 'offline-ready') $('offline-status').textContent = t('offlineReady'); });
    const updateState = () => { if (swRegistration.waiting && navigator.serviceWorker.controller) { $('update').hidden = false; $('offline-status').textContent = t('updateAvailable'); } };
    swRegistration.addEventListener('updatefound', () => swRegistration.installing?.addEventListener('statechange', updateState));
    await navigator.serviceWorker.ready; $('offline-status').textContent = t('offlineReady'); updateState();
    if (!matchMedia('(display-mode: standalone)').matches) $('install').hidden = false;
    navigator.storage?.persist?.().catch(() => {});
  } catch { $('offline-status').textContent = t('offlineNotReady'); }
}
restoreSettings(); updateFields(); startWorker(); offlineStatus();
