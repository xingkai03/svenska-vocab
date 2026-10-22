import { html, useState } from "../../vendor/preact-htm.js";
import { fold, LEVELS } from "../dictionary.js";
import { formatInterval, isDue, isToday, mastery, retention, startOfDay, DAY } from "../scheduler.js";
import { useKeys } from "../keys.js";
import { store } from "../store.js";
import { EmptyState, Icon, LevelBadge, MemoryBar, NavBar, Segmented, go, href } from "../ui.js";

const FILTERS = [["all", "All"], ["due", "Due"], ["learning", "Learning"], ["mastered", "Mastered"], ["favorites", "★"]];
const SORTS = [["recent", "Recently added"], ["alphabetical", "A–Z"], ["due", "Next review"], ["weakest", "Weakest memory"]];
const collator = new Intl.Collator("sv");

// Filter, sort and search stay put while moving between tabs, like the app's tab state.
const view = { filter: "all", sort: "recent", level: "", search: "" };

export function WordsView() {
  const [, rerender] = useState(0);
  const set = (patch) => {
    Object.assign(view, patch);
    rerender((n) => n + 1);
  };
  const words = [...store.words.values()].sort((a, b) => b.addedAt - a.addedAt);
  const q = fold(view.search);
  const now = Date.now();
  let visible = words.filter((w) => {
    const m = mastery(w);
    const matches = {
      all: true,
      due: isDue(w, now),
      learning: m === "New" || m === "Learning",
      mastered: m === "Mastered" || m === "Familiar",
      favorites: w.isFavorite,
    }[view.filter];
    return matches && (!view.level || w.level === view.level)
      && (!q || fold(w.word).includes(q) || fold(w.translation).includes(q));
  });
  if (view.sort === "alphabetical") visible = visible.sort((a, b) => collator.compare(a.word, b.word));
  else if (view.sort === "due") visible = visible.sort((a, b) => a.dueDate - b.dueDate);
  else if (view.sort === "weakest") visible = visible.sort((a, b) => retention(a, now) - retention(b, now));

  const anyDue = words.some((w) => isDue(w, now));
  useKeys([
    ...FILTERS.map(([v, t], i) => [[String(i + 1)], `Show ${t === "★" ? "favorites" : t.toLowerCase()}`, () => set({ filter: v })]),
    [["o"], "Change the sort order", () => set({ sort: SORTS[(SORTS.findIndex((x) => x[0] === view.sort) + 1) % SORTS.length][0] })],
    [["r"], "Review", words.length && (() => go("review", "flashcards", anyDue ? {} : { practice: 1 }))],
    [["n"], "Add a word", () => go("new")],
  ]);

  return html`
    <${NavBar} title="My words" large
      right=${html`
        ${words.length ? html`<button class="bar-button" title="Review" aria-label="Review"
          onClick=${() => go("review", "flashcards", anyDue ? {} : { practice: 1 })}><${Icon} name="cards" /></button>` : null}
        <button class="bar-button" title="Add word" aria-label="Add word" onClick=${() => go("new")}><${Icon} name="plus" /></button>`}>
      <div class="page"><label class="search"><${Icon} name="search" />
        <input type="search" placeholder="Filter my words" value=${view.search} onInput=${(e) => set({ search: e.currentTarget.value })} aria-label="Filter my words" />
      </label></div>
    <//>
    <div class="page">
      <div style="margin-top:12px"><${Segmented} label="Filter" options=${FILTERS} value=${view.filter} onChange=${(filter) => set({ filter })} /></div>
      <div class="row wrap" style="margin-top:10px;gap:8px">
        <select class="menu" aria-label="Sort" value=${view.sort} onChange=${(e) => set({ sort: e.currentTarget.value })}>
          ${SORTS.map(([v, t]) => html`<option value=${v}>${t}</option>`)}
        </select>
        <select class="menu" aria-label="Level" value=${view.level} onChange=${(e) => set({ level: e.currentTarget.value })}>
          <option value="">All levels</option>
          ${LEVELS.map((l) => html`<option value=${l}>${l}</option>`)}
        </select>
      </div>
      ${words.length === 0
        ? html`<${EmptyState} icon="books" title="No words yet">Save words from Lookup, or use Learn new words on the Today tab.<//>`
        : html`<section class="section">
            <div class="section-header"><span>${visible.length} words</span></div>
            <div class="list">${visible.map((w) => html`<${WordRow} key=${w.key} word=${w} now=${now} />`)}</div>
          </section>`}
    </div>`;
}

function WordRow({ word, now }) {
  const due = isDue(word, now);
  const days = Math.max(1, Math.round((startOfDay(word.dueDate) - startOfDay(now)) / DAY));
  const when = due ? "due" : isToday(word.dueDate) ? "today" : formatInterval(days);
  return html`<a class="cell" href=${href("word", word.key)}>
    <div class="cell-main">
      <div class="row" style="gap:6px">
        <span class="headline">${word.word}</span><${LevelBadge} level=${word.level} />
        ${word.isFavorite ? html`<span class="yellow caption"><${Icon} name="starFill" /></span>` : null}
        <span class="spacer"></span>
        <span class=${`caption mono ${due ? "red" : "secondary"}`}>${when}</span>
      </div>
      <div class="subheadline secondary clamp1">${word.translation}</div>
      <${MemoryBar} retention=${retention(word, now)} />
    </div>
    <span class="chevron"><${Icon} name="chevronRight" /></span>
  </a>`;
}
