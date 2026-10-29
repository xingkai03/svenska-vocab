import { html, useEffect, useState } from "../../vendor/preact-htm.js";
import { LineChart } from "../charts.js";
import { dictionary, formList, headword, HINT_LANGUAGES } from "../dictionary.js";
import { isDue, mastery, retention, retentionAfter, DAY } from "../scheduler.js";
import { speak } from "../speech.js";
import { svt, svtTerms } from "../svt.js";
import { ReadingArticles } from "./read.js";
import { EpisodeCell } from "./svt.js";
import { useKeys } from "../keys.js";
import { store } from "../store.js";
import { EmptyState, ExampleText, Icon, LevelBadge, NavBar, PosTag, Section, SpeakButton, go, href, relative } from "../ui.js";

/** `onBack` is set when opened on top of a review: Back and Esc then return to the card instead of leaving the session,
 * and the word can't be removed while the session holds it. */
export function WordDetailView({ id, onBack }) {
  const saved = store.words.get(id);
  const entry = saved ?? dictionary.entry(id);

  useEffect(() => {
    if (entry && store.get("autoSpeak")) speak(entry.word);
  }, [id]);

  useKeys(entry ? [
    [["p"], "Pronounce", () => speak(entry.word)],
    [["P"], "Pronounce slowly", () => speak(entry.word, { slow: true })],
    [["x"], "Pronounce the example", entry.example && (() => speak(entry.example))],
    [["a"], "Add to my words", !saved && (() => store.addToCollection(entry))],
    [["f"], "Favorite", saved && (() => store.updateWord(id, { isFavorite: !saved.isFavorite }))],
    [["e"], "Edit", saved && (() => go("edit", id))],
    [["v"], "Search the word on SVT Play", () => go("svt", { q: entry.word })],
    [["m"], "Write a note", saved && (() => document.querySelector("main textarea")?.focus())],
    [["Delete", "Backspace"], "Remove from my words", saved && !onBack && (() => remove())],
    [["Escape", "d"], "Back to the review", onBack],
  ] : onBack ? [[["Escape", "d"], "Back to the review", onBack]] : []);

  if (!entry) {
    return html`<${NavBar} title="Word" backTo=${onBack ? null : "lookup"} left=${onBack && backButton(onBack)} />
      <div class="page"><${EmptyState} icon="search" title="Word not found">It may have been removed from your words.<//></div>`;
  }
  const level = entry.level || dictionary.entry(id)?.level || "";
  const forms = formList(entry);

  const remove = () => {
    if (confirm(`Remove “${entry.word}” and its review history?`)) store.deleteWord(id);
  };

  return html`
    <${NavBar} title=${entry.word} backTo=${onBack ? null : "lookup"} left=${onBack && backButton(onBack)} right=${saved ? html`
      <button class="bar-button" onClick=${() => store.updateWord(id, { isFavorite: !saved.isFavorite })} aria-label="Favorite" title="Favorite">
        <${Icon} name=${saved.isFavorite ? "starFill" : "star"} /></button>
      <button class="bar-button" onClick=${() => go("edit", id)}>Edit</button>` : null} />
    <div class="page">
      <${Section}>
        <div class="cell"><div class="cell-main" style="gap:8px">
          <div class="row baseline wrap" style="gap:8px">
            <span class="title" style="flex:1">${headword(entry)}</span><${PosTag} entry=${entry} /><${LevelBadge} level=${level} />
          </div>
          <div class="title3">${entry.translation}</div>
          <div class="row" style="gap:16px"><${SpeakButton} text=${entry.word} size="big" hotkey="p" /><${SpeakButton} text=${entry.word} slow size="big" hotkey="P" /></div>
        </div></div>
      <//>

      <${MemoryHint} word=${entry.word} partOfSpeech=${entry.partOfSpeech} />

      ${forms.length ? html`<${Section} header="Forms">
        ${forms.map((f) => html`<div class="cell"><span class="cell-main">${f}</span><${SpeakButton} text=${f} /></div>`)}
      <//>` : null}

      ${entry.example ? html`<${Section} header="Example">
        <div class="cell"><div class="cell-main">
          <${ExampleText} text=${entry.example} />
          ${entry.exampleTranslation ? html`<span class="subheadline secondary">${entry.exampleTranslation}</span>` : null}
        </div><${SpeakButton} text=${entry.example} hotkey="x" /></div>
      <//>` : null}

      <${SvtClips} word=${entry.word} forms=${forms} />
      <${ReadingArticles} word=${entry.word} />

      ${saved ? html`<${Memory} word=${saved} />
        <${Section} header="My note">
          <textarea class="text" rows="2" placeholder="Mnemonic, context, related words…" value=${saved.note}
            onInput=${(e) => store.updateWord(id, { note: e.currentTarget.value })}></textarea>
        <//>` : null}

      <${Section} footer=${entry.source === "online" ? "From Folkets lexikon, CC BY-SA 2.5." : null}>
        ${saved
          ? !onBack && html`<button class="cell destructive" onClick=${remove}><${Icon} name="bookmarkSlash" /> Remove from my words</button>`
          : html`<button class="cell action" onClick=${() => store.addToCollection(entry)}><${Icon} name="bookmark" /> Add to my words</button>`}
      <//>
    </div>`;
}

const backButton = (onBack) => html`<button class="bar-button back" onClick=${onBack} title="Back to the review (Esc)">
  <${Icon} name="chevronLeft" />Review</button>`;

/** German and French look-alikes, for learners who know those languages. */
function MemoryHint({ word, partOfSpeech }) {
  const hints = dictionary.hints(word, partOfSpeech);
  if (!hints.length) return null;
  const explanation = (h) => {
    const name = HINT_LANGUAGES[h.language].name;
    if (h.kind === "same") return `Spelled the same in ${name}, same meaning.`;
    if (h.kind === "similar") return `${name} word with the same meaning that looks alike.`;
    return `Swedish borrowed “${word}” from this ${name} word.`;
  };
  return html`<${Section} header="Memory hint" footer="Look-alike words from Wiktionary (WikDict, kaikki.org), CC BY-SA 4.0.">
    ${hints.map((h) => html`<div class="cell"><span class="title3">${HINT_LANGUAGES[h.language].flag}</span>
      <div class="cell-main"><span class="headline">${h.word}</span><span class="subheadline secondary">${explanation(h)}</span></div></div>`)}
  <//>`;
}

