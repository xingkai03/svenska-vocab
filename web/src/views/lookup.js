import { html, useEffect, useRef, useState } from "../../vendor/preact-htm.js";
import { dictionary } from "../dictionary.js";
import { local, store } from "../store.js";
import { EntryRow, Icon, NavBar, Section, go, href } from "../ui.js";

function remember(term) {
  const t = term.trim();
  if (!t) return;
  const recent = local.get("recentSearches", []);
  local.set("recentSearches", [t, ...recent.filter((r) => r.toLowerCase() !== t.toLowerCase())].slice(0, 10));
}

export function LookupView({ query: initial = "" }) {
  const [query, setQuery] = useState(initial);
  const [showAllFirst, setShowAllFirst] = useState(false);
  const [, setRecentVersion] = useState(0);
  const input = useRef(null);

  useEffect(() => {
    if (!initial) input.current?.focus();
  }, []);

  const update = (q) => {
    setQuery(q);
    setShowAllFirst(false);
    // Keep the query in the address, so going back from a word returns to the same results.
    history.replaceState(null, "", href("lookup", q ? { q } : {}));
  };

  const results = query.trim() ? dictionary.search(query) : null;
  const recent = local.get("recentSearches", []);

  return html`
    <${NavBar} title="Lookup" large right=${html`
      <button class="bar-button" onClick=${() => go("new", query ? { prefill: query } : {})} aria-label="Add your own word" title="Add your own word"><${Icon} name="plus" /></button>`}>
      <div class="page"><label class="search">
        <${Icon} name="search" />
        <input ref=${input} type="search" placeholder="Swedish or English" value=${query} autocomplete="off" autocapitalize="off"
          spellcheck=${false} onInput=${(e) => update(e.currentTarget.value)}
          onKeyDown=${(e) => e.key === "Enter" && remember(query)} aria-label="Search the dictionary" />
      </label></div>
    <//>
    <div class="page">
      ${!results ? html`
        ${recent.length ? html`<${Section} header="Recent" headerRight=${html`<button class="btn plain caption" onClick=${() => { local.set("recentSearches", []); setRecentVersion((v) => v + 1); }}>Clear</button>`}>
          ${recent.map((term) => html`<button class="cell" onClick=${() => update(term)}>
            <span class="accent"><${Icon} name="clock" /></span><span class="cell-main">${term}</span></button>`)}
        <//>` : null}
        <${Section}>
          <div class="cell"><div class="cell-main">
            <div class="headline"><${Icon} name="dictionary" /> Search in Swedish or English</div>
            <div class="subheadline secondary">Type without å, ä, ö if you like: “bat” finds “båt”. ${dictionary.entries.length.toLocaleString()} words, from the same dictionary as the app.</div>
          </div></div>
        <//>`
      : html`
        <${Results} results=${results} query=${query} showAllFirst=${showAllFirst} onShowAll=${() => setShowAllFirst(true)} />
        ${results.swedish.length + results.english.length === 0 ? html`<${Section}><div class="cell secondary">No matches in the dictionary.</div><//>` : null}
        <${Section}>
          <button class="cell action" onClick=${() => go("new", { prefill: query.trim() })}>
            <${Icon} name="plusCircle" /> Add “${query.trim()}” as your own word</button>
        <//>`}
    </div>`;
}

/** Swedish-word matches and translation matches in separate sections. When both exist, the first section
 *  is cut to a few rows so the other stays visible (e.g. "dog" shows Swedish "dog" = died, and "hund"). */
function Results({ results, query, showAllFirst, onShowAll }) {
  const swedish = ["Swedish", results.swedish];
  const english = ["English → Swedish", results.english];
  const [first, second] = results.englishFirst ? [english, swedish] : [swedish, english];
  const collapsed = !showAllFirst && second[1].length > 0 && first[1].length > 6;
  const row = (entry) => html`<${EntryRow} key=${entry.id} entry=${entry} saved=${store.words.has(entry.id)} onOpen=${() => remember(entry.word)} />`;
  return html`
    ${first[1].length ? html`<${Section} header=${first[0]}>
      ${(collapsed ? first[1].slice(0, 5) : first[1]).map(row)}
      ${collapsed ? html`<button class="cell action" onClick=${onShowAll}>Show ${first[1].length - 5} more</button>` : null}
    <//>` : null}
    ${second[1].length ? html`<${Section} header=${second[0]}>${second[1].map(row)}<//>` : null}`;
}
