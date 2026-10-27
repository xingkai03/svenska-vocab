// The signed-in account and two-way sync with Supabase, using the same tables and rules as AccountService
// and SyncService in the app, so a learner's words, reviews, check-ins, settings and imported lists are shared
// between the web and their iPhone.
//
// Change tracking works like in the app: for every row the browser remembers a fingerprint of the version
// both sides last agreed on. A local row whose fingerprint differs has changed here; a row that was agreed on
// and is now missing locally was deleted. On first sign-in nothing has been agreed yet, so everything in the
// browser is uploaded and merged with what the account already holds.

import * as api from "./supabase.js";
import { kvGet, kvSet, SETTING_DEFAULTS, store } from "./store.js";

const SESSION_KEY = "svenska.session";
const PAGE_SIZE = 1000;
/** Re-reads a few minutes before the cursor, so writes that committed late are not missed. */
const OVERLAP = 5 * 60 * 1000;
const DELETED = "deleted";

// MARK: - Account

function loadSession() {
  try {
    return JSON.parse(localStorage.getItem(SESSION_KEY)) ?? null;
  } catch {
    return null;
  }
}

class Cloud {
  session = api.isConfigured ? loadSession() : null;
  isSyncing = false;
  lastSyncedAt = null;
  lastError = null;

  #listeners = new Set();
  #refreshing = null;
  #pending = false;
  #timer = null;

  get isConfigured() {
    return api.isConfigured;
  }

  subscribe(fn) {
    this.#listeners.add(fn);
    return () => this.#listeners.delete(fn);
  }

  #emit() {
    for (const fn of this.#listeners) fn();
  }

