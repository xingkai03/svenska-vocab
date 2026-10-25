// Shared pieces: icons, routing, and the small views used on several screens (Shared.swift in the app).

import { html } from "../vendor/preact-htm.js";
import { dictionary, headword, HINT_LANGUAGES, hintSentence, shortPos } from "./dictionary.js";
import { Kbd } from "./keys.js";
import { speak } from "./speech.js";

// MARK: - Icons (24 × 24, drawn with the current text color)

const PATHS = {
  sun: '<circle cx="12" cy="12" r="4.5" fill="currentColor"/><path d="M12 1.5v3M12 19.5v3M1.5 12h3M19.5 12h3M4.6 4.6l2.1 2.1M17.3 17.3l2.1 2.1M4.6 19.4l2.1-2.1M17.3 6.7l2.1-2.1"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.5 15.5 21 21"/>',
  books: '<rect x="3" y="4" width="4.5" height="16" rx="1" fill="currentColor"/><rect x="9.5" y="4" width="4.5" height="16" rx="1" fill="currentColor"/><path d="m16 5.5 3.6-1 3 15.4-3.6 1z" fill="currentColor" stroke="none"/>',
  chart: '<rect x="3" y="12" width="4" height="9" rx="1" fill="currentColor"/><rect x="10" y="7" width="4" height="14" rx="1" fill="currentColor"/><rect x="17" y="3" width="4" height="18" rx="1" fill="currentColor"/>',
  gear: '<circle cx="12" cy="12" r="3.2"/><path d="M12 2.5v2.4M12 19.1v2.4M2.5 12h2.4M19.1 12h2.4M5.3 5.3 7 7M17 17l1.7 1.7M5.3 18.7 7 17M17 7l1.7-1.7"/><circle cx="12" cy="12" r="7"/>',
  speaker: '<path d="M4 9h3.5L12 5v14l-4.5-4H4z" fill="currentColor"/><path d="M15.5 8.5a5 5 0 0 1 0 7M18.5 5.5a9 9 0 0 1 0 13"/>',
  slow: '<path d="M3 16c0-4.4 3.6-8 8-8s8 3.6 8 8z" fill="currentColor"/><path d="M19 13.5h1.8a1.7 1.7 0 0 0 0-3.4H19M5.5 16v3M16 16v3"/>',
  bookmark: '<path d="M6 3h12v18l-6-4.5L6 21z"/>',
  bookmarkFill: '<path d="M6 3h12v18l-6-4.5L6 21z" fill="currentColor"/>',
  bookmarkSlash: '<path d="M6 6v15l6-4.5 6 4.5V18M6 3h12v11M3 3l18 18"/>',
  star: '<path d="m12 3 2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z"/>',
  starFill: '<path d="m12 3 2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z" fill="currentColor"/>',
  flame: '<path d="M12 22c4 0 7-2.8 7-6.8 0-4.6-3.6-6.9-4.6-11.2-2.2 1.6-3.2 3.9-3 6.4-1.3-.9-2-2.2-2.2-3.6C6.6 9 5 11.6 5 15.2 5 19.2 8 22 12 22z" fill="currentColor" stroke="none"/>',
  circle: '<circle cx="12" cy="12" r="7"/>',
  check: '<path d="m4.5 12.5 5 5 10-11"/>',
  seal: '<path d="m12 2 2.4 1.8 3-.2.9 2.9 2.5 1.7-1 2.8 1 2.8-2.5 1.7-.9 2.9-3-.2L12 22l-2.4-1.8-3 .2-.9-2.9-2.5-1.7 1-2.8-1-2.8 2.5-1.7.9-2.9 3 .2z" fill="currentColor" stroke="none"/><path d="m8.2 12.2 2.6 2.6 5-5.4" stroke="var(--card)"/>',
  plus: '<path d="M12 4v16M4 12h16"/>',
  plusCircle: '<circle cx="12" cy="12" r="9"/><path d="M12 7.5v9M7.5 12h9"/>',
  chevronRight: '<path d="m9 5 7 7-7 7"/>',
  chevronLeft: '<path d="m15 5-7 7 7 7"/>',
  sparkles: '<path d="M10 3c.6 4.2 2.8 6.4 7 7-4.2.6-6.4 2.8-7 7-.6-4.2-2.8-6.4-7-7 4.2-.6 6.4-2.8 7-7zM18.5 14c.3 2 1.3 3 3.3 3.3-2 .3-3 1.3-3.3 3.3-.3-2-1.3-3-3.3-3.3 2-.3 3-1.3 3.3-3.3z" fill="currentColor" stroke="none"/>',
  cards: '<rect x="3" y="6" width="13" height="15" rx="2"/><path d="M8 3h11a2 2 0 0 1 2 2v12"/>',
  swap: '<path d="M4 8h15m-4-4 4 4-4 4M20 16H5m4 4-4-4 4-4"/>',
  list: '<path d="M9 6h12M9 12h12M9 18h12"/><circle cx="4.5" cy="6" r="1.2" fill="currentColor"/><circle cx="4.5" cy="12" r="1.2" fill="currentColor"/><circle cx="4.5" cy="18" r="1.2" fill="currentColor"/>',
  ear: '<path d="M7 9a5 5 0 0 1 10 0c0 3-3 4-3 7a3 3 0 0 1-6 .5"/><path d="M10 9.5a2 2 0 0 1 4 0c0 1.2-1.2 1.6-1.6 2.6"/>',
  keyboard: '<rect x="2.5" y="6" width="19" height="12" rx="2"/><path d="M6 10h.01M9.5 10h.01M13 10h.01M16.5 10h.01M7 14.5h10"/>',
  clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7v5l3 2"/>',
  trash: '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>',
  xCircle: '<circle cx="12" cy="12" r="9" fill="currentColor" stroke="none"/><path d="m9 9 6 6m0-6-6 6" stroke="var(--card)"/>',
  checkCircle: '<circle cx="12" cy="12" r="9" fill="currentColor" stroke="none"/><path d="m8 12.3 2.7 2.7 5.3-5.6" stroke="var(--card)"/>',
  person: '<circle cx="12" cy="12" r="9.5"/><circle cx="12" cy="10" r="3.2"/><path d="M6 18.5c1.4-2 3.5-3 6-3s4.6 1 6 3"/>',
  personPlus: '<circle cx="10" cy="8" r="3.5"/><path d="M3.5 20c.8-3.6 3.3-5.5 6.5-5.5 1.6 0 3 .5 4 1.3M18 13v7M14.5 16.5h7"/>',
  cloudOff: '<path d="M7 18h10a4 4 0 0 0 .8-7.9A6 6 0 0 0 6.3 9 4.5 4.5 0 0 0 7 18zM3 3l18 18"/>',
  sync: '<path d="M20 11a8 8 0 0 0-14.3-4.5M4 13a8 8 0 0 0 14.3 4.5"/><path d="M5 3v4h4M19 21v-4h-4"/>',
  download: '<path d="M12 4v11m-4.5-4.5L12 15l4.5-4.5M5 20h14"/>',
  upload: '<path d="M12 15V4M7.5 8.5 12 4l4.5 4.5M5 20h14"/>',
  note: '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 8h8M8 12h8M8 16h5"/>',
  party: '<path d="m3 21 5-14 9 9z" fill="currentColor" stroke="none"/><path d="M14 3c.5 1.5 0 3-1.5 3.5M20 10c-1.5-.5-3 0-3.5 1.5M17 4l.01 0M21 6.5l.01 0M19.5 2l.01 0"/>',
  trophy: '<path d="M7 4h10v5a5 5 0 0 1-10 0z" fill="currentColor"/><path d="M7 6H4a3 3 0 0 0 3 4M17 6h3a3 3 0 0 1-3 4M12 14v3M8 21h8M9.5 17h5"/>',
  target: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.3" fill="currentColor"/>',
  repeat: '<path d="M4 12a8 8 0 0 1 13.7-5.6L20 8.7M20 4v4.7h-4.7M20 12a8 8 0 0 1-13.7 5.6L4 15.3M4 20v-4.7h4.7"/>',
  sort: '<path d="M7 4v16m-3.5-3.5L7 20l3.5-3.5M17 20V4m-3.5 3.5L17 4l3.5 3.5"/>',
  filter: '<circle cx="12" cy="12" r="9.5" fill="currentColor" stroke="none"/><path d="M7.5 9h9M9.5 12.5h5M11 16h2" stroke="var(--card)"/>',
  tv: '<rect x="2.5" y="4.5" width="19" height="13" rx="2"/><path d="M8 21h8M10.5 8.5v5l4-2.5z"/>',
  dictionary: '<path d="M5 4.5A1.5 1.5 0 0 1 6.5 3H19v15H6.5A1.5 1.5 0 0 0 5 19.5zM5 19.5A1.5 1.5 0 0 0 6.5 21H19"/><path d="M9.5 13 12 7l2.5 6M10.3 11h3.4"/>',
};

