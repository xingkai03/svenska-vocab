// Offline support for the published web version. scripts/build_web.py fills in VERSION and FILES when it builds the
// site: every file of one deploy is cached together, so a browser never mixes old and new code, and the app opens
// without a connection. Not used on localhost (see main.js), so local edits show up straight away.

const VERSION = "dev";
const FILES = [];
const CACHE = `svenska-${VERSION}`;
/** Files fetched on demand (SVT clip lists) and kept for offline use, across versions. */
const EXTRA = "svenska-extra";

self.addEventListener("install", (event) => {
  // cache: "reload" skips the browser's HTTP cache, which can still hold files of the previous deploy.
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(FILES.map((f) => new Request(f, { cache: "reload" })))));
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith("svenska-") && name !== CACHE && name !== EXTRA) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});

// The page asks for a waiting update to take over when it is safe to reload (see main.js).
self.addEventListener("message", (event) => {
  if (event.data === "activate") self.skipWaiting();
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  const url = new URL(request.url);
  // Only this site's own files; Supabase and article sources always go to the network.
  if (request.method !== "GET" || url.origin !== location.origin) return;
  event.respondWith((async () => {
    const path = request.mode === "navigate" ? new URL("./", self.registration.scope).href : url.href.split("#")[0];
    const cached = await caches.match(path, { ignoreSearch: request.mode === "navigate" });
    if (cached) return cached;
    const response = await fetch(request);
    if (response.ok && url.pathname.includes("/svt/")) {
      const copy = response.clone();
      caches.open(EXTRA).then((cache) => cache.put(request, copy));
    }
    return response;
  })());
});
