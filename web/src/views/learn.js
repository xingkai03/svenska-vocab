import { html, useEffect, useState } from "../../vendor/preact-htm.js";
import { deckEntries, dictionary, formList, GROUP_ORDER, headword, LEVELS } from "../dictionary.js";
import { speak, speakWithExample } from "../speech.js";
import { Kbd, useKeys } from "../keys.js";
import { store } from "../store.js";
import { EmptyState, ExampleText, HintLines, LevelBadge, NavBar, PosTag, Segmented, SpeakButton } from "../ui.js";

const TYPES = [["all", "All"], ["noun", "Nouns"], ["verb", "Verbs"], ["adjective", "Adjectives"], ["other", "Other"]];

function matchesType(e, type) {
  if (type === "all") return true;
  if (type === "other") return !["noun", "verb", "adjective"].includes(e.partOfSpeech);
  return e.partOfSpeech === type;
}

/** Familiar or Mastered: reviewed, and remembered for at least a week. Words marked "I know it" count too. */
const isMastered = (w) => w.reviewCount > 0 && w.interval >= 7;

/** Matches a word across word lists whatever its part of speech: lowercased, without a leading en/ett/att. */
export function wordKey(word) {
  const t = word.toLowerCase().trim();
  for (const prefix of ["en ", "ett ", "att "]) {
    if (t.startsWith(prefix) && t.length > prefix.length) return t.slice(prefix.length).trim();
  }
  return t;
}

let cache = { revision: -1, saved: null, progress: new WeakMap() };

/**
 * Saved words by wordKey → whether mastered (a word saved from one list counts in every list that has it), and each
 * list's progress. Kept until the collection changes: the list picker shows progress for every list on each render.
 */
function savedProgress() {
  const revision = store.revision.words ?? 0;
  if (cache.revision !== revision || !cache.saved) {
    const saved = new Map();
    for (const w of store.words.values()) {
      const k = wordKey(w.word);
      saved.set(k, saved.get(k) || isMastered(w));
    }
    cache = { revision, saved, progress: new WeakMap() };
  }
  const { saved, progress: counts } = cache;
  const progress = (entries) => {
    let result = counts.get(entries);
    if (result) return result;
    let mastered = 0, learning = 0;
    for (const e of entries) {
      const m = saved.get(wordKey(e.word));
      if (m === undefined) continue;
      if (m) mastered += 1;
      else learning += 1;
    }
    result = { mastered, learning };
    counts.set(entries, result);
    return result;
  };
  return { saved, progress };
}

