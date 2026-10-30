// Reading: Swedish articles fetched straight from the sources' own open APIs in the browser, split into words and
// phrases that link to the dictionary. Nothing is copied into this site or synced. 8 Sidor's lists and articles are
// kept in this browser (IndexedDB) for up to a month so they show at once, and refreshed in the background when they
// are old; the other sources are kept in memory only while the page is open. Each source allows browser requests from
// other sites (CORS):
//   8 Sidor          easy-Swedish news (WordPress API, wp-json). © 8 Sidor; read on their terms, always linked back.
//   Klartext         Sveriges Radio's easy news: a short summary and the episode's audio (SR open API, credited).
//   Wikipedia        Swedish Wikipedia, CC BY-SA 4.0.
// Your own text (pasted) works for anything else, such as SVT Nyheter.

import { dictionary } from "./dictionary.js";

const EIGHT = "https://8sidor.se";
const EIGHT_API = `${EIGHT}/wp-json/wp/v2`;
/** 8 Sidor's news sections, in the order of their front page. */
const EIGHT_SECTIONS = ["sverige", "varlden", "alla-valjare", "sport", "kultur", "vardags"];
const SR_API = "https://api.sr.se/api/v2";
const KLARTEXT = 493;
const WIKI_API = "https://sv.wikipedia.org/w/api.php";
const WIKI = "https://sv.wikipedia.org/wiki/";
/** Wikipedia sections that are lists of links rather than prose. */
const WIKI_SKIP = /^(referenser|källor|noter|externa länkar|se även|vidare läsning|litteratur|fotnoter)$/i;

/**
 * An article: { source, id, title, date (ms), link (original page), paragraphs: [{ kind: "p"|"h", text }],
 * audio?: url, credit }. A list item: { source, id, title, date, summary }.
 */
export const SOURCES = {
  "8sidor": {
    name: "8 Sidor",
    level: "Easy Swedish",
    about: "News in easy Swedish, written for people learning the language. New articles every weekday.",
    home: EIGHT,
    credit: "Article © 8 Sidor, shown from 8sidor.se.",
  },
  klartext: {
    name: "Klartext",
    level: "Easy Swedish, listening",
    about: "Sveriges Radio's daily news in simpler Swedish: the episode's summary to read, and the broadcast to listen to.",
    home: "https://sverigesradio.se/klartext",
    credit: "Klartext, Sveriges Radio.",
  },
  wiki: {
    name: "Wikipedia",
    level: "Harder",
    about: "Swedish Wikipedia on any topic you like. Ordinary Swedish, good once easy news feels comfortable.",
    home: "https://sv.wikipedia.org",
    credit: "From Swedish Wikipedia, CC BY-SA 4.0.",
  },
  paste: {
    name: "Your own text",
    level: "Any level",
    about: "Paste an article from anywhere, such as SVT Nyheter or a book you're reading. It stays on this device.",
    credit: "",
  },
};

async function getJSON(url) {
  let response;
  try {
    response = await fetch(url);
  } catch {
    throw new Error("Couldn't reach the site. Check your connection and try again.");
  }
  if (!response.ok) throw new Error(`The site answered with an error (${response.status}).`);
  return response.json();
}

/** Text of an HTML fragment, with entities decoded. */
const textOf = (fragment) => new DOMParser().parseFromString(fragment ?? "", "text/html").body.textContent.replace(/\s+/g, " ").trim();

/** Headings and paragraphs of an article's HTML, leaving out players, images and captions. */
export function paragraphsFromHTML(fragment) {
  const doc = new DOMParser().parseFromString(fragment ?? "", "text/html");
  doc.querySelectorAll("script, style, noscript, iframe, figure, figcaption, img, audio, video, .rs_skip, .wp-caption, .screen-reader-text")
    .forEach((el) => el.remove());
  const paragraphs = [];
  for (const el of doc.body.querySelectorAll("p, h1, h2, h3, h4, li, blockquote")) {
    if (el.querySelector("p, li")) continue; // the inner elements are taken on their own
    const text = el.textContent.replace(/\s+/g, " ").trim();
    if (text) paragraphs.push({ kind: /^H\d$/.test(el.tagName) ? "h" : "p", text });
  }
  if (!paragraphs.length) {
    for (const text of doc.body.textContent.split(/\n\s*\n/)) {
      const t = text.replace(/\s+/g, " ").trim();
      if (t) paragraphs.push({ kind: "p", text: t });
    }
  }
  return paragraphs;
}

