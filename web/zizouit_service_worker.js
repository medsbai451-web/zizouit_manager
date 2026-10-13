// Cached assets contain only the application shell; business data stays in local storage.
const BUILD_VERSION = '__BUILD_VERSION__';
const CACHE_PREFIX = `zizouit-offline:${self.registration.scope}:`;
const CACHE_NAME = CACHE_PREFIX + BUILD_VERSION;

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const response = await fetch(new URL('offline-assets.json', self.registration.scope), {cache: 'no-store'});
    if (!response.ok) throw new Error('Offline build manifest unavailable');
    const manifest = await response.json();
    if (manifest.version !== BUILD_VERSION) throw new Error('Offline build version mismatch');
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(manifest.assets.map(path => new URL(path, self.registration.scope).href));
    // Existing clients retain their previous version until closed; no forced reload during work.
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin || !url.href.startsWith(self.registration.scope)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const key = event.request.mode === 'navigate'
      ? new URL('index.html', self.registration.scope).href
      : event.request;
    return (await cache.match(key)) || fetch(event.request);
  })());
});
