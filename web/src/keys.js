// Keyboard control. Global keys switch tabs, focus search, move through lists and go back; each screen adds its own
// with useKeys(). "?" shows them all.

import { html, useEffect, useRef, useState } from "../vendor/preact-htm.js";
import { back, go, parseRoute } from "./ui.js";

const TAB_ROOTS = ["today", "lookup", "words", "summary"];

/** Screen layers, newest last; each holds [keys, label, run] entries. */
const layers = [];
let toggleHelp = () => {};
let helpOpen = false;

/**
 * Registers a screen's shortcuts while it is shown: [["Space", "Enter"], "Show answer", run]. Keys are KeyboardEvent.key
 * values, with "Space" for the space bar and a "Mod+" prefix for ⌘ (Mac) or Ctrl; "Mod+" keys also work while typing.
 * Entries with a falsy run are left out, so a screen can list keys that only apply some of the time.
 */
export function useKeys(entries) {
  const layer = useRef(null);
  if (!layer.current) layer.current = { entries: [] };
  layer.current.entries = entries.filter((e) => e && e[2]);
  useEffect(() => {
    layers.push(layer.current);
    return () => layers.splice(layers.indexOf(layer.current), 1);
  }, []);
}

const GLOBAL = [
  [["t"], "Today"],
  [["l"], "Lookup"],
  [["w"], "My words"],
  [["s"], "Summary"],
  [[","], "Settings"],
  [["/"], "Search"],
  [["j", "↓"], "Next item in a list"],
  [["k", "↑"], "Previous item in a list"],
  [["Enter"], "Open the selected item"],
  [["Esc"], "Back, or leave a text field"],
  [["?"], "Show or hide these shortcuts"],
];

const isTyping = (el) => el instanceof HTMLInputElement && !["checkbox", "radio", "range", "button", "submit"].includes(el.type)
  || el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement || el?.isContentEditable;

function keyName(e) {
  const key = e.key === " " ? "Space" : e.key;
  return e.metaKey || e.ctrlKey ? `Mod+${key.length === 1 ? key.toLowerCase() : key}` : key;
}

/** The Swedish word of the selected list row, or of the first row: for P in Lookup and My words. */
export function selectedWord() {
  const row = document.activeElement?.closest?.("main a.cell") ?? document.querySelector("main .list a.cell");
  return row?.querySelector(".headline")?.textContent ?? null;
}

/** Links and buttons in the page's lists and cards, in screen order. */
function listItems() {
  return [...document.querySelectorAll("main a.cell, main button.cell:not(:disabled), main a.card-link, main [data-id] > a")]
    .filter((el) => el.offsetParent !== null);
}

function moveFocus(step) {
  const items = listItems();
  if (!items.length) return;
  const i = items.indexOf(document.activeElement);
  if (i === 0 && step < 0) {
    const search = document.querySelector("main .search input");
    if (search) return search.focus();
  }
  const next = items[i < 0 ? (step > 0 ? 0 : items.length - 1) : Math.min(items.length - 1, Math.max(0, i + step))];
  next.focus();
  next.scrollIntoView({ block: "nearest" });
}

function onKeyDown(e) {
  if (e.altKey || e.defaultPrevented || e.isComposing) return;
  const name = keyName(e);
  const typing = isTyping(e.target);
  if (helpOpen) {
    if (e.key === "Escape" || e.key === "?") {
      e.preventDefault();
      toggleHelp();
    }
    return;
  }

  // The newest screen layer first; while typing, only ⌘/Ctrl combinations.
  for (let i = layers.length - 1; i >= 0; i--) {
    const entry = layers[i].entries.find(([keys]) => keys.includes(name));
    if (entry && (!typing || name.startsWith("Mod+"))) {
      e.preventDefault();
      entry[2](e);
      return;
    }
  }
  if (name.startsWith("Mod+")) return;

  if (typing) {
    if (e.key === "Escape") e.target.blur();
    else if (e.key === "ArrowDown" && e.target.closest(".search")) {
      e.preventDefault();
      moveFocus(1);
    }
    return;
  }

  const route = parseRoute();
  const actions = {
    t: () => go("today"),
    l: () => go("lookup"),
    w: () => go("words"),
    s: () => go("summary"),
    ",": () => go("settings"),
    "/": () => {
      const search = document.querySelector("main .search input");
      if (search) search.focus();
      else go("lookup");
    },
    j: () => moveFocus(1),
    ArrowDown: () => moveFocus(1),
    k: () => moveFocus(-1),
    ArrowUp: () => moveFocus(-1),
    "?": () => toggleHelp(),
    Escape: () => (!TAB_ROOTS.includes(route.name) ? back("today") : document.activeElement?.blur()),
  };
  const action = actions[e.key];
  if (action) {
    e.preventDefault();
    action();
  }
}

addEventListener("keydown", onKeyDown);
// A menu keeps focus after a pick, which would swallow letter keys like P until clicking elsewhere.
addEventListener("change", (e) => { if (e.target instanceof HTMLSelectElement) e.target.blur(); });

const show = (key) => ({ Space: "Space", ArrowLeft: "←", ArrowRight: "→", ArrowUp: "↑", ArrowDown: "↓", Escape: "Esc", Enter: "Enter" }[key]
  ?? (/^[A-ZÅÄÖ]$/.test(key) ? `⇧${key}`
    : key.replace(/^Mod\+/, navigator.platform.startsWith("Mac") ? "⌘" : "Ctrl+").replace(/(^|\+|⌘)([a-z])$/, (_, p, c) => p + c.toUpperCase())));

/** A key hint shown on buttons, on computers only. */
export const Kbd = ({ k }) => html`<kbd class="hint">${show(k)}</kbd>`;

/** The "?" overlay listing the global shortcuts and the current screen's. */
export function ShortcutHelp() {
  const [open, setOpen] = useState(false);
  helpOpen = open;
  toggleHelp = () => setOpen((o) => !o);
  if (!open) return null;
  const screen = layers.flatMap((l) => l.entries);
  const rows = (list) => list.map(([keys, label]) => html`<div class="cell">
    <span class="cell-main">${label}</span><span>${keys.map((k) => html`<kbd>${show(k)}</kbd>`)}</span></div>`);
  return html`<div class="sheet-backdrop" onClick=${() => setOpen(false)}>
    <div class="sheet" role="dialog" aria-label="Keyboard shortcuts" onClick=${(e) => e.stopPropagation()}>
      <div class="navbar"><div class="navbar-row"><div class="navbar-side"></div><div class="navbar-title">Keyboard shortcuts</div>
        <div class="navbar-side right"><button class="bar-button bold" onClick=${() => setOpen(false)}>Done</button></div></div></div>
      <div style="padding:0 16px">
        ${screen.length ? html`<section class="section"><div class="section-header">This screen</div><div class="list">${rows(screen)}</div></section>` : null}
        <section class="section"><div class="section-header">Everywhere</div><div class="list">${rows(GLOBAL)}</div></section>
      </div>
    </div>
  </div>`;
}
