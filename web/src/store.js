// The learner's own data in this browser: saved words, review history, check-ins, settings and imported
// word lists. Kept in IndexedDB so the web version works without an account and offline, like the app;
// sync.js reconciles it with the cloud.

import { addDays, dayString, startOfDay } from "./scheduler.js";

const DB_NAME = "svenska-vocab";

function openDB() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onupgradeneeded = () => request.result.createObjectStore("kv");
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

const dbPromise = openDB().catch(() => null);

export async function kvGet(key) {
  const db = await dbPromise;
  if (!db) return undefined;
  return new Promise((resolve) => {
    const request = db.transaction("kv").objectStore("kv").get(key);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => resolve(undefined);
  });
}

export async function kvSet(key, value) {
  const db = await dbPromise;
  if (!db) return;
  return new Promise((resolve) => {
    const tx = db.transaction("kv", "readwrite");
    if (value === undefined) tx.objectStore("kv").delete(key);
    else tx.objectStore("kv").put(value, key);
    tx.oncomplete = tx.onerror = () => resolve();
  });
}

/** Preferences that sync between devices, with the app's defaults. */
export const SETTING_DEFAULTS = {
  dailyGoal: 20,
  sessionSize: 30,
  speechRate: 0.45,
  autoSpeak: true,
  onlineLookup: true,
  skippedWords: "",
  discoverDeck: "core",
  knowsGerman: false,
  knowsFrench: false,
};

/** Key of a word in the collection: the same as DictionaryEntry.id in the app. */
export const entryId = (e) => `${e.word.toLowerCase()}#${e.partOfSpeech}`;

class Store {
  words = new Map(); // key → saved word
  logs = []; // { date, wordKey, grade, intervalAfter }, oldest first
  checkIns = new Map(); // "2026-10-21" → { day, checkedInAt, itemsDone }
  settings = {}; // only the settings the learner has set (see SETTING_DEFAULTS)
  lists = new Map(); // "deck_my_list.tsv" → file content
  version = 0;
  /** Counts the changes to each part, e.g. revision.lists, so derived data knows when to rebuild. */
  revision = {};

  /** Called after every change made on this device (not by a sync), e.g. to schedule an upload. */
  onLocalChange = null;

  #listeners = new Set();
  #dirty = new Set();
  #saveTimer = null;

  async load() {
    const [words, logs, checkIns, settings, lists] = await Promise.all(
      ["words", "logs", "checkIns", "settings", "lists"].map(kvGet));
    this.words = new Map((words ?? []).map((w) => [w.key, w]));
    this.logs = logs ?? [];
    this.checkIns = new Map((checkIns ?? []).map((c) => [c.day, c]));
    this.settings = settings ?? {};
    this.lists = new Map(Object.entries(lists ?? {}));
    this.revision.lists = (this.revision.lists ?? 0) + 1;
    this.#emit();
  }

  subscribe(fn) {
    this.#listeners.add(fn);
    return () => this.#listeners.delete(fn);
  }

