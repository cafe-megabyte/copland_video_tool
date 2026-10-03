const RELEASE = '__RELEASE__';
const BASE = new URL('./', self.location.href);
const CACHE = `copland-${BASE.pathname}-${RELEASE}`;
const COMPLETE = new URL(`./.offline-complete-${RELEASE}`, BASE).href;
self.addEventListener('install', event => event.waitUntil((async () => {
  const cache = await caches.open(CACHE);
  try {
    const response = await fetch(new URL('offline-resources.json', BASE), {cache: 'no-store'});
    if (!response.ok) throw new Error('Missing offline inventory');
    const resources = await response.json();
    for (const resource of resources) {
      const url = new URL(resource.path, BASE);
      if (url.origin !== BASE.origin || !url.pathname.startsWith(BASE.pathname)) throw new Error('Invalid offline resource');
      if (resource.path.startsWith('releases/') && !resource.path.startsWith(`releases/${RELEASE}/`)) throw new Error('Mixed offline release');
      const result = await fetch(url, {cache: 'no-store'});
      if (!result.ok) throw new Error(`Missing ${resource.path}`);
      const bytes = await result.clone().arrayBuffer();
      if (bytes.byteLength !== resource.size) throw new Error(`Incomplete ${resource.path}`);
      if (resource.path === 'index.html' && !new TextDecoder().decode(bytes).includes(`./releases/${RELEASE}/app.js`))
        throw new Error('HTML belongs to another release');
      await cache.put(url, result);
    }
    await cache.put(COMPLETE, new Response(RELEASE));
    // First installation can activate immediately; updates await explicit user action.
    if (!self.registration.active) await self.skipWaiting();
  } catch (error) { await caches.delete(CACHE); throw error; }
})()));
self.addEventListener('activate', event => event.waitUntil((async () => {
  const cache = await caches.open(CACHE);
  if (!await cache.match(COMPLETE)) throw new Error('Incomplete offline package');
  await self.clients.claim();
  for (const client of await self.clients.matchAll()) client.postMessage({type: 'offline-ready', release: RELEASE});
  // Older release caches remain available to existing clients. Browser storage
  // controls still apply; manual deletion removes the offline installation.
})()));
self.addEventListener('message', event => { if (event.data?.type === 'activate') self.skipWaiting(); });
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== BASE.origin || !url.pathname.startsWith(BASE.pathname)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    if (event.request.mode === 'navigate') return await cache.match(new URL('index.html', BASE)) || fetch(event.request);
    const cached = await cache.match(event.request, {ignoreSearch: true});
    if (cached) return cached;
    // An old client may request its immutable previous release paths after update.
    if (url.pathname.startsWith(new URL('releases/', BASE).pathname)) {
      const old = await caches.match(event.request, {ignoreSearch: true}); if (old) return old;
    }
    return fetch(event.request);
  })());
});