/** The newest SVT Play episodes where the word or one of its forms is said. Draws nothing until clips are found. */
function SvtClips({ word, forms }) {
  const [found, setFound] = useState(null);
  const terms = [...new Set([word, ...forms].flatMap((w) => { const t = svtTerms(w); return t.length === 1 ? t : []; }))];
  useEffect(() => {
    let current = true;
    if (terms.length) svt.search(terms, { anyOf: true }).then((r) => current && setFound(r.results), () => {});
    return () => { current = false; };
  }, [terms.join(" ")]);
  if (!found?.length) return null;
  return html`<${Section} header="Heard on SVT Play" footer="Opens SVT Play just before the word is said; some programmes can only be watched in Sweden.">
    ${found.slice(0, 3).map((r) => html`<${EpisodeCell} ...${r} max=${4} />`)}
    <a class="cell action" href=${href("svt", { q: word })}><${Icon} name="tv" /> Search “${word}” on SVT Play</a>
  <//>`;
}

/** Spaced-repetition status plus the word's personal forgetting curve. */
function Memory({ word }) {
  const reviewed = word.lastReviewedAt != null;
  const horizon = Math.max(14, Math.min(120, word.interval * 2));
  const elapsed = reviewed ? (Date.now() - word.lastReviewedAt) / DAY : 0;
  const points = [];
  for (let step = 0; step <= horizon * 2; step++) points.push([step / 2, retentionAfter(step / 2, word.interval)]);
  return html`<${Section} header="Memory" footer=${reviewed
      ? "Each successful review flattens the curve, so the next review can wait longer."
      : "Review this word once to start its forgetting curve."}>
    <div class="cell"><span class="cell-main">Level</span><span class="value">${mastery(word)}</span></div>
    <div class="cell"><span class="cell-main">Next review</span><span class="value">${isDue(word) ? "Now" : relative(word.dueDate)}</span></div>
    <div class="cell"><span class="cell-main">Reviews</span><span class="value">${word.reviewCount} (${word.lapses} forgotten)</span></div>
    ${reviewed ? html`
      <div class="cell"><span class="cell-main">Memory now</span><span class="value">${Math.round(retention(word) * 100)}%</span></div>
      <div class="cell"><div class="cell-main">
        <${LineChart} height=${150} xMax=${horizon} yTicks=${[0, 0.5, 0.9, 1]} xLabel="days since last review"
          series=${[{ color: "var(--accent)", points, fill: true }]}
          marker=${{ x: Math.min(elapsed, horizon), label: "now", color: "var(--orange)" }}
          ariaLabel="Forgetting curve of this word" />
      </div></div>` : null}
  <//>`;
}