  #store(session) {
    this.session = session;
    try {
      if (session) localStorage.setItem(SESSION_KEY, JSON.stringify(session));
      else localStorage.removeItem(SESSION_KEY);
    } catch {}
    this.#emit();
  }

  /** Returns true when signed in straight away, false when the email address must be confirmed first. */
  async signUp(email, password) {
    const session = await api.signUp(email, password);
    if (!session) return false;
    this.#store(session);
    return true;
  }

  async signIn(email, password) {
    this.#store(await api.signIn(email, password));
  }

  /** Signs in from an email confirmation link, if the page was opened from one. */
  async signInFromLink() {
    if (!api.isConfigured) return;
    try {
      const session = await api.sessionFromLink();
      if (session) this.#store(session);
    } catch (error) {
      this.lastError = error.message;
      this.#emit();
    }
  }

  async signOut() {
    await this.sync();
    const session = this.session;
    if (session) await api.signOut(session);
    this.#store(null);
    if (session) await this.reset(session.userId);
  }

  /** Permanently deletes the account and everything stored in the cloud. Data in this browser stays. */
  async deleteAccount() {
    const userId = this.session?.userId;
    await api.rpc("delete_account", await this.accessToken());
    this.#store(null);
    if (userId) await this.reset(userId);
  }

  /** A valid access token, refreshed if it expires within a minute. */
  async accessToken(forceRefresh = false) {
    const current = this.session;
    if (!current) throw new api.SupabaseError(0, "You are signed out.");
    if (!forceRefresh && current.expiresAt > Date.now() + 60_000) return current.accessToken;
    this.#refreshing ??= api.refresh(current).finally(() => (this.#refreshing = null));
    try {
      const fresh = await this.#refreshing;
      this.#store(fresh);
      return fresh.accessToken;
    } catch (error) {
      if (error.status >= 400 && error.status < 500) {
        // The refresh token was revoked or has expired: the learner has to sign in again.
        this.#store(null);
        throw new api.SupabaseError(0, "You are signed out.");
      }
      throw error;
    }
  }

  /** Table reads and writes with a fresh token; retries once with a refreshed token on 401. */
  async #authorized(call) {
    try {
      return await call(await this.accessToken());
    } catch (error) {
      if (error.status !== 401) throw error;
      return call(await this.accessToken(true));
    }
  }

  async #changes(table, cursor) {
    const rows = [];
    for (;;) {
      const query = { select: "*", order: "updated_at.asc", limit: String(PAGE_SIZE), offset: String(rows.length) };
      if (cursor != null) query.updated_at = `gt.${new Date(cursor - OVERLAP).toISOString()}`;
      const page = await this.#authorized((token) => api.select(table, query, token));
      rows.push(...page);
      if (page.length < PAGE_SIZE) return rows;
    }
  }

  async #upsert(table, rows, onConflict, ignoreDuplicates = false) {
    if (!rows.length) return;
    await this.#authorized((token) => api.upsert(table, rows, onConflict, token, ignoreDuplicates));
  }

  // MARK: - Sync

  /** Syncs a few seconds after a change in this browser, so quick edits go up together. */
  scheduleSync(delay = 4000) {
    if (!this.session) return;
    clearTimeout(this.#timer);
    this.#timer = setTimeout(() => this.sync(), delay);
  }

  /** Runs a sync now, or right after the one in progress. */
  async sync() {
    clearTimeout(this.#timer);
    const userId = this.session?.userId;
    if (!userId) return;
    if (this.isSyncing) {
      this.#pending = true;
      return;
    }
    this.isSyncing = true;
    this.#emit();
    try {
      do {
        this.#pending = false;
        try {
          const state = (await kvGet(`sync:${userId}`)) ?? newState();
          await this.#run(userId, state);
          state.lastSyncedAt = Date.now();
          await kvSet(`sync:${userId}`, state);
          this.lastSyncedAt = state.lastSyncedAt;
          this.lastError = null;
        } catch (error) {
          this.lastError = error.message || String(error);
          console.error(error);
        }
      } while (this.#pending && this.session?.userId === userId);
    } finally {
      this.isSyncing = false;
      await store.flush();
      this.#emit();
    }
  }

  async loadStatus() {
    if (!this.session) return;
    this.lastSyncedAt = (await kvGet(`sync:${this.session.userId}`))?.lastSyncedAt ?? null;
    this.#emit();
  }

  /** Forgets what was synced for this account, e.g. after signing out. */
  async reset(userId) {
    await kvSet(`sync:${userId}`, undefined);
    this.lastSyncedAt = null;
    this.lastError = null;
    this.#emit();
  }

  async #run(userId, state) {
    // Saved words
    state.words = await this.#syncTable(WORDS, userId, state.words);
    // Check-ins
    state.checkIns = await this.#syncTable(CHECK_INS, userId, state.checkIns);
    // Review history (append-only)
    await this.#syncLogs(userId, state);
    // Settings: on a conflict the account's settings win, so a new device picks them up.
    state.settings = await this.#syncTable(SETTINGS, userId, state.settings);
    // Imported word lists
    state.lists = await this.#syncTable(LISTS, userId, state.lists);
  }

  /** Pulls rows changed since the last sync, merges them in, then pushes this browser's changes. */
  async #syncTable(t, userId, tableState) {
    const state = { cursor: tableState.cursor ?? null, synced: { ...tableState.synced } };

    // Pull
    const remote = await this.#changes(t.table, state.cursor);
    const before = t.local();
    let applied = false;
    for (const row of remote) {
      const { key, record } = t.fromWire(row);
      const deleted = Boolean(row.deleted);
      const remotePrint = deleted ? DELETED : print(t, record);
      const base = state.synced[key];
      const updated = parseDate(row.updated_at);
      if (updated != null) state.cursor = Math.max(state.cursor ?? updated, updated);
      if (remotePrint === base) continue;
      const current = before.get(key);
      if (current) {
        const localPrint = print(t, current);
        const changedHere = localPrint !== base;
        if (localPrint !== remotePrint && (!changedHere || (!deleted && t.preferRemote(current, record)))) {
          t.apply(key, deleted ? null : record);
          applied = true;
        }
      } else if (!deleted) {
        t.apply(key, record);
        applied = true;
      }
      state.synced[key] = remotePrint;
    }
    if (applied) store.changed([t.part], { fromSync: true });

    // Push
    const after = t.local();
    const changed = [];
    for (const [key, record] of after) {
      const fingerprint = print(t, record);
      if (fingerprint !== state.synced[key]) changed.push({ key, row: t.toWire(key, record), fingerprint });
    }
    for (const [key, agreed] of Object.entries(state.synced)) {
      if (!after.has(key) && agreed !== DELETED) {
        changed.push({ key, row: t.toWire(key, t.tombstone(), true), fingerprint: DELETED });
      }
    }
    for (let i = 0; i < changed.length; i += t.batchSize) {
      const chunk = changed.slice(i, i + t.batchSize);
      await this.#upsert(t.table, chunk.map((c) => ({ user_id: userId, ...c.row })), t.conflict);
      for (const c of chunk) state.synced[c.key] = c.fingerprint;
    }
    return state;
  }

  async #syncLogs(userId, state) {
    let cursor = state.logsCursor ?? null;
    const known = new Set(store.logs.map(logId));

    const remote = await this.#changes("review_logs", cursor);
    let added = false;
    for (const row of remote) {
      const updated = parseDate(row.updated_at);
      if (updated != null) cursor = Math.max(cursor ?? updated, updated);
      if (known.has(row.id)) continue;
      known.add(row.id);
      store.logs.push({ date: parseDate(row.reviewed_at), wordKey: row.word_key, grade: row.grade, intervalAfter: row.interval_after, mode: row.mode ?? "" });
      added = true;
    }
    if (added) {
      store.logs.sort((a, b) => a.date - b.date);
      store.changed(["logs"], { fromSync: true });
    }

    // Logs are only ever added, so anything newer than what was last uploaded is new.
    const pushedThrough = state.logsPushedThrough ?? -Infinity;
    const fresh = store.logs.filter((l) => l.date > pushedThrough);
    for (let i = 0; i < fresh.length; i += 1000) {
      const chunk = fresh.slice(i, i + 1000);
      await this.#upsert("review_logs", chunk.map((l) => ({
        user_id: userId, id: logId(l), word_key: l.wordKey, grade: l.grade, interval_after: l.intervalAfter,
        mode: l.mode ?? "", reviewed_at: iso(l.date),
      })), "user_id,id", true);
      state.logsPushedThrough = Math.max(state.logsPushedThrough ?? -Infinity, ...chunk.map((l) => l.date));
    }
    state.logsCursor = cursor;
  }
}

