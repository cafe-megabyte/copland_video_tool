const api = new Function(readText('web/i18n.js').replace(/^export /mg, '') + '\nreturn {messages, resolveLanguage, t};')();
function assert(value, message) { if (!value) throw new Error(message); }
for (const [input, expected] of [['de','de'],['de-DE','de'],['de-AT','de'],['DE-ch','de'],['en','en'],['en-DE','en'],['fr-FR','en'],['ja','en'],['','en'],[undefined,'en']]) {
  assert(api.resolveLanguage(input) === expected, `Wrong language for ${input}`);
}
const enKeys = Object.keys(api.messages.en).sort(), deKeys = Object.keys(api.messages.de).sort();
assert(JSON.stringify(enKeys) === JSON.stringify(deKeys), 'Translation dictionaries differ');
for (const key of enKeys) for (const locale of ['en', 'de']) {
  assert(api.messages[locale][key].length, `Empty ${locale} translation: ${key}`);
  const parameters = api.messages[locale][key].match(/\{\w+\}/g) || [];
  assert(JSON.stringify(parameters.sort()) === JSON.stringify((api.messages.en[key].match(/\{\w+\}/g) || []).sort()), `Different parameters: ${key}`);
}
const html = readText('web/index.html');
const keys = [...html.matchAll(/data-i18n(?:-aria-label|-placeholder)?="([^"]+)"/g)].map(m => m[1]);
const app = readText('web/app.js');
keys.push(...[...app.matchAll(/\bt\('([^']+)'/g)].map(m => m[1]));
for (const file of ['app','binary','engine-worker','mp4-writer','webm-writer','video-export','wasm-loader']) {
  keys.push(...[...readText(`web/${file}.js`).matchAll(/new (?:Error|DOMException)\('(error\.[^']+)'/g)].map(m => m[1]));
}
for (const key of keys) assert(enKeys.includes(key), `Missing translation: ${key}`);
assert(api.t('summary',{count:'304',seconds:'10.133'},'en') === '304 frames · 10.133 s', 'English summary');
const germanSummary = api.t('summary',{count:'304',seconds:'10,133'},'de');
assert(germanSummary.includes('304') && germanSummary.includes('10,133 s') && !/\{\w+\}/.test(germanSummary), 'German summary preserves localized values');
assert(germanSummary !== api.t('summary',{count:'304',seconds:'10,133'},'en'), 'German summary differs from English');
assert(!/Copland(?! Video Tool)/.test(html), 'Incomplete product name in HTML');
const manifest = JSON.parse(readText('web/manifest.webmanifest'));
assert(manifest.name === 'Copland Video Tool' && manifest.short_name === manifest.name, 'Incomplete installation name');
report('EN/DE language selection, complete UI/error translations and product names passed.');
var testDone = true;
