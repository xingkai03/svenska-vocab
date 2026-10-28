// Swedish ⇄ English lookup over the same bundled data as the app: the curated core vocabulary, the full
// Folkets lexikon (KTH, CC BY-SA 2.5), Kelly CEFR levels and the open word lists (scripts/build_web.py copies
// them into web/data). A port of DictionaryService.swift and WordDecks.swift.

import { DAY, startOfDay } from "./scheduler.js";
import { entryId, store } from "./store.js";

export const LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"];

export const HINT_LANGUAGES = {
  de: { name: "German", flag: "🇩🇪", setting: "knowsGerman" },
  fr: { name: "French", flag: "🇫🇷", setting: "knowsFrench" },
};

/** "Same as German Hund", "Like French école", "From French billet". */
export function hintSentence(h) {
  const name = HINT_LANGUAGES[h.language].name;
  return `${h.kind === "same" ? "Same as" : h.kind === "similar" ? "Like" : "From"} ${name} ${h.word}`;
}
export const MY_LISTS = "My lists";
/** Picker sections in display order; groups not listed here come after them. */
export const GROUP_ORDER = ["Coursebook", "Spoken frequency", "Topics", "Special lists", MY_LISTS];

export const POS_ALL = ["noun", "verb", "adjective", "adverb", "pronoun", "preposition",
  "conjunction", "numeral", "interjection", "phrase"];

const SHORT_POS = {
  noun: "n.", verb: "v.", adjective: "adj.", adverb: "adv.", pronoun: "pron.", preposition: "prep.",
  conjunction: "conj.", numeral: "num.", interjection: "interj.", phrase: "phr.",
};
export const shortPos = (pos) => SHORT_POS[pos] ?? pos;

/** Lowercased and diacritic-folded, so "a" also finds "å" and "ä" on keyboards without Swedish letters. */
export const fold = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();

export const formList = (e) => (e.forms ?? "").split(",").map((f) => f.trim()).filter(Boolean);

/** Word with its article for nouns ("en bil") or infinitive marker for verbs ("att springa"). */
export function headword(e) {
  if (e.gender) return `${e.gender} ${e.word}`;
  if (e.partOfSpeech === "verb") return `att ${e.word}`;
  return e.word;
}

function makeEntry(c, source = "bundled") {
  const col = (i) => (i < c.length ? c[i] : "");
  return {
    word: col(0), partOfSpeech: col(1), gender: col(2), forms: col(3), translation: col(4),
    example: col(5), exampleTranslation: col(6), source, level: "",
  };
}

function parseDictionary(text, seen) {
  const result = [];
  for (const line of text.split("\n")) {
    if (!line || line.startsWith("#")) continue;
    const c = line.split("\t");
    if (c.length < 5) continue;
    const entry = makeEntry(c);
    const id = entryId(entry);
    if (seen.has(id)) continue;
    seen.add(id);
    entry.id = id;
    result.push(entry);
  }
  return result;
}

/** Ending → replacement pairs that undo common Swedish inflections: noun plurals, definite and genitive
 *  forms, verb tenses and participles, adjective agreement and comparison. Tried on words that are neither a
 *  headword nor a listed form, so "bilarna" finds "bil", "pratade" finds "prata", "fåglar" finds "fågel" and the imperative "stäng" finds "stänga". */
const INFLECTIONS = [
  ["arnas", ""], ["ernas", ""], ["ornas", "a"], ["arna", ""], ["erna", ""], ["orna", "a"], ["rna", ""],
  ["aste", ""], ["ades", "a"], ["ande", "a"], ["ende", ""], ["ade", "a"], ["are", ""], ["ast", ""],
  ["dde", ""], ["ens", ""], ["ets", ""], ["nas", ""], ["ats", "a"], ["es", "a"],
  ["ar", ""], ["er", ""], ["er", "a"], ["or", "a"], ["en", ""], ["en", "a"], ["et", ""], ["na", ""],
  ["ns", ""], ["at", "a"], ["ad", "a"], ["de", "a"], ["te", "a"], ["tt", ""], ["t", "a"],
  ["n", ""], ["r", ""], ["t", ""], ["s", ""], ["s", "a"], ["a", ""], ["e", ""], ["", "a"],
];