export const cloud = new Cloud();

function newState() {
  const table = () => ({ cursor: null, synced: {} });
  return { words: table(), checkIns: table(), settings: table(), lists: table(), logsCursor: null, logsPushedThrough: null, lastSyncedAt: null };
}

// MARK: - Wire format

/** Dates as UTC ISO 8601 with milliseconds, so a date survives the round trip through Postgres unchanged. */
const iso = (ms) => new Date(ms).toISOString();

/** Parses Postgres timestamps such as 2026-10-21T17:23:16.123456+00:00, rounded to the millisecond like the app. */
function parseDate(text) {
  if (text == null) return null;
  const m = /^(.*?)(?:\.(\d+))?(Z|[+-]\d\d:?\d\d)$/.exec(text);
  if (!m) return Date.parse(text);
  const base = Date.parse(m[1] + m[3]);
  if (Number.isNaN(base)) return null;
  return Math.round(base + Number(`0.${m[2] ?? "0"}`) * 1000);
}

const logId = (l) => `${l.wordKey}|${Math.round(l.date)}`;

/** Identifies a row's content, so the two sides can tell whether they agree. */
const print = (t, record) => JSON.stringify(t.fields.map((f) => record[f]));

const WORD_COLUMNS = [
  // [local name, column, kind]
  ["word", "word"], ["partOfSpeech", "part_of_speech"], ["gender", "gender"], ["forms", "forms"],
  ["translation", "translation"], ["example", "example"], ["exampleTranslation", "example_translation"],
  ["note", "note"], ["source", "source"], ["level", "level"], ["addedAt", "added_at", "date"],
  ["isFavorite", "is_favorite"], ["easeFactor", "ease_factor"], ["interval", "interval_days"],
  ["repetitions", "repetitions"], ["lapses", "lapses"], ["reviewCount", "review_count"],
  ["dueDate", "due_date", "date"], ["lastReviewedAt", "last_reviewed_at", "date"],
];