/** Learn new words from the core vocabulary, a Kelly CEFR list or another word list, optionally one chapter at a time. */
export function LearnView() {
  const [chapter, setChapter] = useState("");
  const [type, setType] = useState("all");
  const [added, setAdded] = useState(0);
  /** The word just marked "I know it" (saved as mastered), until the next answer. */
  const [lastKnown, setLastKnown] = useState(null);

  const decks = dictionary.customDecks;
  // "core", a CEFR level ("A1" … "C2") or a word list id. A list that isn't on the web (e.g. a private list on
  // the iPhone) shows the core list here, without changing the choice the iPhone remembers.
  const chosen = store.get("discoverDeck");
  const customDeck = decks.find((d) => d.id === chosen);
  const deck = chosen === "core" || LEVELS.includes(chosen) || customDeck ? chosen : "core";
  const all = deck === "core" ? dictionary.coreEntries : customDeck ? deckEntries(customDeck, chapter) : dictionary.deck(deck);

  const { saved, progress } = savedProgress();
  const remaining = all.filter((e) => !saved.has(wordKey(e.word)) && matchesType(e, type));
  const { mastered, learning } = progress(all);
  const entry = remaining[0];

  useEffect(() => {
    if (entry) speakWithExample(store.get("autoSpeak") && entry.word, entry.example);
  }, [entry?.id]);

  const label = (name, entries) => {
    if (!entries.length) return name;
    const p = progress(entries);
    return `${name} · ${p.mastered} mastered · ${p.learning} learning / ${entries.length}`;
  };
  const groups = new Map();
  for (const d of decks) groups.set(d.group, [...(groups.get(d.group) ?? []), d]);
  const order = (g) => (GROUP_ORDER.includes(g) ? GROUP_ORDER.indexOf(g) : GROUP_ORDER.length);
  const groupNames = [...groups.keys()].sort((a, b) => order(a) - order(b) || a.localeCompare(b));

  const skip = () => {
    store.markKnown(entry);
    setLastKnown(entry);
  };
  const undo = () => {
    store.deleteWord(lastKnown.id);
    setLastKnown(null);
  };
  const learn = () => {
    store.addToCollection(entry);
    setAdded((n) => n + 1);
    setLastKnown(null);
  };

  const cycleType = (step) => setType(TYPES[(TYPES.findIndex((t) => t[0] === type) + step + TYPES.length) % TYPES.length][0]);
  useKeys([
    [["ArrowRight", "Enter"], "Learn", entry && learn],
    [["ArrowLeft", "i"], "I know it", entry && skip],
    [["z", "Mod+z"], "Undo “I know it”", lastKnown && undo],
    [["p"], "Pronounce", entry && (() => speak(entry.word))],
    [["P"], "Pronounce slowly", entry && (() => speak(entry.word, { slow: true }))],
    [["x"], "Pronounce the example", entry?.example && (() => speak(entry.example))],
    [["]"], "Next word type", () => cycleType(1)],
    [["["], "Previous word type", () => cycleType(-1)],
  ]);

  return html`
    <${NavBar} title="Learn new words" backTo="today" backLabel="Today" />
    <div class="page"><div class="stack" style="gap:20px">
      <div class="row wrap" style="gap:8px;justify-content:center">
        <select class="menu" aria-label="Word list" value=${deck} onChange=${(e) => { store.set("discoverDeck", e.currentTarget.value); setChapter(""); }}>
          <option value="core">${label("Core", dictionary.coreEntries)}</option>
          <optgroup label="CEFR levels (Kelly)">
            ${LEVELS.map((l) => html`<option value=${l}>${label(l, dictionary.deck(l))}</option>`)}
          </optgroup>
          ${groupNames.map((g) => html`<optgroup label=${g}>
            ${groups.get(g).map((d) => html`<option value=${d.id}>${label(d.name, d.entries)}</option>`)}
          </optgroup>`)}
        </select>
        ${customDeck?.chapters.length ? html`<select class="menu" aria-label="Chapter" value=${chapter} onChange=${(e) => setChapter(e.currentTarget.value)}>
          <option value="">All chapters</option>
          ${customDeck.chapters.map((c) => html`<option value=${c}>${c}</option>`)}
        </select>` : null}
      </div>

      <${Segmented} label="Type" options=${TYPES} value=${type} onChange=${setType} />

      ${all.length ? html`<div style="display:flex;flex-direction:column;gap:4px">
        <div class="progress"><div style=${{ width: `${((mastered + learning) / all.length) * 100}%` }}></div></div>
        <div class="caption secondary center">${mastered} mastered · ${learning} learning · ${all.length} words</div>
      </div>` : null}

      ${entry ? html`
        <div class="caption secondary center">${remaining.length} words left · ${added} added this session${lastKnown ? html` ·${" "}<button class="btn plain caption" style="color:var(--accent)" onClick=${undo}>Undo “I know it”<${Kbd} k="z" /></button>` : null}</div>
        <div class="flashcard slide-in" key=${entry.id}>
          <div class="row" style="gap:6px"><${PosTag} entry=${entry} /><${LevelBadge} level=${entry.level} /></div>
          <div class="big-word">${headword(entry)}</div>
          <div class="row" style="gap:24px"><${SpeakButton} text=${entry.word} size="big" hotkey="p" /><${SpeakButton} text=${entry.word} slow size="big" hotkey="P" /></div>
          <div class="title3">${entry.translation}</div>
          <${HintLines} word=${entry.word} partOfSpeech=${entry.partOfSpeech} />
          ${formList(entry).length ? html`<div class="subheadline secondary">${formList(entry).join(" · ")}</div>` : null}
          ${entry.example ? html`<hr />
            <${ExampleText} text=${entry.example} />
            <div class="subheadline secondary">${entry.exampleTranslation}</div>
            <${SpeakButton} text=${entry.example} hotkey="x" />` : null}
        </div>
        <div class="row" style="gap:16px">
          <button class="btn large full" onClick=${skip}>✓ I know it<${Kbd} k="ArrowLeft" /></button>
          <button class="btn large full prominent" onClick=${learn}>+ Learn<${Kbd} k="ArrowRight" /></button>
        </div>`
      : html`<${EmptyState} icon="seal" title="You've seen them all">Look up more words, or pick another word list.<//>`}
    </div></div>`;
}
