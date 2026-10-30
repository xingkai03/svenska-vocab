import { html, useEffect, useMemo, useRef, useState } from "../../vendor/preact-htm.js";
import { dictionary, headword } from "../dictionary.js";
import { useKeys } from "../keys.js";
import {
  articleDate, eightSidorList, eightSidorSearch, eightSidorSections, klartextList, loadArticle, paragraphsFromText, sentenceAt, SOURCES, tokenize, wikiList,
} from "../reading.js";
import { mastery } from "../scheduler.js";
import { speak } from "../speech.js";
import { local, store } from "../store.js";
import { EmptyState, HintCaption, Icon, LevelBadge, NavBar, PosTag, Section, SpeakButton, go, href } from "../ui.js";

const ORDER = ["8sidor", "klartext", "wiki", "paste"];

/** #/read, #/read/<source>, #/read/<source>/<id>?w=word (the word is highlighted in the article). */
export function ReadView({ args, query }) {
  const [source, id] = args;
  if (!source) return html`<${ReadHome} />`;
  if (!SOURCES[source]) return html`<${NavBar} title="Read" backTo="read" /><div class="page"><${EmptyState} icon="note" title="Unknown source" /></div>`;
  if (source === "paste") return id ? html`<${PastedArticle} />` : html`<${PasteEditor} />`;
  if (id) return html`<${ArticleView} key=${`${source}/${id}`} source=${source} id=${id} highlight=${query.w ?? ""} />`;
  return html`<${ArticleList} key=${source} source=${source} query=${query} />`;
}

function ReadHome() {
  return html`
    <${NavBar} title="Read" backTo="lookup" />
    <div class="page">
      <${Section} footer="Tap any word in an article to see what it means and add it to your words. Your New, Learning and Familiar words are coloured in the text.">
        ${ORDER.map((s) => html`<a class="cell" href=${href("read", s)}>
          <div class="cell-main"><div class="row" style="gap:6px"><span class="headline">${SOURCES[s].name}</span><span class="tag">${SOURCES[s].level}</span></div>
            <span class="subheadline secondary">${SOURCES[s].about}</span></div>
          <span class="chevron"><${Icon} name="chevronRight" /></span></a>`)}
      <//>
      <div class="section-footer">Articles are read straight from each site. 8 Sidor articles are kept in this browser
        for a while so they open instantly; they are never uploaded or shared.
        8 Sidor and Klartext belong to their publishers; please read them for your own learning.</div>
    </div>`;
}

// MARK: - Article lists