/** Paragraphs of plain text: blank lines separate them; a short line without a full stop is a heading. */
export function paragraphsFromText(text) {
  return text.split(/\n\s*\n|\r\n\s*\r\n/).map((t) => t.replace(/\s+/g, " ").trim()).filter(Boolean)
    .map((t) => ({ kind: t.length < 80 && !/[.!?:”"]$/.test(t) && !t.includes(". ") ? "h" : "p", text: t }));
}

// MARK: - Kept in this browser

const MINUTE = 60_000;
const DAY = 24 * 60 * MINUTE;
/** Anything not read again for this long is removed. */
const KEEP_FOR = 30 * DAY;

let database = null;

/** The browser's store of fetched lists and articles, or null where IndexedDB isn't available. */
function db() {
  database ??= new Promise((resolve) => {
    try {
      const open = indexedDB.open("svenska-reading", 1);
      open.onupgradeneeded = () => open.result.createObjectStore("kept");
      open.onsuccess = () => { resolve(open.result); setTimeout(prune, 5000); };
      open.onerror = () => resolve(null);
    } catch {
      resolve(null);
    }
  });
  return database;
}

/** Runs `fn` on the store and resolves with its request's result (undefined if anything fails). */
async function withStore(mode, fn) {
  const store = await db();
  if (!store) return undefined;
  return new Promise((resolve) => {
    try {
      const request = fn(store.transaction("kept", mode).objectStore("kept"));
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => resolve(undefined);
    } catch {
      resolve(undefined);
    }
  });
}

/** { at, value } kept under `key`, where `at` is when it was fetched. */
const stored = (key) => withStore("readonly", (s) => s.get(key));
const keep = (key, value, at = Date.now()) => withStore("readwrite", (s) => s.put({ at, value }, key));

/** Removes what was fetched more than KEEP_FOR ago. */
async function prune() {
  try {
    const request = (await db()).transaction("kept", "readwrite").objectStore("kept").openCursor();
    request.onsuccess = () => {
      const cursor = request.result;
      if (!cursor) return;
      if (!(Date.now() - cursor.value?.at < KEEP_FOR)) cursor.delete();
      cursor.continue();
    };
  } catch {
    // Nothing kept, or the store is unavailable.
  }
}

const refreshing = new Set();

/**
 * The kept value for `key` straight away, fetched with `load` when there is none. A kept value older than `maxAge`
 * is still returned, then fetched again in the background, and `onUpdate` gets the new value if it changed.
 */
async function kept(key, maxAge, load, onUpdate) {
  const hit = await stored(key);
  if (!hit) {
    const value = await load();
    keep(key, value);
    return value;
  }
  if (Date.now() - hit.at > maxAge && !refreshing.has(key)) {
    refreshing.add(key);
    load().then((value) => {
      keep(key, value);
      if (JSON.stringify(value) !== JSON.stringify(hit.value)) onUpdate?.(value);
    }, () => {}).finally(() => refreshing.delete(key));
  }
  return hit.value;
}

// MARK: - 8 Sidor

let eightSections = null;

/** [{ id, name }] for the news sections, looked up once by slug. */
export function eightSidorSections() {
  eightSections ??= kept("8sidor/sections", 7 * DAY, () => getJSON(`${EIGHT_API}/categories?slug=${EIGHT_SECTIONS.join(",")}&_fields=id,name,slug`)
    .then((list) => EIGHT_SECTIONS.map((slug) => list.find((c) => c.slug === slug)).filter(Boolean)
      .map((c) => ({ id: String(c.id), name: textOf(c.name) }))))
    .catch((e) => { eightSections = null; throw e; });
  return eightSections;
}

const eightItem = (p) => ({
  source: "8sidor", id: String(p.id), title: textOf(p.title?.rendered), date: Date.parse(p.date), summary: textOf(p.excerpt?.rendered),
});

const eightArticle = (p) => ({
  ...eightItem(p), link: p.link, paragraphs: paragraphsFromHTML(p.content?.rendered), credit: SOURCES["8sidor"].credit,
});

/** Whole articles for `params`, each kept for loadArticle, so opening one later is instant. */
async function eightSidorPosts(params) {
  params.set("_fields", "id,date,link,title,excerpt,content");
  if (!params.has("categories")) params.set("categories", (await eightSidorSections()).map((s) => s.id).join(","));
  const articles = (await getJSON(`${EIGHT_API}/posts?${params}`)).map(eightArticle);
  for (const a of articles) {
    cache.set(`8sidor/${a.id}`, Promise.resolve(a));
    keep(`8sidor/${a.id}`, a);
  }
  return articles;
}

/**
 * Newest articles, optionally in one section. Shown at once from this browser when it has them; `onUpdate` gets the
 * list again if a background refresh finds newer articles.
 */
export function eightSidorList({ section = "", page = 1, perPage = 20 } = {}, onUpdate) {
  const params = new URLSearchParams({ per_page: perPage, page });
  if (section) params.set("categories", section);
  return kept(`8sidor/list/${section}/${page}/${perPage}`, 15 * MINUTE, async () => (await eightSidorPosts(params))
    .map(({ source, id, title, date, summary }) => ({ source, id, title, date, summary })), onUpdate);
}

async function eightSidorArticle(id) {
  const key = `8sidor/${id}`;
  return kept(key, 7 * DAY, async () =>
    eightArticle(await getJSON(`${EIGHT_API}/posts/${encodeURIComponent(id)}?_fields=id,date,link,title,content`)));
}

/** The kept articles for a list of ids, leaving out any that can no longer be loaded. */
const eightSidorArticles = async (ids) => (await Promise.all(ids.map((id) => loadArticle("8sidor", id).catch(() => null)))).filter(Boolean);

/**
 * Whole articles from 8 Sidor's search for a word, newest first. Its search matches any part of a word ("ark" finds
 * "marken"), so callers check the text themselves. Shown at once from this browser when it has searched for the word
 * before; `onUpdate` gets the articles again if a background refresh finds new ones.
 */
export async function eightSidorSearch(word, perPage = 20, onUpdate) {
  const load = async () => (await eightSidorPosts(new URLSearchParams({ per_page: perPage, search: word }))).map((a) => a.id);
  const ids = await kept(`8sidor/search/${word.toLowerCase()}/${perPage}`, 6 * 60 * MINUTE, load,
    onUpdate && (async (newIds) => onUpdate(await eightSidorArticles(newIds))));
  return eightSidorArticles(ids);
}

// MARK: - Klartext (Sveriges Radio)

const srDate = (s) => Number(/\d+/.exec(s ?? "")?.[0] ?? 0);

const klartextArticle = (e) => ({
  source: "klartext",
  id: String(e.id),
  title: e.title,
  date: srDate(e.publishdateutc),
  summary: e.description ?? "",
  link: e.url,
  audio: e.listenpodfile?.url ?? e.downloadpodfile?.url ?? e.broadcast?.broadcastfiles?.[0]?.url ?? "",
  paragraphs: paragraphsFromText(e.description ?? "").map((p) => ({ ...p, kind: "p" })),
  credit: SOURCES.klartext.credit,
});

export async function klartextList({ page = 1 } = {}) {
  const data = await getJSON(`${SR_API}/episodes/index?programid=${KLARTEXT}&format=json&size=20&page=${page}`);
  return (data.episodes ?? []).map(klartextArticle);
}

async function klartextEpisode(id) {
  const data = await getJSON(`${SR_API}/episodes/get?id=${encodeURIComponent(id)}&format=json`);
  if (!data.episode) throw new Error("This episode is no longer available.");
  return klartextArticle(data.episode);
}

// MARK: - Wikipedia

const wiki = (params) => getJSON(`${WIKI_API}?${new URLSearchParams({ format: "json", formatversion: "2", origin: "*", ...params })}`);

/** Articles matching a search, or a handful of random ones. */
export async function wikiList(search = "") {
  if (search.trim()) {
    const data = await wiki({ action: "query", list: "search", srsearch: search, srlimit: "20", srnamespace: "0" });
    return (data.query?.search ?? []).map((r) => ({ source: "wiki", id: r.title, title: r.title, summary: textOf(r.snippet) }));
  }
  const data = await wiki({
    action: "query", generator: "random", grnnamespace: "0", grnlimit: "12", prop: "extracts", exintro: "1", explaintext: "1", exsentences: "2",
  });
  return (data.query?.pages ?? []).map((p) => ({ source: "wiki", id: p.title, title: p.title, summary: p.extract ?? "" }));
}

async function wikiArticle(title) {
  const data = await wiki({ action: "query", prop: "extracts|info", explaintext: "1", exsectionformat: "wiki", inprop: "url", redirects: "1", titles: title });
  const page = data.query?.pages?.[0];
  if (!page || page.missing) throw new Error(`Swedish Wikipedia has no article called “${title}”.`);
  const paragraphs = [];
  let skipping = false;
  for (const line of (page.extract ?? "").split("\n")) {
    const heading = /^(=+)\s*(.*?)\s*\1$/.exec(line.trim());
    if (heading) {
      skipping = WIKI_SKIP.test(heading[2]);
      if (!skipping) paragraphs.push({ kind: "h", text: heading[2] });
    } else if (!skipping && line.trim()) {
      paragraphs.push({ kind: "p", text: line.trim() });
    }
  }
  // Drop headings left without text under them.
  const kept = paragraphs.filter((p, i) => p.kind === "p" || paragraphs[i + 1]?.kind === "p");
  return {
    source: "wiki", id: page.title, title: page.title, link: page.fullurl ?? WIKI + encodeURIComponent(page.title.replace(/ /g, "_")),
    paragraphs: kept, credit: SOURCES.wiki.credit,
  };
}

// MARK: - Articles

const cache = new Map();

/** The article for a source and id, fetched once per visit. */
export function loadArticle(source, id) {
  const key = `${source}/${id}`;
  if (!cache.has(key)) {
    const load = source === "8sidor" ? eightSidorArticle(id) : source === "klartext" ? klartextEpisode(id) : source === "wiki" ? wikiArticle(id)
      : Promise.reject(new Error("Unknown source."));
    cache.set(key, load.catch((e) => { cache.delete(key); throw e; }));
  }
  return cache.get(key);
}

// MARK: - Words and phrases

/**
 * Splits a paragraph into tokens: { text, word: true } for words (including hyphenated ones) and { text } for
 * everything between them. Words that start a multi-word dictionary entry get
 * `phrase: { length, entries }`, counted in words.
 */
export function tokenize(text) {
  const tokens = [];
  const re = /\p{L}+(?:[-’']\p{L}+)*/gu;
  let last = 0;
  for (const m of text.matchAll(re)) {
    if (m.index > last) tokens.push({ text: text.slice(last, m.index) });
    tokens.push({ text: m[0], word: true });
    last = m.index + m[0].length;
  }
  if (last < text.length) tokens.push({ text: text.slice(last) });
  // Phrases only run across words separated by plain spaces, not punctuation.
  const at = tokens.flatMap((t, k) => (t.word ? [k] : []));
  const words = at.map((k) => tokens[k]);
  for (let i = 0; i < words.length; i++) {
    let run = 1;
    for (let k = at[i]; run < 6 && tokens[k + 1] && /^ +$/.test(tokens[k + 1].text) && tokens[k + 2]?.word; k += 2) run += 1;
    if (run < 2) continue;
    const phrase = dictionary.phraseAt(words.slice(i, i + run).map((w) => w.text), 0);
    if (phrase) {
      words[i].phrase = phrase;
      for (let j = 1; j < phrase.length; j++) words[i + j].inPhrase = words[i];
    }
  }
  return tokens;
}

/** The sentence of `text` around character `offset`. */
export function sentenceAt(text, offset) {
  const before = text.slice(0, offset);
  const start = Math.max(...[". ", "! ", "? ", ": "].map((s) => before.lastIndexOf(s) + (before.lastIndexOf(s) >= 0 ? 2 : 0)), 0);
  const end = text.slice(offset).search(/[.!?](\s|$)/);
  return text.slice(start, end < 0 ? text.length : offset + end + 1).trim();
}

/** "27 okt." style date in Swedish. */
export const articleDate = (ms) => (ms ? new Date(ms).toLocaleDateString("sv-SE", { day: "numeric", month: "short", year: new Date(ms).getFullYear() === new Date().getFullYear() ? undefined : "numeric" }) : "");