export function Icon({ name, class: cls = "" }) {
  return html`<svg class=${`icon ${cls}`} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
    stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" dangerouslySetInnerHTML=${{ __html: PATHS[name] ?? "" }} />`;
}

// MARK: - Routing (#/today, #/word/hund%23noun, #/review/flashcards?practice=1, …)

export function parseRoute() {
  const raw = location.hash.replace(/^#\/?/, "");
  const [path, search = ""] = raw.split("?");
  const parts = path.split("/").filter(Boolean).map(decodeURIComponent);
  return { name: parts[0] || "today", args: parts.slice(1), query: Object.fromEntries(new URLSearchParams(search)), hash: location.hash };
}

export function href(...parts) {
  let query = "";
  if (parts.length && typeof parts[parts.length - 1] === "object") {
    const q = new URLSearchParams(parts.pop()).toString();
    if (q) query = `?${q}`;
  }
  return `#/${parts.map(encodeURIComponent).join("/")}${query}`;
}

export function go(...parts) {
  location.hash = href(...parts);
}

/** Back within the app, or to `fallback` when the page was opened directly. */
export function back(fallback = "today") {
  if (navigated) history.back();
  else go(fallback);
}

let navigated = false;
addEventListener("hashchange", () => (navigated = true));

// MARK: - Navigation bar

/** `large` shows an iOS-style large title, as on the tab roots. */
export function NavBar({ title, large = false, backTo, backLabel = "Back", left, right, children }) {
  return html`
    <header class=${`navbar ${large ? "large" : ""}`}>
      <div class="navbar-row">
        <div class="navbar-side">
          ${backTo ? html`<button class="bar-button back" onClick=${() => back(backTo)}><${Icon} name="chevronLeft" />${backLabel}</button>` : left}
        </div>
        <div class="navbar-title">${title}</div>
        <div class="navbar-side right">${right}</div>
      </div>
      ${large ? html`<div class="large-title">${title}</div>` : null}
      ${children}
    </header>`;
}

// MARK: - Small views

/** Speaker button; `hotkey` names its keyboard shortcut, shown next to it on computers. */
export function SpeakButton({ text, slow = false, size = "", hotkey }) {
  const label = slow ? "Pronounce slowly" : "Pronounce";
  return html`<span class="speak"><button class=${`icon-button ${size}`} onClick=${(e) => { e.stopPropagation(); e.preventDefault(); speak(text, { slow }); }}
    aria-label=${label} title=${hotkey ? `${label} (${hotkey === "P" ? "Shift+P" : hotkey.toUpperCase()})` : label}>
    <${Icon} name=${slow ? "slow" : "speaker"} />
  </button>${hotkey ? html`<${Kbd} k=${hotkey} />` : null}</span>`;
}

export function PosTag({ entry }) {
  return html`<span class="tag">${entry.gender ? `${entry.gender}-word` : shortPos(entry.partOfSpeech)}</span>`;
}

/** CEFR level ("A2") from the Kelly list; draws nothing for words without a level. */
export function LevelBadge({ level }) {
  return level ? html`<span class="tag level" aria-label=${`Level ${level}`}>${level}</span>` : null;
}

/** Small horizontal bar showing the forgetting-curve retention of a word. */
export function MemoryBar({ retention }) {
  const color = retention < 0.5 ? "var(--red)" : retention < 0.8 ? "var(--orange)" : "var(--green)";
  const width = Math.max(0.03, Math.min(retention, 1)) * 100;
  return html`<div class="memory-bar" role="img" aria-label=${`Memory strength ${Math.round(retention * 100)} percent`}>
    <div style=${{ width: `${width}%`, background: color }}></div></div>`;
}

/** One-line German/French memory hint for list rows: "🇩🇪 Fenster · 🇫🇷 fenêtre". Draws nothing without hints. */
export function HintCaption({ word, partOfSpeech }) {
  const hints = dictionary.hints(word, partOfSpeech);
  if (!hints.length) return null;
  return html`<div class="caption secondary" aria-label=${hints.map(hintSentence).join(". ")}>
    ${hints.map((h) => `${HINT_LANGUAGES[h.language].flag} ${h.word}`).join(" · ")}</div>`;
}

/** "🇩🇪 Fenster · 🇫🇷 fenêtre" under the translation, for learn and review cards. */
export function HintLines({ word, partOfSpeech }) {
  const hints = dictionary.hints(word, partOfSpeech);
  if (!hints.length) return null;
  return html`<div class="subheadline secondary" aria-label=${hints.map(hintSentence).join(". ")}>
    ${hints.map((h) => `${HINT_LANGUAGES[h.language].flag} ${h.word}`).join(" · ")}</div>`;
}

/** A list row for a dictionary entry. */
export function EntryRow({ entry, saved, onOpen }) {
  return html`<a class="cell" href=${href("word", entry.id)} onClick=${onOpen}>
    <div class="cell-main">
      <div class="row" style="gap:6px"><span class="headline">${entry.word}</span><${PosTag} entry=${entry} /><${LevelBadge} level=${entry.level} /></div>
      <div class="subheadline secondary clamp2">${entry.translation}</div>
      <${HintCaption} word=${entry.word} partOfSpeech=${entry.partOfSpeech} />
    </div>
    ${saved ? html`<span class="accent"><${Icon} name="bookmarkFill" /></span>` : null}
    <span class="chevron"><${Icon} name="chevronRight" /></span>
  </a>`;
}

export function Section({ header, footer, children, headerRight }) {
  return html`<section class="section">
    ${header || headerRight ? html`<div class="section-header"><span>${header}</span>${headerRight}</div>` : null}
    <div class="list">${children}</div>
    ${footer ? html`<div class="section-footer">${footer}</div>` : null}
  </section>`;
}

export function Segmented({ options, value, onChange, label }) {
  return html`<div class="segmented" role="radiogroup" aria-label=${label}>
    ${options.map(([v, text]) => html`<button role="radio" aria-checked=${v === value} class=${v === value ? "on" : ""}
      onClick=${() => onChange(v)}>${text}</button>`)}
  </div>`;
}

export function Toggle({ label, checked, onChange }) {
  return html`<label class="cell"><span class="cell-main">${label}</span>
    <input type="checkbox" class="switch" checked=${checked} onChange=${(e) => onChange(e.currentTarget.checked)} /></label>`;
}

export function Stepper({ label, value, min, max, step, onChange }) {
  return html`<div class="cell"><span class="cell-main">${label}</span>
    <span class="stepper">
      <button aria-label="Decrease" disabled=${value <= min} onClick=${() => onChange(Math.max(min, value - step))}>−</button>
      <button aria-label="Increase" disabled=${value >= max} onClick=${() => onChange(Math.min(max, value + step))}>+</button>
    </span></div>`;
}

export function EmptyState({ icon, title, children }) {
  return html`<div class="empty"><${Icon} name=${icon} /><h2>${title}</h2><div>${children}</div></div>`;
}

export { headword };

// MARK: - Formatting

export const percent = (x) => `${Math.round(x * 100)}%`;

const relativeFormat = new Intl.RelativeTimeFormat("en", { numeric: "auto" });

/** "in 3 days", "yesterday", "now". */
export function relative(t, now = Date.now()) {
  const seconds = (t - now) / 1000;
  const units = [["year", 31_536_000], ["month", 2_592_000], ["week", 604_800], ["day", 86_400], ["hour", 3600], ["minute", 60]];
  for (const [unit, size] of units) {
    if (Math.abs(seconds) >= size) return relativeFormat.format(Math.round(seconds / size), unit);
  }
  return "now";
}