function ArticleList({ source, query }) {
  const [items, setItems] = useState(null);
  const [error, setError] = useState(null);
  const [page, setPage] = useState(1);
  const [more, setMore] = useState(true);
  const [sections, setSections] = useState([]);
  const [section, setSection] = useState(query.section ?? "");
  const [search, setSearch] = useState(query.q ?? "");
  const [shuffle, setShuffle] = useState(0);
  const info = SOURCES[source];

  useEffect(() => {
    if (source === "8sidor") eightSidorSections().then(setSections, () => {});
  }, []);

  useEffect(() => {
    history.replaceState(null, "", href("read", source, { ...(section ? { section } : {}), ...(search ? { q: search } : {}) }));
    let current = true;
    setError(null);
    if (page === 1) setItems(null);
    const delay = source === "wiki" && search ? 300 : 0;
    const timer = setTimeout(() => {
      // Newer articles from a background refresh replace the first page while it is the only one shown.
      const update = page === 1 ? (list) => current && setItems(list) : undefined;
      const load = source === "8sidor" ? eightSidorList({ section, page }, update)
        : source === "klartext" ? klartextList({ page })
        : wikiList(search);
      load.then((list) => {
        if (!current) return;
        setItems((old) => (page === 1 ? list : [...(old ?? []), ...list]));
        setMore(source !== "wiki" && list.length >= 20);
      }, (e) => current && setError(e.message));
    }, delay);
    return () => { current = false; clearTimeout(timer); };
  }, [section, page, search, shuffle]);

  const reset = (fn) => (value) => { fn(value); setPage(1); };

  return html`
    <${NavBar} title=${info.name} backTo="read">
      ${source === "wiki" ? html`<div class="page"><label class="search">
        <${Icon} name="search" />
        <input type="search" placeholder="Topic, e.g. Stockholm, fika, Astrid Lindgren" value=${search} autocomplete="off"
          onInput=${(e) => reset(setSearch)(e.currentTarget.value)} aria-label="Search Swedish Wikipedia" />
      </label></div>` : null}
    <//>
    <div class="page">
      ${source === "8sidor" && sections.length ? html`<${Section}>
        <div class="cell"><span>Section</span>
          <select class="menu" style="margin-left:auto" aria-label="Section" value=${section} onChange=${(e) => reset(setSection)(e.currentTarget.value)}>
            <option value="">All news</option>
            ${sections.map((s) => html`<option value=${s.id}>${s.name}</option>`)}
          </select></div>
      <//>` : null}

      ${error ? html`<${EmptyState} icon="cloudOff" title="Couldn't load articles">${error}
          <div><button class="btn" onClick=${() => { setPage(1); setShuffle((n) => n + 1); }}>Try again</button></div><//>`
      : !items ? html`<${Section}><div class="cell secondary">Loading…</div><//>`
      : !items.length ? html`<${Section}><div class="cell secondary">No articles found.</div><//>`
      : html`<${Section} header=${source === "wiki" && !search ? "Random articles" : null}
          footer=${source === "wiki" && !search ? html`<button class="btn plain" onClick=${() => setShuffle((n) => n + 1)}><${Icon} name="shuffle" /> Other articles</button>` : null}>
          ${items.map((item) => html`<a class="cell" href=${href("read", source, item.id)}>
            <div class="cell-main">
              ${item.date ? html`<span class="caption secondary">${articleDate(item.date)}</span>` : null}
              <span class="headline">${item.title}</span>
              ${item.summary ? html`<span class="subheadline secondary clamp2">${item.summary}</span>` : null}
            </div>
            ${item.audio ? html`<span class="secondary"><${Icon} name="ear" /></span>` : null}
            <span class="chevron"><${Icon} name="chevronRight" /></span></a>`)}
          ${more ? html`<button class="cell action" onClick=${() => setPage((p) => p + 1)}>Show older articles</button>` : null}
        <//>`}
      ${info.home ? html`<div class="section-footer">${info.credit} <a href=${info.home} target="_blank" rel="noopener">${new URL(info.home).hostname}</a></div>` : null}
    </div>`;
}

// MARK: - Your own text

function PasteEditor() {
  const [text, setText] = useState(() => local.get("pastedText", ""));
  const read = () => {
    local.set("pastedText", text);
    go("read", "paste", "text");
  };
  useKeys([[["Mod+Enter"], "Read the text", text.trim() && read]]);
  return html`
    <${NavBar} title="Your own text" backTo="read" right=${html`<button class="bar-button bold" disabled=${!text.trim()} onClick=${read}>Read</button>`} />
    <div class="page">
      <${Section} footer="Copy an article from any site, for example SVT Nyheter, and paste it here. Leave a blank line between paragraphs. The text stays in this browser.">
        <textarea class="text" rows="14" placeholder="Klistra in en svensk text här…" value=${text}
          onInput=${(e) => setText(e.currentTarget.value)} aria-label="Swedish text"></textarea>
      <//>
      <button class="btn prominent" style="width:100%" disabled=${!text.trim()} onClick=${read}>Read with word links</button>
    </div>`;
}

function PastedArticle() {
  const text = local.get("pastedText", "");
  const article = useMemo(() => {
    const paragraphs = paragraphsFromText(text);
    const title = paragraphs[0]?.kind === "h" ? paragraphs.shift().text : "";
    return { source: "paste", id: "text", title, paragraphs, credit: "" };
  }, [text]);
  if (!text.trim()) return html`<${PasteEditor} />`;
  return html`<${Reader} article=${article} highlight="" right=${html`<button class="bar-button" onClick=${() => go("read", "paste")}>Edit</button>`} />`;
}

// MARK: - Article

function ArticleView({ source, id, highlight }) {
  const [article, setArticle] = useState(null);
  const [error, setError] = useState(null);
  useEffect(() => {
    loadArticle(source, id).then(setArticle, (e) => setError(e.message));
  }, []);
  if (error || !article) {
    return html`<${NavBar} title=${SOURCES[source].name} backTo=${href("read", source)} />
      <div class="page">${error ? html`<${EmptyState} icon="cloudOff" title="Couldn't load the article">${error}<//>`
        : html`<${Section}><div class="cell secondary">Loading…</div><//>`}</div>`;
  }
  return html`<${Reader} article=${article} highlight=${highlight} />`;
}

/** Lower-cased word → its dictionary entries, shared by every article read in this visit. */
const lookups = new Map();
const entriesFor = (word) => {
  const w = word.toLowerCase();
  if (!lookups.has(w)) lookups.set(w, dictionary.matches(w));
  return lookups.get(w);
};

/** Mastery levels that are coloured in articles; Mastered words and words not in My words stay plain. */
const MARKED = ["New", "Learning", "Familiar"];

/** The mastery of a word in the text when it (or a saved phrase it belongs to) is in My words and not yet mastered. */
function markOf(token) {
  const lead = token.inPhrase ?? (token.phrase ? token : null);
  const saved = [...(lead?.phrase?.entries ?? []), ...entriesFor(token.text)].map((e) => store.words.get(e.id)).find(Boolean);
  const level = saved && mastery(saved);
  return MARKED.includes(level) ? level : null;
}

/** Whether a word in a text is `target` or one of its forms: "hunden" is hund, but "marken" is not ark. */
function sameWord(word, target) {
  const w = word.toLowerCase(), t = target.toLowerCase();
  if (w === t) return true;
  const ids = new Set(entriesFor(t).map((e) => e.id));
  return entriesFor(w).some((e) => ids.has(e.id) || e.word.toLowerCase() === t);
}

/** An article with every word linked: tap (or select several words) to look it up. */
function Reader({ article, highlight, right }) {
  const [picked, setPicked] = useState(null);
  const body = useRef(null);
  const paragraphs = useMemo(() => article.paragraphs.map((p) => ({ ...p, tokens: tokenize(p.text) })), [article]);
  // The word being looked up (from a word page, or the last word tapped) is highlighted wherever it appears.
  const [looked, setLooked] = useState(highlight);
  const isTarget = (w) => looked && sameWord(w, looked);
  let hits = 0;
  const counts = { New: 0, Learning: 0, Familiar: 0 };
  let wordCount = 0;
  for (const p of paragraphs) {
    for (const t of p.tokens) {
      if (!t.word) continue;
      wordCount += 1;
      if (isTarget(t.text)) hits += 1;
      const level = markOf(t);
      if (level) counts[level] += 1;
    }
  }

  useEffect(() => {
    body.current?.querySelector(".w.hit")?.scrollIntoView({ block: "center" });
  }, [paragraphs]);

  const offsetOf = (p, index) => p.tokens.slice(0, index).reduce((n, t) => n + t.text.length, 0);
  const open = (e) => {
    const selection = getSelection();
    const selected = selection?.toString().trim() ?? "";
    // Several selected words are looked up as a phrase.
    if (selected.includes(" ") && body.current?.contains(selection.anchorNode)) {
      const el = selection.anchorNode.parentElement?.closest("[data-p]");
      const p = paragraphs[Number(el?.dataset.p ?? -1)];
      setPicked({ text: selected.replace(/\s+/g, " "), selection: true, sentence: p ? sentenceAt(p.text, p.text.indexOf(selected)) : "" });
      return;
    }
    const span = e.target.closest?.(".w");
    if (!span) return;
    const p = paragraphs[Number(span.dataset.p)];
    const index = Number(span.dataset.t);
    const token = p.tokens[index];
    const lead = token.inPhrase ?? (token.phrase ? token : null);
    setPicked({ text: token.text, phrase: lead?.phrase ?? null, sentence: sentenceAt(p.text, offsetOf(p, index)) });
    setLooked(token.text);
  };

  useKeys([[["o"], "Open the original article", article.link && (() => window.open(article.link, "_blank", "noopener"))]]);

  const word = (t, pi, ti) => {
    const entries = entriesFor(t.text);
    const level = markOf(t);
    const cls = ["w", level ? `m-${level.toLowerCase()}` : "", entries.length ? "" : "unknown", isTarget(t.text) ? "hit" : ""].filter(Boolean).join(" ");
    return html`<span class=${cls} data-p=${pi} data-t=${ti}>${t.text}</span>`;
  };

  const info = SOURCES[article.source];
  return html`
    <${NavBar} title=${info.name} backTo=${href("read", article.source)} right=${right} />
    <div class="page reader">
      ${article.title ? html`<h1 class="reader-title">${article.title}</h1>` : null}
      <div class="caption secondary reader-meta">
        ${article.date ? html`<span>${articleDate(article.date)}</span>` : null}
        <span>${wordCount} words</span>
        ${MARKED.map((m) => html`<span><span class=${`mark-key m-${m.toLowerCase()}`}>${m}</span> ${counts[m]}</span>`)}
        ${looked ? html`<span><span class="mark-key hit">${looked}</span> ${hits}×
          <button class="btn plain caption" onClick=${() => setLooked("")} aria-label="Stop highlighting">✕</button></span>` : null}
        ${article.link ? html`<a href=${article.link} target="_blank" rel="noopener">Open on ${new URL(article.link).hostname.replace(/^www\./, "")}</a>` : null}
      </div>
      ${article.audio ? html`<audio class="reader-audio" controls preload="none" src=${article.audio}></audio>` : null}
      <div class="reader-body" ref=${body} onClick=${open}>
        ${paragraphs.map((p, pi) => {
          const content = p.tokens.map((t, ti) => (t.word ? word(t, pi, ti) : t.text));
          return p.kind === "h" ? html`<h2 data-p=${pi}>${content}</h2>` : html`<p data-p=${pi}>${content}</p>`;
        })}
      </div>
      ${article.source === "klartext" ? html`<div class="section-footer">Klartext's summary of the day's news; the full broadcast is in the player above.</div>` : null}
      <div class="section-footer">${article.credit}${article.link ? html` <a href=${article.link} target="_blank" rel="noopener">Original article</a>` : null}
        <br />Coloured words are in your words: New (not reviewed yet), Learning (next review within a week) and Familiar (1–3 weeks). Mastered and unsaved words stay plain; tap any word to look it up.</div>
    </div>
    ${picked ? html`<${WordSheet} ...${picked} onClose=${() => setPicked(null)} />` : null}`;
}

// MARK: - Word sheet

/** What a tapped word (or selected phrase) means, with buttons to hear it and add it to your words. */
function WordSheet({ text, phrase, selection, sentence, onClose }) {
  const results = selection ? dictionary.search(text, 6).swedish : entriesFor(text);
  const phraseEntries = phrase?.entries ?? [];
  const entries = [...phraseEntries, ...results.filter((e) => !phraseEntries.includes(e))].slice(0, 6);
  const first = entries.find((e) => !store.words.has(e.id));

  useKeys([
    [["Escape"], "Close", onClose],
    [["p"], "Pronounce", () => speak(text)],
    [["P"], "Pronounce slowly", () => speak(text, { slow: true })],
    [["x"], "Pronounce the sentence", sentence && (() => speak(sentence))],
    [["a"], "Add the first meaning to my words", first && (() => store.addToCollection(first))],
  ]);

  return html`<div class="sheet-backdrop" onClick=${onClose}>
    <div class="sheet word-sheet" role="dialog" aria-label=${`“${text}”`} onClick=${(e) => e.stopPropagation()}>
      <div class="navbar"><div class="navbar-row"><div class="navbar-side"></div><div class="navbar-title">${text}</div>
        <div class="navbar-side right"><button class="bar-button bold" onClick=${onClose}>Done</button></div></div></div>
      <div style="padding:0 16px">
        <div class="row" style="gap:12px;justify-content:center">
          <${SpeakButton} text=${text} size="big" hotkey="p" /><${SpeakButton} text=${text} slow size="big" hotkey="P" />
        </div>
        ${entries.length ? html`<${Section} header=${phraseEntries.length ? "Phrase and word" : "In the dictionary"}>
          ${entries.map((e) => html`<${EntryActions} key=${e.id} entry=${e} />`)}
        <//>` : html`<${Section}><div class="cell secondary">“${text}” isn't in the dictionary. It may be a name or a rare form.</div><//>`}
        <${Section}>
          <a class="cell action" href=${href("lookup", { q: text.toLowerCase() })}><${Icon} name="search" /> Look up “${text}”</a>
          ${!entries.length ? html`<a class="cell action" href=${href("new", { prefill: text.toLowerCase() })}><${Icon} name="plusCircle" /> Add as your own word</a>` : null}
        <//>
        ${sentence ? html`<${Section} header="Sentence">
          <div class="cell"><span class="cell-main italic">${sentence}</span><${SpeakButton} text=${sentence} hotkey="x" /></div>
        <//>` : null}
      </div>
    </div>
  </div>`;
}

function EntryActions({ entry }) {
  const saved = store.words.has(entry.id);
  return html`<div class="cell">
    <a class="cell-main" href=${href("word", entry.id)} style="color:inherit">
      <div class="row" style="gap:6px"><span class="headline">${headword(entry)}</span><${PosTag} entry=${entry} /><${LevelBadge} level=${entry.level} /></div>
      <div class="subheadline secondary">${entry.translation}</div>
      <${HintCaption} word=${entry.word} partOfSpeech=${entry.partOfSpeech} />
    </a>
    <${SpeakButton} text=${entry.word} />
    ${saved
      ? html`<span class="accent" title="In your words" aria-label="In your words"><${Icon} name="bookmarkFill" /></span>`
      : html`<button class="btn small" onClick=${() => store.addToCollection(entry)} aria-label=${`Add ${entry.word} to my words`}>
          <${Icon} name="plus" /> Add</button>`}
  </div>`;
}

// MARK: - On word pages

/** Recent 8 Sidor articles that use the word, linking to the reader with the word highlighted. Draws nothing until found. */
export function ReadingArticles({ word }) {
  const [found, setFound] = useState(null);
  useEffect(() => {
    let current = true;
    if (/^\p{L}+$/u.test(word) && word.length > 2) {
      // 8 Sidor's search also finds the letters inside other words, so keep articles that really use the word.
      const show = (articles) => current && setFound(articles.filter((a) => a.paragraphs.some((p) =>
        tokenize(p.text).some((t) => t.word && sameWord(t.text, word)))).slice(0, 4));
      eightSidorSearch(word, 20, show).then(show, () => {});
    }
    return () => { current = false; };
  }, [word]);
  if (!found?.length) return null;
  return html`<${Section} header="Read on 8 Sidor" footer="Easy-Swedish news that uses the word. Tap words in the article to look them up.">
    ${found.map((item) => html`<a class="cell" href=${href("read", "8sidor", item.id, { w: word })}>
      <div class="cell-main"><span class="caption secondary">${articleDate(item.date)}</span><span class="headline">${item.title}</span></div>
      <span class="chevron"><${Icon} name="chevronRight" /></span></a>`)}
  <//>`;
}
