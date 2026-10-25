import { html, useEffect, useRef, useState } from "../../vendor/preact-htm.js";
import { useKeys } from "../keys.js";
import { clipLink, clipTime, PLAY, svt, svtTerms } from "../svt.js";
import { EmptyState, Icon, NavBar, Section, Toggle, href } from "../ui.js";

const MAX_TIMES = 12;

/** Search a Swedish word and jump to the moments it's said on SVT Play (the former SVT Learn page). */
export function SvtView({ query: initial }) {
  const [q, setQ] = useState(initial.q ?? "");
  const [programme, setProgramme] = useState(initial.p ?? "");
  const [prefix, setPrefix] = useState(initial.prefix === "1");
  const [meta, setMeta] = useState(null);
  const [error, setError] = useState(null);
  const [found, setFound] = useState(null);
  const input = useRef(null);

  useEffect(() => {
    svt.load().then(setMeta, (e) => setError(e.message));
    if (!initial.q) input.current?.focus();
  }, []);

  const terms = svtTerms(q);
  useEffect(() => {
    // Keep the search in the address, so it can be shared and going back returns to it.
    history.replaceState(null, "", href("svt", { ...(q ? { q } : {}), ...(programme ? { p: programme } : {}), ...(prefix ? { prefix: "1" } : {}) }));
    if (!terms.length) return setFound(null);
    let current = true;
    const timer = setTimeout(() => svt.search(terms, { prefix, programme }).then((r) => current && setFound({ ...r, terms })), 200);
    return () => { current = false; clearTimeout(timer); };
  }, [terms.join(" "), programme, prefix]);

  useKeys([[["b"], "Toggle “word starts with”", () => setPrefix((p) => !p)]]);

  const programmes = meta ? [...new Set(meta.episodes.map((e) => e.p))].sort((a, b) => a.localeCompare(b, "sv")) : [];
  const said = found?.terms.join(" ");

  return html`
    <${NavBar} title="SVT Play" backTo="lookup">
      <div class="page"><label class="search">
        <${Icon} name="search" />
        <input ref=${input} type="search" placeholder="t.ex. regeringen, väder, kultur" value=${q} autocomplete="off"
          autocapitalize="off" spellcheck=${false} onInput=${(e) => setQ(e.currentTarget.value)} aria-label="Swedish word or words" />
      </label></div>
    <//>
    <div class="page">
      ${error ? html`<${EmptyState} icon="tv" title="Couldn't load the index">${error}<//>` : html`
        <${Section}>
          <div class="cell"><span>Programme</span>
            <select class="menu svt-programme" aria-label="Programme" value=${programme} onChange=${(e) => setProgramme(e.currentTarget.value)}>
              <option value="">All programmes</option>
              ${programmes.map((p) => html`<option value=${p}>${p}</option>`)}
            </select></div>
          <${Toggle} label="Word starts with" checked=${prefix} onChange=${setPrefix} />
        <//>

        ${!terms.length ? html`<${Section} footer=${meta ? `${meta.episodes.length} episodes indexed, updated ${meta.built}.` : "Loading…"}>
            <div class="cell"><div class="cell-main">
              <div class="headline"><${Icon} name="tv" /> Hear a word on SVT Play</div>
              <div class="subheadline secondary">Type a Swedish word and jump to the moment it's said. Several words find places where they're said within 20 seconds of each other.</div>
            </div></div>
          <//>`
        : found ? html`
          ${prefix && found.terms.length === 1 && found.matched.length > 1 ? html`<div class="svt-words">
            ${found.matched.slice(0, 30).map((w) => html`<button class="btn small" onClick=${() => { setQ(w); setPrefix(false); }}>${w}</button>`)}
          </div>` : null}
          ${found.results.length
            ? html`<${Section} header=${`${found.results.length} episode${found.results.length > 1 ? "s" : ""} with “${said}”`}>
                ${found.results.map((r) => html`<${EpisodeCell} ...${r} />`)}
              <//>`
            : html`<${Section}><div class="cell secondary">No clips found for “${said}”.${prefix ? "" : " Try “Word starts with”."}</div><//>`}`
        : null}

        <div class="section-footer svt-note">Links go to <a href=${PLAY} target="_blank" rel="noopener">SVT Play</a>; some programmes can only be
          watched in Sweden. Episodes leave SVT Play after a while, so each one shows when it expires. Only word positions
          are stored here, not SVT's subtitles.</div>`}
    </div>`;
}

/** One episode with a play link for each moment the word is said. */
export function EpisodeCell({ episode, times, max = MAX_TIMES }) {
  const until = episode.to && episode.to < "2050" ? `on SVT Play until ${episode.to}` : "";
  return html`<div class="cell"><div class="cell-main">
    <span class="caption secondary">${episode.p}</span>
    <span class="headline">${episode.n}${until ? html` <span class="caption secondary">· ${until}</span>` : null}</span>
    <div class="svt-times">${times.slice(0, max).map((t) => html`
      <a class="tag" href=${clipLink(episode, t)} target="_blank" rel="noopener" aria-label=${`Play from ${clipTime(t)}`}>▶ ${clipTime(t)}</a>`)}
      ${times.length > max ? html`<span class="caption secondary">+${times.length - max}</span>` : null}
    </div>
  </div></div>`;
}
