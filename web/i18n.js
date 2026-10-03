// Use the primary browser language; secondary preferences do not change it.
export function resolveLanguage(browserLanguage) {
  return /^de(?:[-_]|$)/i.test(browserLanguage || '') ? 'de' : 'en';
}
export const language = resolveLanguage(globalThis.navigator?.language);
export const messages = {
  en: {
    viewer: 'Image and animation preview', chooseOrDrop: 'Choose an image or drop it here',
    dropHint: 'Choose a PNG or JPEG, or drop an image here.', chooseImage: 'Choose image',
    previewLabel: 'Animation preview. Drag to select a region.', noImage: 'No image selected', replaceImage: 'Change image',
    play: 'Play preview', pause: 'Pause preview', position: 'Time position', previewHint: 'The preview shows the actual animation frames.',
    settings: 'Animation settings', animation: 'Animation', reset: 'Reset', duration: 'Duration', seconds: 'Seconds',
    fps: 'Frame rate', framesPerSecond: 'Frames / s', easing: 'Progression', linear: 'Linear with a gentle finish',
    geometric: 'Geometric', slowFast: 'Slow → fast', fastSlow: 'Fast → slow', blank: 'Lead-in', hold: 'Final frame',
    startSize: 'Starting size', startSizeUnit: 'Pixels · empty = automatic', automatic: 'Automatic', imageRegion: 'Image region',
    reveal: 'Reveal', wholeImage: 'The whole image', detectRegion: 'Detect the visible region automatically', selectRegion: 'Select a region',
    regionHint: 'Drag in the preview or enter image coordinates.', left: 'Left', top: 'Top', right: 'Right', bottom: 'Bottom',
    threshold: 'Background tolerance', autoBackground: 'Automatic background', background: 'Background colour',
    keyframes: 'Custom keyframes', keyframeLabel: 'Time : pixel size',
    keyframeHint: 'Start at 0 seconds and end at size 1. Times must increase; sizes may only decrease. Keyframes replace duration and progression.',
    video: 'Video', format: 'Format', chooseFirst: 'Choose an image first', createVideo: 'Create video', videoProgress: 'Video progress',
    preparing: 'Preparing …', cancel: 'Cancel', initialStatus: 'Choose an image to begin.', finishedVideo: 'Finished video', saveVideo: 'Save video', share: 'Share',
    offlinePreparing: 'Preparing offline package …', install: 'Install', update: 'Load update', installTitle: 'Add to Home Screen',
    installHint: 'Open your browser’s Share menu and choose “Add to Home Screen”. First wait for “Offline ready” to appear at the bottom.', understood: 'Got it',
    progress: '{done} of {total} frames', summary: '{count} frames · {seconds} s', detectedRegion: 'Detected region: {box}. {hint}',
    noEncoder: 'No suitable video encoder available', encoderHint: 'The preview works. This browser has no suitable video encoder for this image size and frame rate. Try another browser.',
    openingImage: 'Opening image …', imageReady: 'Image ready. Adjust the animation or create the video.',
    cancelled: 'Export cancelled. You can start it again.', exporting: 'Creating the video on your device. Please keep the app open.',
    finished: 'Done. Your video is ready to save.', shareUnavailable: 'Sharing is unavailable here. Use “Save video”.',
    interrupted: 'Export interrupted because the app was left. Restart it with the app open.', offlineUnavailable: 'Offline installation is unavailable in this browser.',
    offlineReady: 'Offline ready', updateAvailable: 'Offline ready · Update available', offlineNotReady: 'Offline package not ready yet. Please reopen online.',
    'error.worker': 'Processing could not start. Please reload the app.', 'error.settings': 'Please check the highlighted settings.',
    'error.keyframeSyntax': 'Enter keyframes as time:size.', 'error.keyframeCount': 'Up to 256 keyframes are supported.',
    'error.imageSize': 'Please choose an image with at most 4096 pixels per side and 8 megapixels.',
    'error.skippedFrames': 'The encoder skipped frames.', 'error.fileSize': 'The video exceeds the 512 MB limit.',
    'error.emptyFrame': 'The encoder returned an empty frame.', 'error.frameOrder': 'The encoder changed the frame order.',
    'error.webmFrames': 'No valid WebM frames available.', 'error.numberRange': 'A number is outside the file format’s range.',
    'error.coreLoad': 'The animation engine could not be loaded.', 'error.coreVersion': 'Unknown animation engine version.',
    'error.imageData': 'Invalid image data.', 'error.keyframes': 'Invalid keyframes.',
    'error.region': 'The image region is invalid or contains no visible image content.', 'error.timing': 'Invalid timing or keyframe settings.',
    'error.frame': 'Invalid frame.', 'error.encoderChanged': 'The encoder changed its configuration during export.',
    'error.mp4Config': 'The encoder returned no valid MP4 configuration.', 'error.exportRunning': 'An export is already running.',
    'error.durationLimit': 'Up to 18,000 frames and 10 minutes are supported.',
    'error.cancelled': 'Export cancelled.',
    'error.unexpected': 'Processing failed. Check the image and settings, then try again.'
  },
  de: {
    viewer: 'Bild und Animationsvorschau', chooseOrDrop: 'Bild auswählen oder hierher ziehen',
    dropHint: 'PNG oder JPEG auswählen oder ein Bild hierher ziehen.', chooseImage: 'Bild auswählen',
    previewLabel: 'Animationsvorschau. Zum Auswählen eines Bereichs ziehen.', noImage: 'Noch kein Bild ausgewählt', replaceImage: 'Bild wechseln',
    play: 'Vorschau abspielen', pause: 'Vorschau anhalten', position: 'Zeitposition', previewHint: 'Die Vorschau zeigt die tatsächlichen Animationsbilder.',
    settings: 'Animation einstellen', animation: 'Animation', reset: 'Zurücksetzen', duration: 'Dauer', seconds: 'Sekunden',
    fps: 'Bildrate', framesPerSecond: 'Bilder / s', easing: 'Verlauf', linear: 'Linear mit sanftem Ende',
    geometric: 'Geometrisch', slowFast: 'Langsam → schnell', fastSlow: 'Schnell → langsam', blank: 'Vorlauf', hold: 'Schlussbild',
    startSize: 'Startgröße', startSizeUnit: 'Pixel · leer = automatisch', automatic: 'Automatisch', imageRegion: 'Bildbereich',
    reveal: 'Enthüllen', wholeImage: 'Das gesamte Bild', detectRegion: 'Sichtbaren Bereich automatisch erkennen', selectRegion: 'Einen Bereich auswählen',
    regionHint: 'Ziehe in der Vorschau oder gib die Bildkoordinaten ein.', left: 'Links', top: 'Oben', right: 'Rechts', bottom: 'Unten',
    threshold: 'Hintergrundtoleranz', autoBackground: 'Hintergrund automatisch', background: 'Hintergrundfarbe',
    keyframes: 'Eigene Keyframes', keyframeLabel: 'Zeit : Pixelgröße',
    keyframeHint: 'Beginne bei 0 Sekunden und ende bei Größe 1. Zeiten müssen steigen, Größen dürfen nur kleiner werden. Keyframes ersetzen Dauer und Verlauf.',
    video: 'Video', format: 'Format', chooseFirst: 'Bitte zuerst ein Bild auswählen', createVideo: 'Video erstellen', videoProgress: 'Video-Fortschritt',
    preparing: 'Wird vorbereitet …', cancel: 'Abbrechen', initialStatus: 'Wähle ein Bild, um zu beginnen.', finishedVideo: 'Fertiges Video', saveVideo: 'Video speichern', share: 'Teilen',
    offlinePreparing: 'Offlinepaket wird vorbereitet …', install: 'Installieren', update: 'Update laden', installTitle: 'Zum Homescreen hinzufügen',
    installHint: 'Öffne das Teilen-Menü deines Browsers und wähle „Zum Home-Bildschirm“. Warte vorher, bis unten „Offline bereit“ erscheint.', understood: 'Verstanden',
    progress: '{done} von {total} Bildern', summary: '{count} Bilder · {seconds} s', detectedRegion: 'Erkannter Bereich: {box}. {hint}',
    noEncoder: 'Kein passender Videoencoder verfügbar', encoderHint: 'Die Vorschau funktioniert. Dieser Browser bietet für diese Bildgröße und Bildrate keinen passenden Videoencoder. Versuche einen anderen Browser.',
    openingImage: 'Bild wird geöffnet …', imageReady: 'Bild bereit. Passe die Animation an oder erstelle das Video.',
    cancelled: 'Export abgebrochen. Du kannst ihn erneut starten.', exporting: 'Das Video wird auf deinem Gerät erstellt. Bitte lass die App geöffnet.',
    finished: 'Fertig. Dein Video ist bereit zum Speichern.', shareUnavailable: 'Teilen ist hier nicht verfügbar. Nutze „Video speichern“.',
    interrupted: 'Export unterbrochen, weil die App verlassen wurde. Starte ihn bei geöffneter App erneut.', offlineUnavailable: 'Offlineinstallation ist in diesem Browser nicht verfügbar.',
    offlineReady: 'Offline bereit', updateAvailable: 'Offline bereit · Update verfügbar', offlineNotReady: 'Offlinepaket noch nicht bereit. Bitte erneut online öffnen.',
    'error.worker': 'Die Verarbeitung konnte nicht gestartet werden. Bitte lade die App neu.', 'error.settings': 'Bitte prüfe die markierten Einstellungen.',
    'error.keyframeSyntax': 'Keyframes bitte als Zeit:Größe angeben.', 'error.keyframeCount': 'Maximal 256 Keyframes werden unterstützt.',
    'error.imageSize': 'Bitte wähle ein Bild mit maximal 4096 Pixeln je Seite und 8 Megapixeln.',
    'error.skippedFrames': 'Der Encoder hat Bilder ausgelassen.', 'error.fileSize': 'Das Video überschreitet die Grenze von 512 MB.',
    'error.emptyFrame': 'Der Encoder hat ein leeres Bild ausgegeben.', 'error.frameOrder': 'Der Encoder hat die Bildreihenfolge verändert.',
    'error.webmFrames': 'Keine gültigen WebM-Bilder vorhanden.', 'error.numberRange': 'Zahl außerhalb des Dateiformats.',
    'error.coreLoad': 'Der Animationskern konnte nicht geladen werden.', 'error.coreVersion': 'Unbekannte Version des Animationskerns.',
    'error.imageData': 'Ungültige Bilddaten.', 'error.keyframes': 'Ungültige Keyframes.',
    'error.region': 'Der Bildbereich ist ungültig oder enthält keine sichtbaren Bildteile.', 'error.timing': 'Die Zeit- oder Keyframe-Einstellungen sind ungültig.',
    'error.frame': 'Ungültiges Bild.', 'error.encoderChanged': 'Der Encoder hat seine Konfiguration während des Exports verändert.',
    'error.mp4Config': 'Der Encoder hat keine gültige MP4-Konfiguration ausgegeben.', 'error.exportRunning': 'Es läuft bereits ein Export.',
    'error.durationLimit': 'Maximal 18.000 Bilder und 10 Minuten werden unterstützt.',
    'error.cancelled': 'Export abgebrochen.',
    'error.unexpected': 'Die Verarbeitung ist fehlgeschlagen. Prüfe das Bild und die Einstellungen und versuche es erneut.'
  }
};
export function t(key, values = {}, locale = language) {
  const template = messages[locale]?.[key] ?? messages.en[key];
  if (template === undefined) throw new Error(`Missing translation: ${key}`);
  return template.replace(/\{(\w+)\}/g, (_, name) => values[name] ?? `{${name}}`);
}
export function number(value, options = {}) { return value.toLocaleString(language, options); }
export function errorMessage(error) {
  if (Object.hasOwn(messages.en, error.message)) return t(error.message);
  console.error(error);
  return t('error.unexpected');
}
export function applyTranslations(root, locale = language) {
  root.documentElement.lang = locale;
  for (const node of root.querySelectorAll('[data-i18n]')) node.textContent = t(node.dataset.i18n, {}, locale);
  for (const attribute of ['aria-label', 'placeholder']) {
    for (const node of root.querySelectorAll(`[data-i18n-${attribute}]`)) node.setAttribute(attribute, t(node.getAttribute(`data-i18n-${attribute}`), {}, locale));
  }
  root.getElementById('time').value = `${(0).toLocaleString(locale, {minimumFractionDigits: 2, maximumFractionDigits: 2})} s`;
}