  /** Marks parts of the data as changed: saves them and re-renders. */
  changed(parts, { fromSync = false } = {}) {
    for (const p of parts) {
      this.#dirty.add(p);
      this.revision[p] = (this.revision[p] ?? 0) + 1;
    }
    clearTimeout(this.#saveTimer);
    this.#saveTimer = setTimeout(() => this.flush(), 250);
    this.#emit();
    if (!fromSync) this.onLocalChange?.();
  }

  async flush() {
    clearTimeout(this.#saveTimer);
    const parts = [...this.#dirty];
    this.#dirty.clear();
    await Promise.all(parts.map((p) => {
      switch (p) {
        case "words": return kvSet("words", [...this.words.values()]);
        case "logs": return kvSet("logs", this.logs);
        case "checkIns": return kvSet("checkIns", [...this.checkIns.values()]);
        case "settings": return kvSet("settings", this.settings);
        case "lists": return kvSet("lists", Object.fromEntries(this.lists));
      }
    }));
  }

  #emit() {
    this.version += 1;
    for (const fn of this.#listeners) fn(this.version);
  }

  // Settings

  get(name) {
    return this.settings[name] ?? SETTING_DEFAULTS[name];
  }

  set(name, value) {
    this.settings = { ...this.settings, [name]: value };
    this.changed(["settings"]);
  }

  // Words

  /** Adds a dictionary entry to the collection, if not already present. */
  addToCollection(entry, now = Date.now()) {
    const key = entryId(entry);
    if (this.words.has(key)) return this.words.get(key);
    const word = this.#newWord(entry, now);
    this.words.set(key, word);
    this.changed(["words"]);
    return word;
  }

  /**
   * "I know it" in Learn new words: saves the entry as a word already known for a month (like the app), so it counts
   * as mastered and comes back for a review in 30 days. Does nothing if the word is already saved.
   */
  markKnown(entry, now = Date.now()) {
    if (!this.#addKnown(entry, now)) return;
    this.changed(["words"]);
  }

  /**
   * Older versions kept "I know it" words in the skippedWords setting; saves them as known words (ids no longer in
   * the dictionary are dropped) and clears the setting. Runs on load and whenever the setting changes, e.g. after a
   * sync from an older app.
   */
  migrateSkippedWords(lookup, now = Date.now()) {
    const ids = this.get("skippedWords").split("\n").filter(Boolean);
    if (!ids.length) return;
    this.settings = { ...this.settings, skippedWords: "" };
    for (const id of ids) {
      const entry = lookup(id);
      if (entry) this.#addKnown(entry, now);
    }
    this.changed(["words", "settings"]);
  }

  #addKnown(entry, now) {
    const key = entryId(entry);
    if (this.words.has(key)) return false;
    this.words.set(key, { ...this.#newWord(entry, now), repetitions: 3, interval: 30, reviewCount: 1,
      lastReviewedAt: now, dueDate: addDays(startOfDay(now), 30) });
    return true;
  }

  #newWord(entry, now) {
    return {
      key: entryId(entry), word: entry.word, partOfSpeech: entry.partOfSpeech, gender: entry.gender ?? "",
      forms: entry.forms ?? "", translation: entry.translation ?? "", example: entry.example ?? "",
      exampleTranslation: entry.exampleTranslation ?? "", note: "", source: entry.source ?? "bundled",
      level: entry.level ?? "", addedAt: now, isFavorite: false,
      easeFactor: 2.5, interval: 0, repetitions: 0, lapses: 0, reviewCount: 0, dueDate: now, lastReviewedAt: null,
    };
  }

  updateWord(key, patch) {
    const word = this.words.get(key);
    if (!word) return;
    this.words.set(key, { ...word, ...patch });
    this.changed(["words"]);
  }

  deleteWord(key) {
    if (this.words.delete(key)) this.changed(["words"]);
  }

  addLog(log) {
    this.logs.push(log);
    this.changed(["logs"]);
  }

  checkIn(itemsDone, now = Date.now()) {
    const day = dayString(now);
    this.checkIns.set(day, { day, checkedInAt: now, itemsDone });
    this.changed(["checkIns"]);
  }

  // Imported word lists

  setList(fileName, content) {
    this.lists.set(fileName, content);
    this.changed(["lists"]);
  }

  deleteList(fileName) {
    if (this.lists.delete(fileName)) this.changed(["lists"]);
  }
}

export const store = new Store();

/** Per-browser conveniences that don't sync (recent searches). */
export const local = {
  get(name, fallback) {
    try {
      const v = localStorage.getItem(`svenska.${name}`);
      return v == null ? fallback : JSON.parse(v);
    } catch {
      return fallback;
    }
  },
  set(name, value) {
    try {
      localStorage.setItem(`svenska.${name}`, JSON.stringify(value));
    } catch {}
  },
};
