import {applyTranslations, t, number, errorMessage} from './i18n.js';
applyTranslations(document);
const $ = id => document.getElementById(id);
const fields = ['duration', 'fps', 'blank', 'hold', 'start-size', 'easing', 'box-mode', 'threshold', 'background', 'auto-background', 'keyframes'];
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
}
function request(type, data = {}, transfer = []) {
  const id = ++nextId; return new Promise((resolve, reject) => { pending.set(id, {resolve, reject}); worker.postMessage({id, type, ...data}, transfer); });
}
function options() {
  if (!$('settings').checkValidity()) throw new Error('error.settings');
  const keyframes = $('keyframes').value.trim() ? $('keyframes').value.trim().split(',').map(part => {
    const pair = part.trim().split(':');
    if (pair.length !== 2 || !pair.every(s => s.trim() && Number.isFinite(Number(s)))) throw new Error('error.keyframeSyntax');
    return {time: Number(pair[0]), size: Number(pair[1])};
  }) : [];
  if (keyframes.length > 256) throw new Error('error.keyframeCount');
  return {duration: Number($('duration').value), fps: Number($('fps').value), blank: Number($('blank').value), hold: Number($('hold').value),
    startSize: Number($('start-size').value) || 0, easing: Number($('easing').value), boxMode: Number($('box-mode').value),
    box: ['x0', 'y0', 'x1', 'y1'].map(id => Number($(id).value)), threshold: Number($('threshold').value),
    background: $('auto-background').checked ? -1 : parseInt($('background').value.slice(1), 16), keyframes};
}
function saveSettings() {
  try { localStorage.setItem('copland-settings-v1', JSON.stringify(Object.fromEntries(fields.map(id => [id, $(id).type === 'checkbox' ? $(id).checked : $(id).value])))); } catch { /* Storage may be unavailable. */ }
}
function restoreSettings() {
  try { const saved = JSON.parse(localStorage.getItem('copland-settings-v1') || '{}'); for (const id of fields) if (id in saved) { if ($(id).type === 'checkbox') $(id).checked = !!saved[id]; else $(id).value = saved[id]; } } catch { /* Defaults remain usable. */ }
}
function updateFields() {
  $('background').disabled = busy || $('auto-background').checked;
  $('box-fields').hidden = $('box-mode').value !== '2'; $('threshold-field').hidden = $('box-mode').value !== '1';
  for (const field of $('box-fields').querySelectorAll('input')) field.disabled = busy || $('box-mode').value !== '2';
  $('threshold').disabled = busy || $('box-mode').value !== '1';
  $('preview').classList.toggle('selecting', $('box-mode').value === '2');
}
function updatePrepared(data) {
  prepared = true; count = data.count; $('position').max = count - 1; $('position').disabled = false;
  $('position').value = Math.min(Number($('position').value), count - 1); $('play').disabled = false;
  const chosen = $('format').value;
  $('format').replaceChildren(...data.formats.map(f => { const o = document.createElement('option'); o.value = f; o.textContent = f === 'mp4' ? 'MP4 · H.264' : 'WebM · VP8'; return o; }));
  if (data.formats.includes(chosen)) $('format').value = chosen;
  if (!data.formats.length) { const option = document.createElement('option'); option.textContent = t('noEncoder'); $('format').append(option); }
  $('format').disabled = busy || !data.formats.length; $('export').disabled = busy || !data.formats.length;
  $('summary').textContent = t('summary', {count: number(count), seconds: number(count / Number($('fps').value), {maximumFractionDigits: 3})});
  $('preview-hint').textContent = $('box-mode').value === '1' ? t('detectedRegion', {box: data.box.join(', '), hint: t('previewHint')}) : t('previewHint');
  if (!data.formats.length) status(t('encoderHint'), true);
}
async function prepare() {
  if (!source || busy || importing) return;
  prepared = false; $('export').disabled = true; stopPlayback();
  const revision = ++prepareRevision;
  try { const data = await request('prepare', {options: options()}); if (revision !== prepareRevision) return; updatePrepared(data); await preview(); if (revision === prepareRevision && data.formats.length) status(t('imageReady')); saveSettings(); }
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
    const bitmap = await createImageBitmap(file);
    const width = bitmap.width, height = bitmap.height;
    if (width > 4096 || height > 4096 || width * height > 8388608) { bitmap.close(); throw new Error('error.imageSize'); }
    const canvas = document.createElement('canvas'); canvas.width = width; canvas.height = height;
    const ctx = canvas.getContext('2d', {willReadFrequently: true, colorSpace: 'srgb'}); ctx.drawImage(bitmap, 0, 0); bitmap.close();
    const rgba = new Uint8Array(ctx.getImageData(0, 0, width, height).data.buffer);
    source = {rgba, width, height, name: file.name.replace(/\.[^.]+$/, '') || 'Copland Video Tool'};
    $('x0').value = $('y0').value = 0; $('x1').value = width; $('y1').value = height;
    $('empty').hidden = true; $('preview').hidden = false;
    $('image-info').textContent = `${file.name} · ${width} × ${height}`; $('position').value = 0;
    if (resultURL) URL.revokeObjectURL(resultURL);
    resultURL = undefined; resultBlob = undefined; $('result').hidden = true;
    $('video').removeAttribute('src'); $('video').load();
    await loadSource();
    await preview(); if (!$('export').disabled) status(t('imageReady'));
  } catch (error) { prepared = false; $('export').disabled = true; status(errorMessage(error), true); }
  finally { importing = false; }
}
async function loadSource() {
  const rgba = source.rgba.slice().buffer;
  const data = await request('load', {rgba, width: source.width, height: source.height, options: options()}, [rgba]); updatePrepared(data);
}
function stopPlayback() { playing = false; $('play').textContent = '▶'; $('play').setAttribute('aria-label', t('play')); }
async function play() {
  if (playing) { stopPlayback(); return; } if (!prepared || busy) return;
  playing = true; $('play').textContent = 'Ⅱ'; $('play').setAttribute('aria-label', t('pause'));
  if (Number($('position').value) >= count - 1) $('position').value = 0;
  const initial = Number($('position').value), started = performance.now(), fps = Number($('fps').value);
  while (playing && !busy) {
    const index = Math.min(count - 1, initial + Math.floor((performance.now() - started) * fps / 1000));
    $('position').value = index;
    try { await preview(); } catch (error) { status(errorMessage(error), true); stopPlayback(); break; }
    if (index === count - 1) { stopPlayback(); break; }
    await new Promise(resolve => setTimeout(resolve, 33));
  }
}
function setBusy(value) {
  busy = value;
  for (const input of $('settings').querySelectorAll('input, select, textarea, button')) input.disabled = value;
  $('cancel').disabled = false; $('reset').disabled = value;
  $('replace').disabled = value; $('play').disabled = value || !prepared; $('position').disabled = value || !prepared;
  $('progress-area').hidden = !value; $('export').disabled = value || !prepared || !['mp4', 'webm'].includes($('format').value);
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
$('play').onclick = play; $('position').oninput = () => { stopPlayback(); preview().catch(error => status(errorMessage(error), true)); };
$('image-file').onchange = event => { const file = event.target.files[0]; event.target.value = ''; importFile(file); };
$('replace').onclick = () => $('image-file').click();
$('drop-zone').onclick = () => { if (!$('empty').hidden && !busy) $('image-file').click(); };
$('drop-zone').onkeydown = event => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); if (!busy) $('image-file').click(); } };
for (const name of ['dragenter', 'dragover']) $('drop-zone').addEventListener(name, e => { e.preventDefault(); $('drop-zone').classList.add('drag-over'); });
for (const name of ['dragleave', 'drop']) $('drop-zone').addEventListener(name, e => { e.preventDefault(); $('drop-zone').classList.remove('drag-over'); if (name === 'drop') importFile(e.dataTransfer.files[0]); });
$('settings').addEventListener('input', event => {
  if (event.target.id === 'format') return;
  updateFields(); prepareRevision++; prepared = false; $('export').disabled = true; clearTimeout(debounce); debounce = setTimeout(prepare, 300);
});
$('reset').onclick = () => { HTMLFormElement.prototype.reset.call($('settings')); if (source) { $('x1').value = source.width; $('y1').value = source.height; } updateFields(); prepare(); saveSettings(); };
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
