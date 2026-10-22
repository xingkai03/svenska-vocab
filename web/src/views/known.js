import { html, useState } from "../../vendor/preact-htm.js";
import { dictionary, fold } from "../dictionary.js";
import { useKeys } from "../keys.js";
import { store } from "../store.js";
import { EmptyState, HintCaption, Icon, LevelBadge, NavBar, PosTag, Section, href } from "../ui.js";

/** Ids of the words marked "I know it" in Learn new words, oldest first (the synced skippedWords setting). */
export const knownIds = () => store.get("skippedWords").split("\n").filter(Boolean);

export function setKnownIds(ids) {
  store.set("skippedWords", ids.join("\n"));
}

/** A known word's entry; ids not in the dictionary fall back to the word and part of speech in "word#pos". */
function entryFor(id) {
  const entry = dictionary.entry(id);
  if (entry) return entry;
  const i = id.lastIndexOf("#");
  return { id, word: i < 0 ? id : id.slice(0, i), partOfSpeech: i < 0 ? "" : id.slice(i + 1), gender: "", translation: "", level: "" };
}

/** Words marked "I know it", newest first, with a way to put them back into Learn new words. */
export function KnownWordsView() {
  const [search, setSearch] = useState("");
  const ids = knownIds();
  const q = fold(search);
  const entries = ids.slice().reverse().map(entryFor)
    .filter((e) => !q || fold(e.word).includes(q) || fold(e.translation).includes(q));

  const unmark = (id) => setKnownIds(knownIds().filter((x) => x !== id));
  const learn = (entry) => {
    store.addToCollection(entry);
    unmark(entry.id);
  };
  const unmarkAll = () => {
    if (confirm(`Put all ${ids.length} known words back into Learn new words?`)) setKnownIds([]);
  };
  const selected = () => entries.find((e) => e.id === document.activeElement?.closest?.("[data-id]")?.dataset.id);
  useKeys([
    [["u"], "Unmark the selected word", entries.length && (() => selected() && unmark(selected().id))],
    [["a"], "Learn the selected word", entries.length && (() => selected() && learn(selected()))],
  ]);

  return html`
    <${NavBar} title="Known words" backTo="learn" backLabel="Learn"
      right=${ids.length ? html`<button class="bar-button" onClick=${unmarkAll}>Unmark all</button>` : null}>
      ${ids.length ? html`<div class="page"><label class="search"><${Icon} name="search" />
        <input type="search" placeholder="Search known words" value=${search} onInput=${(e) => setSearch(e.currentTarget.value)} aria-label="Search known words" />
      </label></div>` : null}
    <//>
    <div class="page">
      ${ids.length === 0
        ? html`<${EmptyState} icon="seal" title="No known words">Words you mark “I know it” in Learn new words show up here, so you can put them back.<//>`
        : html`<${Section} header=${`${entries.length} words`} footer="Unmark puts a word back into Learn new words. Learn adds it to your words.">
            ${entries.map((e) => html`<div class="cell" key=${e.id} data-id=${e.id}>
              <a class="cell-main" style="color:inherit" href=${href("word", e.id)}>
                <div class="row" style="gap:6px"><span class="headline">${e.word}</span><${PosTag} entry=${e} /><${LevelBadge} level=${e.level} /></div>
                ${e.translation ? html`<span class="subheadline secondary clamp2">${e.translation}</span>` : null}
                <${HintCaption} word=${e.word} partOfSpeech=${e.partOfSpeech} />
              </a>
              <button class="btn small" onClick=${() => unmark(e.id)}>Unmark</button>
              <button class="btn small prominent" onClick=${() => learn(e)}>Learn</button>
            </div>`)}
          <//>`}
    </div>`;
}