/** Headword spellings a word could be an inflection of, most likely first. Stems also lose a doubled final
 *  consonant ("mannen" → "man") or get back the e that falls out before an ending ("cyklar" → "cykel"). */
export function inflectionStems(word) {
  const w = word.toLowerCase();
  const result = [];
  if (w.length < 3) return result;
  const add = (s) => s.length >= 2 && s !== w && !result.includes(s) && result.push(s);
  for (const [ending, replacement] of INFLECTIONS) {
    if (!w.endsWith(ending)) continue;
    const stem = w.slice(0, w.length - ending.length);
    add(stem + replacement);
    if (!ending) add(`${stem}${stem.at(-1)}a`); // "glöm" → "glömma"
    if (replacement) continue;
    if (/([bdfgklmnprstv])\1$/.test(stem)) add(stem.slice(0, -1));
    if (/[^aeiouyåäö][lnr]$/.test(stem)) add(`${stem.slice(0, -1)}e${stem.slice(-1)}`);
  }
  return result;
}

/** Ranked search in both directions. Exact Swedish spelling ranks above diacritic-folded matches. */
class SearchIndex {
  constructor(entries, coreCount) {
    this.entries = entries;
    this.coreCount = coreCount;
    this.foldedWords = [];
    this.foldedTranslations = [];
    this.byExactWord = new Map();
    this.byWord = new Map();
    this.byForm = new Map();
    this.byToken = new Map();
    const push = (map, key, i) => {
      const list = map.get(key);
      if (list) list.push(i); else map.set(key, [i]);
    };
    entries.forEach((e, i) => {
      const w = fold(e.word);
      const t = fold(e.translation);
      this.foldedWords.push(w);
      this.foldedTranslations.push(t);
      push(this.byExactWord, e.word.toLowerCase(), i);
      push(this.byWord, w, i);
      for (const f of new Set(formList(e).map(fold))) push(this.byForm, f, i);
      // Single letters are mostly leftovers like the "s" in "someone's"; "I" is the exception.
      for (const k of new Set(t.split(/[^\p{L}\p{N}]+/u))) {
        if (k.length > 1 || k === "i") push(this.byToken, k, i);
      }
    });
    this.sorted = entries.map((_, i) => i)
      .sort((a, b) => (this.foldedWords[a] < this.foldedWords[b] ? -1 : this.foldedWords[a] > this.foldedWords[b] ? 1 : 0));
  }