const WORDS = {
  table: "saved_words", conflict: "user_id,key", part: "words", batchSize: 500,
  fields: WORD_COLUMNS.map((c) => c[0]),
  local: () => store.words,
  tombstone: () => ({
    word: "", partOfSpeech: "", gender: "", forms: "", translation: "", example: "", exampleTranslation: "",
    note: "", source: "", level: "", addedAt: Date.now(), isFavorite: false, easeFactor: 2.5, interval: 0,
    repetitions: 0, lapses: 0, reviewCount: 0, dueDate: Date.now(), lastReviewedAt: null,
  }),
  toWire(key, w, deleted = false) {
    const row = { key, deleted };
    for (const [name, column, kind] of WORD_COLUMNS) {
      row[column] = kind === "date" ? (w[name] == null ? null : iso(w[name])) : w[name];
    }
    return row;
  },
  fromWire(row) {
    const w = { key: row.key };
    for (const [name, column, kind] of WORD_COLUMNS) {
      w[name] = kind === "date" ? parseDate(row[column]) : row[column];
    }
    w.addedAt ??= Date.now();
    w.dueDate ??= Date.now();
    return { key: row.key, record: w };
  },
  apply(key, record) {
    if (record) store.words.set(key, record);
    else store.words.delete(key);
  },
  // Both sides changed: keep the version that has seen more reviews.
  preferRemote: (local, remote) => remote.reviewCount > local.reviewCount,
};
WORDS.fields.unshift("key");

const CHECK_INS = {
  table: "check_ins", conflict: "user_id,day", part: "checkIns", batchSize: 500,
  fields: ["day", "checkedInAt", "itemsDone"],
  local: () => store.checkIns,
  tombstone: () => ({ checkedInAt: Date.now(), itemsDone: 0 }),
  toWire: (day, c, deleted = false) => ({ day, checked_in_at: iso(c.checkedInAt), items_done: c.itemsDone, deleted }),
  fromWire: (row) => ({
    key: row.day,
    record: { day: row.day, checkedInAt: parseDate(row.checked_in_at) ?? Date.now(), itemsDone: row.items_done ?? 0 },
  }),
  apply(day, record) {
    if (record) store.checkIns.set(day, record);
    else store.checkIns.delete(day);
  },
  preferRemote: (local, remote) => remote.itemsDone > local.itemsDone,
};

// Preferences that follow the learner across devices, stored as JSON with the app's snake_case names.
const SETTING_COLUMNS = {
  dailyGoal: "daily_goal", sessionSize: "session_size", speechRate: "speech_rate", autoSpeak: "auto_speak",
  onlineLookup: "online_lookup", skippedWords: "skipped_words", discoverDeck: "discover_deck",
  knowsGerman: "knows_german", knowsFrench: "knows_french", disabledReviewModes: "disabled_review_modes",
};

function settingsData(settings) {
  const data = {};
  for (const name of Object.keys(SETTING_DEFAULTS).sort()) if (settings[name] != null) data[name] = settings[name];
  return data;
}

const SETTINGS = {
  table: "user_settings", conflict: "user_id,key", part: "settings", batchSize: 500,
  fields: ["data"],
  local: () => new Map([["settings", { data: settingsData(store.settings) }]]),
  tombstone: () => ({ data: {} }),
  toWire(key, record, deleted = false) {
    const data = {};
    for (const [name, value] of Object.entries(record.data)) data[SETTING_COLUMNS[name]] = value;
    return { key, data, deleted };
  },
  fromWire(row) {
    const settings = {};
    for (const [name, column] of Object.entries(SETTING_COLUMNS)) if (row.data?.[column] != null) settings[name] = row.data[column];
    return { key: row.key, record: { data: settingsData(settings) } };
  },
  apply(_, record) {
    if (record) store.settings = { ...store.settings, ...record.data };
  },
  preferRemote: () => true,
};

const LISTS = {
  table: "imported_lists", conflict: "user_id,file_name", part: "lists", batchSize: 20,
  fields: ["content"],
  local: () => new Map([...store.lists].map(([name, content]) => [name, { content }])),
  tombstone: () => ({ content: "" }),
  toWire: (fileName, l, deleted = false) => ({ file_name: fileName, content: l.content, deleted }),
  fromWire: (row) => ({ key: row.file_name, record: { content: row.content ?? "" } }),
  apply(fileName, record) {
    // Only plain deck file names, never paths.
    if (!fileName.startsWith("deck_") || fileName.includes("/") || fileName.includes("..")) return;
    if (record) store.lists.set(fileName, record.content);
    else store.lists.delete(fileName);
  },
  preferRemote: () => false,
};
