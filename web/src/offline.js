// Registers the service worker (web/sw.js) that keeps the published site working offline, and offers a reload when
// a new version has been downloaded in the background.

import { store } from "./store.js";

let waiting = null;
const listeners = new Set();

/** True when a new version is ready and a reload would switch to it. */
export const updateReady = () => waiting != null;

export function subscribe(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

/** Switches to the downloaded version: saves pending changes, then reloads once the new worker is in charge. */
export async function applyUpdate() {
  if (!waiting) return;
  await store.flush();
  navigator.serviceWorker.addEventListener("controllerchange", () => location.reload(), { once: true });
  waiting.postMessage("activate");
}

export async function registerServiceWorker() {
  // Local testing (scripts/serve_web.py) always loads the files as they are on disk.
  if (!("serviceWorker" in navigator) || ["localhost", "127.0.0.1"].includes(location.hostname)) return;
  let registration;
  try {
    registration = await navigator.serviceWorker.register("sw.js");
  } catch (error) {
    console.warn("Offline support is not available:", error);
    return;
  }
  const offer = (worker) => {
    waiting = worker;
    for (const fn of listeners) fn();
  };
  // An update that finished downloading during an earlier visit: switch before anything has been done on the page.
  if (registration.waiting && navigator.serviceWorker.controller) {
    waiting = registration.waiting;
    applyUpdate();
    return;
  }
  registration.addEventListener("updatefound", () => {
    const worker = registration.installing;
    worker?.addEventListener("statechange", () => {
      // The first install has nothing to replace; later ones wait until the learner reloads.
      if (worker.state === "installed" && navigator.serviceWorker.controller) offer(worker);
    });
  });
  // The app stays open for a long time, so look for a new version whenever it comes back into view.
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") registration.update().catch(() => {});
  });
}