  search(query, limit = 40) {
    const q = fold(query);
    if (!q) return { swedish: [], english: [], englishFirst: false };
    const score = new Map();
    const hits = [];
    const add = (ids, s) => {
      for (const i of ids ?? []) {
        if (!score.has(i)) {
          score.set(i, s);
          hits.push(i);
        }
      }
    };
    add(this.byExactWord.get(query.toLowerCase().trim()), 0);
    add(this.byWord.get(q), 1);
    add(this.byForm.get(q), 2);
    for (const stem of inflectionStems(query.trim())) add(this.byExactWord.get(stem), 2);
    add(this.byToken.get(q), 3);
    add(this.#prefixMatches(q), 4);
    // Substring matches rank last; skip the full scan when better matches already fill the list,
    // and for single letters, which would match nearly everything.
    if (hits.length < limit && q.length >= 2) {
      for (let i = 0; i < this.entries.length; i++) {
        if (score.has(i)) continue;
        if (this.foldedTranslations[i].includes(q)) score.set(i, 5);
        else if (this.foldedWords[i].includes(q)) score.set(i, 6);
        else continue;
        hits.push(i);
      }
    }
    // Ties: curated core words first, then shorter words.
    hits.sort((a, b) => score.get(a) - score.get(b)
      || (a < this.coreCount) !== (b < this.coreCount) && (a < this.coreCount ? -1 : 1)
      || this.foldedWords[a].length - this.foldedWords[b].length);
    // Scores 3 and 5 matched the translation; everything else matched the Swedish side.
    const isEnglish = (i) => score.get(i) === 3 || score.get(i) === 5;
    const swedish = hits.filter((i) => !isEnglish(i)).slice(0, limit).map((i) => this.entries[i]);
    const english = hits.filter(isEnglish).slice(0, limit).map((i) => this.entries[i]);
    return {
      swedish, english,
      englishFirst: !/[åäö]/i.test(query) && hits.length > 0 && score.get(hits[0]) === 3,
    };
  }

  /** Entries a word from running text is, or is an inflection of: the same spelling, a listed form, then a
   *  headword its ending can be undone to ("bilarna" → "bil"). Unlike search, never a prefix or substring match. */
  matches(word) {
    const w = word.toLowerCase();
    const found = [];
    const add = (ids, keep = () => true) => {
      for (const i of ids ?? []) if (!found.includes(i) && keep(this.entries[i])) found.push(i);
    };
    add(this.byExactWord.get(w));
    add(this.byForm.get(fold(w)), (e) => formList(e).some((f) => f.toLowerCase() === w));
    if (!found.length) for (const stem of inflectionStems(w)) add(this.byExactWord.get(stem));
    if (!found.length) add(this.byWord.get(fold(w)));
    return found.sort((a, b) => (a < this.coreCount) !== (b < this.coreCount) ? (a < this.coreCount ? -1 : 1) : 0)
      .map((i) => this.entries[i]);
  }

  /** Multi-word entries ("ta hand om", "tycker om") by their words, lower-cased and joined by spaces. */
  get phrases() {
    if (!this.#phrases) {
      this.#phrases = new Map();
      this.entries.forEach((e, i) => {
        for (const p of [e.word, ...formList(e)]) {
          const key = p.toLowerCase().replace(/\s+/g, " ").trim();
          if (!key.includes(" ") || /[^\p{L} -]/u.test(key)) continue;
          if (!this.#phrases.has(key)) this.#phrases.set(key, []);
          if (!this.#phrases.get(key).includes(i)) this.#phrases.get(key).push(i);
        }
      });
      this.phraseLength = Math.min(5, Math.max(2, ...[...this.#phrases.keys()].map((k) => k.split(" ").length)));
    }
    return this.#phrases;
  }

  #phrases = null;

  /** The longest multi-word entry starting at words[start]; the first word may be inflected ("tar hand om"). */
  phraseAt(words, start) {
    const phrases = this.phrases;
    for (let n = Math.min(this.phraseLength, words.length - start); n >= 2; n--) {
      const rest = words.slice(start + 1, start + n).map((w) => w.toLowerCase()).join(" ");
      const first = words[start].toLowerCase();
      for (const head of [first, ...inflectionStems(first)]) {
        const ids = phrases.get(`${head} ${rest}`);
        if (ids) return { length: n, entries: ids.map((i) => this.entries[i]) };
      }
    }
    return null;
  }

  #prefixMatches(prefix) {
    let low = 0, high = this.sorted.length;
    while (low < high) {
      const mid = (low + high) >> 1;
      if (this.foldedWords[this.sorted[mid]] < prefix) low = mid + 1; else high = mid;
    }
    const result = [];
    while (low < this.sorted.length && this.foldedWords[this.sorted[low]].startsWith(prefix)) {
      result.push(this.sorted[low]);
      low += 1;
    }
    return result;
  }
}

/** Fills in what a deck row leaves out from the bundled dictionaries. */
class DeckFiller {
  constructor(entries) {
    this.byID = new Map();
    this.byWord = new Map();
    for (const e of entries) {
      if (!this.byID.has(e.id)) this.byID.set(e.id, e);
      const w = e.word.toLowerCase();
      if (!this.byWord.has(w)) this.byWord.set(w, e);
    }
  }

  complete(row) {
    const r = { ...row };
    const exact = row.partOfSpeech ? this.byID.get(entryId(row)) : undefined;
    const match = exact ?? this.byWord.get(row.word.toLowerCase());
    if (!match) {
      if (!r.partOfSpeech) r.partOfSpeech = "phrase";
      return r;
    }
    if (!r.partOfSpeech) r.partOfSpeech = match.partOfSpeech;
    if (!r.translation) r.translation = match.translation;
    // Grammar and examples only carry over when it really is the same word.
    if (r.partOfSpeech !== match.partOfSpeech) return r;
    if (!r.gender) r.gender = match.gender;
    if (!r.forms) r.forms = match.forms;
    if (!r.example) {
      r.example = match.example;
      r.exampleTranslation = match.exampleTranslation;
    }
    r.level = match.level;
    return r;
  }
}

const capitalized = (s) => s.toLowerCase().replace(/(^|\s)(\S)/g, (_, a, b) => a + b.toUpperCase());

/** A word list file: optional `# deck:` and `# group:` lines, then rows like core_vocabulary.tsv plus a chapter. */
function loadDeck(fileName, text, imported, filler) {
  let name = capitalized(fileName.replace(/^deck_/, "").replace(/\.tsv$/i, "").replaceAll("_", " "));
  let group = MY_LISTS;
  const entries = [], entryChapters = [], seen = new Set();
  for (const line of text.split(/\r?\n/)) {
    if (!line) continue;
    if (line.startsWith("#")) {
      const comment = line.slice(1).trim();
      if (comment.toLowerCase().startsWith("deck:")) name = comment.slice(5).trim();
      else if (comment.toLowerCase().startsWith("group:") && !imported) group = comment.slice(6).trim();
      continue;
    }
    const c = line.split("\t").map((s) => s.trim());
    if (!c[0]) continue;
    const entry = filler.complete(makeEntry(c, "bundled"));
    entry.id = entryId(entry);
    if (!entry.translation || seen.has(entry.id)) continue;
    seen.add(entry.id);
    entries.push(entry);
    entryChapters.push(c[7] ?? "");
  }
  if (!entries.length) return null;
  const chapters = [...new Set(entryChapters.filter(Boolean))];
  return {
    id: (imported ? "imported/" : "bundled/") + fileName, fileName, name, group, entries, entryChapters, chapters,
    isImported: imported,
  };
}

export function deckEntries(deck, chapter) {
  if (!chapter) return deck.entries;
  return deck.entries.filter((_, i) => deck.entryChapters[i] === chapter);
}

class Dictionary {
  entries = [];
  coreEntries = [];
  isLoaded = false;
  #index = new SearchIndex([], 0);
  #levels = new Map();
  #bundledDecks = [];
  #filler = null;
  #byId = new Map();
  #imported = { revision: -1, decks: [] };
  #hints = new Map();
  #hintsByWord = new Map();

  async load(base = "data/") {
    const get = (path) => fetch(base + path).then((r) => {
      if (!r.ok) throw new Error(`Could not load ${path} (${r.status})`);
      return r.text();
    });
    const [core, folkets, kelly, deckNames, hints] = await Promise.all([
      get("core_vocabulary.tsv"), get("folkets_sv_en.tsv"), get("kelly_levels.tsv"),
      get("decks.json").then(JSON.parse), get("language_hints.tsv").catch(() => ""),
    ]);
    this.#loadHints(hints);
    const deckTexts = await Promise.all(deckNames.map((n) => get(`decks/${n}`)));

    const seen = new Set();
    const coreEntries = parseDictionary(core, seen);
    const all = coreEntries.concat(parseDictionary(folkets, seen));
    this.#applyLevels(all, kelly);
    this.coreEntries = coreEntries;
    this.entries = all;
    this.#index = new SearchIndex(all, coreEntries.length);
    this.#filler = new DeckFiller(all);
    this.#bundledDecks = deckNames.map((n, i) => loadDeck(n, deckTexts[i], false, this.#filler)).filter(Boolean);
    for (const e of all) this.#byId.set(e.id, e);
    for (const d of this.#bundledDecks) for (const e of d.entries) if (!this.#byId.has(e.id)) this.#byId.set(e.id, e);
    this.isLoaded = true;
  }

  /** Sets `level` from kelly_levels.tsv (word, pos, level, rank) and keeps each level's words in frequency order. */
  #applyLevels(entries, text) {
    const levels = new Map();
    for (const line of text.split("\n")) {
      if (!line || line.startsWith("#")) continue;
      const c = line.split("\t");
      const rank = Number(c[3]);
      if (c.length < 4 || !Number.isInteger(rank)) continue;
      levels.set(`${c[0].toLowerCase()}#${c[1]}`, { level: c[2], rank });
    }
    const ranked = new Map();
    for (const e of entries) {
      const match = levels.get(e.id);
      if (!match) continue;
      e.level = match.level;
      if (!ranked.has(match.level)) ranked.set(match.level, []);
      ranked.get(match.level).push([match.rank, e]);
    }
    for (const [level, list] of ranked) this.#levels.set(level, list.sort((a, b) => a[0] - b[0]).map((x) => x[1]));
  }

  /** language_hints.tsv: word, pos, language (de/fr), foreign word, kind (same/similar/from). */
  #loadHints(text) {
    for (const line of text.split("\n")) {
      if (!line || line.startsWith("#")) continue;
      const c = line.split("\t");
      if (c.length < 5 || !HINT_LANGUAGES[c[2]] || !["same", "similar", "from"].includes(c[4])) continue;
      const hint = { language: c[2], word: c[3], kind: c[4] };
      const key = `${c[0]}#${c[1]}`;
      if (!this.#hints.has(key)) this.#hints.set(key, []);
      this.#hints.get(key).push(hint);
      if (!this.#hintsByWord.has(c[0])) this.#hintsByWord.set(c[0], []);
      const forWord = this.#hintsByWord.get(c[0]);
      if (!forWord.some((h) => h.language === hint.language)) forWord.push(hint);
    }
  }

  /** German and French look-alikes of a word in the languages the learner knows (Settings), German first. */
  hints(word, partOfSpeech) {
    const known = Object.keys(HINT_LANGUAGES).filter((l) => store.get(HINT_LANGUAGES[l].setting));
    if (!known.length) return [];
    const key = word.toLowerCase();
    const found = (partOfSpeech ? this.#hints.get(`${key}#${partOfSpeech}`) : this.#hintsByWord.get(key)) ?? [];
    return found.filter((h) => known.includes(h.language)).sort((a, b) => (a.language === "de" ? -1 : 0) - (b.language === "de" ? -1 : 0));
  }

  /** Kelly words of one CEFR level ("A1" … "C2"), most useful first. */
  deck(level) {
    return this.#levels.get(level) ?? [];
  }

  /** Bundled word lists followed by the learner's imported ones. */
  get customDecks() {
    const revision = store.revision.lists ?? 0;
    if (this.#filler && this.#imported.revision !== revision) {
      const names = [...store.lists.keys()].sort();
      this.#imported = {
        revision,
        decks: names.map((n) => loadDeck(n, store.lists.get(n), true, this.#filler)).filter(Boolean),
      };
    }
    return this.#bundledDecks.concat(this.#imported.decks);
  }

  search(query, limit) {
    return this.#index.search(query, limit);
  }

  /** Dictionary entries for a word as it appears in a text, best first (see SearchIndex.matches). */
  matches(word) {
    return this.#index.matches(word);
  }

  /** { length, entries } for a multi-word entry starting at words[start], or null. */
  phraseAt(words, start) {
    return this.#index.phraseAt(words, start);
  }

  /** A dictionary or word list entry by key ("hund#noun"). */
  entry(id) {
    if (this.#byId.has(id)) return this.#byId.get(id);
    for (const d of this.customDecks) {
      const e = d.entries.find((x) => x.id === id);
      if (e) return e;
    }
    return undefined;
  }

  /** Same word every day as in the app, cycling through the core vocabulary. */
  wordOfTheDay(now = Date.now()) {
    if (!this.coreEntries.length) return undefined;
    // Day number counted like Calendar.ordinality(of: .day, in: .era): 2000-01-01 is day 730 122.
    const day = 730_122 + Math.round((startOfDay(now) - new Date(2000, 0, 1).getTime()) / DAY);
    // Stride by a prime so consecutive days are not neighbours in the frequency list.
    return this.coreEntries[(day * 7919) % this.coreEntries.length];
  }

  /** Random translations to use as wrong answers in multiple-choice questions. */
  distractors(correct, count) {
    const pool = new Set();
    for (let attempts = 0; pool.size < count && attempts < 200 && this.coreEntries.length; attempts++) {
      const t = this.coreEntries[Math.floor(Math.random() * this.coreEntries.length)].translation;
      if (t !== correct) pool.add(t);
    }
    return [...pool];
  }
}

export const dictionary = new Dictionary();

// Import

/** One CSV/TSV line split into trimmed fields; separators inside double quotes don't split. */
function fields(line, separator) {
  const result = [];
  let current = "", quoted = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"' && separator !== "\t") {
      if (quoted && line[i + 1] === '"') {
        current += ch;
        i += 1;
      } else {
        quoted = !quoted;
      }
    } else if (ch === separator && !quoted) {
      result.push(current);
      current = "";
    } else {
      current += ch;
    }
  }
  result.push(current);
  return result.map((s) => s.trim());
}

const POS_NAMES = [
  ["noun", ["noun", "n", "substantiv", "subst", "s"]],
  ["verb", ["verb", "v"]],
  ["adjective", ["adjective", "adj", "adjektiv"]],
  ["adverb", ["adverb", "adv"]],
  ["pronoun", ["pronoun", "pron", "pronomen"]],
  ["preposition", ["preposition", "prep"]],
  ["conjunction", ["conjunction", "conj", "konjunktion", "konj", "subjunktion", "subj"]],
  ["numeral", ["numeral", "num", "räkneord"]],
  ["interjection", ["interjection", "interj", "interjektion"]],
  ["phrase", ["phrase", "phr", "fras", "uttryck"]],
];

/** Maps common English and Swedish word-class names to the app's; unknown ones are left for the dictionary to fill. */
function partOfSpeech(raw) {
  const s = raw.toLowerCase().replace(/^[. ]+|[. ]+$/g, "");
  return POS_NAMES.find(([, names]) => names.includes(s))?.[0] ?? "";
}

/**
 * Converts a TSV/CSV word list into a deck file, the same way the app does, so imported lists sync both ways.
 * Columns: Swedish, English, then optionally part of speech, example and chapter, in that order or named in a
 * header row. Returns { fileName, content, count }.
 */
export function convertList(fileName, text) {
  const lines = text.split(/\r?\n|\r/).filter((l) => l.trim() && !l.startsWith("#"));
  if (!lines.length) throw new Error("No words found. Use one word per line: Swedish, English (tab or comma separated).");
  const separator = lines[0].includes("\t") ? "\t" : lines[0].includes(",") ? "," : ";";
  const rows = lines.map((l) => fields(l, separator));

  let columns = { swedish: 0, english: 1, pos: 2, example: 3, chapter: 4 };
  const aliases = {
    swedish: ["swedish", "svenska", "word", "ord", "sv"],
    english: ["english", "engelska", "translation", "översättning", "en"],
    pos: ["pos", "part of speech", "part_of_speech", "ordklass", "class", "type"],
    example: ["example", "exempel"],
    chapter: ["chapter", "kapitel", "lesson", "unit"],
  };
  const header = rows[0].map((h) => h.toLowerCase());
  const named = {};
  for (const [key, names] of Object.entries(aliases)) {
    const i = header.findIndex((h) => names.includes(h));
    if (i >= 0) named[key] = i;
  }
  if (named.swedish != null || named.english != null) {
    columns = named;
    rows.shift();
  }

  const name = fileName.replace(/\.[^.]*$/, "");
  let out = `# deck: ${name}\n`;
  let count = 0;
  for (const row of rows) {
    const value = (key) => (columns[key] != null && columns[key] < row.length ? row[columns[key]].replaceAll("\t", " ") : "");
    if (!value("swedish")) continue;
    out += [value("swedish"), partOfSpeech(value("pos")), "", "", value("english"), value("example"), "",
      value("chapter")].join("\t") + "\n";
    count += 1;
  }
  if (!count) throw new Error("No words found. Use one word per line: Swedish, English (tab or comma separated).");
  const slug = name.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean).join("_");
  return { fileName: `deck_${slug || "list"}.tsv`, content: out, count, name };
}
