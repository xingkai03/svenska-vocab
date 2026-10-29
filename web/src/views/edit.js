import { html, useEffect, useState } from "../../vendor/preact-htm.js";
import { cloud } from "../cloud.js";
import { POS_ALL } from "../dictionary.js";
import { joinExamples, splitExamples } from "../examples.js";
import { useKeys } from "../keys.js";
import { entryId, store } from "../store.js";
import { back, href, Icon, NavBar, Section, Segmented } from "../ui.js";

const sameText = (a, b) => (a ?? "").replace(/\s+/g, " ").trim() === (b ?? "").replace(/\s+/g, " ").trim();
const sameExamples = (a, b) => a.length === b.length && a.every((p, i) => sameText(p.sv, b[i].sv) && sameText(p.en, b[i].en));

/** What an AI suggestion would change, as the names of the fields that differ from the form. */
function changedFields(form, examples, s) {
  const changed = [];
  if (!sameText(s.translation, form.translation)) changed.push("translation");
  if (s.partOfSpeech !== form.partOfSpeech || (s.partOfSpeech === "noun" && s.gender !== form.gender)) changed.push("grammar");
  if (!sameText(s.forms, form.forms)) changed.push("forms");
  if (!sameExamples(s.examples, examples.filter((p) => p.sv.trim()))) changed.push("examples");
  return changed;
}

/** Add a custom word, or edit a word already in the collection. */
export function EditWordView({ id, prefill = "" }) {
  const existing = id ? store.words.get(id) : null;
  const [form, setForm] = useState(() => existing
    ? { word: existing.word, partOfSpeech: existing.partOfSpeech, gender: existing.gender, forms: existing.forms,
        translation: existing.translation }
    : { word: prefill.trim(), partOfSpeech: "noun", gender: "en", forms: "", translation: "" });
  const [examples, setExamples] = useState(() => {
    const pairs = existing ? splitExamples(existing.example, existing.exampleTranslation) : [];
    return pairs.length ? pairs : [{ sv: "", en: "" }];
  });
  const set = (patch) => setForm((f) => ({ ...f, ...patch }));
  const setExample = (i, patch) => setExamples((list) => list.map((p, j) => (j === i ? { ...p, ...patch } : p)));
  const canSave = form.word.trim() && form.translation.trim();

  // AI check & polish: { loading } while waiting, { error }, or { suggestion, changed, picked } to review.
  const [polish, setPolish] = useState(null);
  const canPolish = cloud.isConfigured && cloud.session && form.word.trim() && !polish?.loading;

  const askAI = async () => {
    setPolish({ loading: true });
    try {
      const suggestion = await cloud.invoke("polish-word", {
        ...form, gender: form.partOfSpeech === "noun" ? form.gender : "", examples: examples.filter((p) => p.sv.trim()),
      });
      const changed = changedFields(form, examples, suggestion);
      setPolish({ suggestion, changed, picked: new Set(changed) });
    } catch (error) {
      setPolish({ error: error.message || "Something went wrong." });
    }
  };

  const applyPolish = () => {
    const { suggestion: s, picked } = polish;
    if (picked.has("translation")) set({ translation: s.translation });
    if (picked.has("grammar")) set({ partOfSpeech: s.partOfSpeech, gender: s.partOfSpeech === "noun" ? s.gender : form.gender });
    if (picked.has("forms")) set({ forms: s.forms });
    if (picked.has("examples")) setExamples(s.examples.length ? s.examples : [{ sv: "", en: "" }]);
    setPolish(null);
  };

  const togglePick = (name) => setPolish((p) => {
    const picked = new Set(p.picked);
    if (picked.has(name)) picked.delete(name);
    else picked.add(name);
    return { ...p, picked };
  });

  const save = () => {
    const t = Object.fromEntries(Object.entries(form).map(([k, v]) => [k, v.trim()]));
    t.gender = t.partOfSpeech === "noun" ? form.gender : "";
    Object.assign(t, joinExamples(examples));
    if (existing) {
      // The key stays the same so review history is kept.
      store.updateWord(existing.key, t);
      back("words");
    } else {
      const word = store.addToCollection({ ...t, source: "custom" });
      location.replace(`#/word/${encodeURIComponent(word.key ?? entryId(t))}`);
    }
  };

  useEffect(() => document.querySelector("main input.text")?.focus(), []);
  useKeys([[["Mod+Enter", "Mod+s"], "Save", canSave && save]]);

  const field = (name, placeholder, multiline = false) => multiline
    ? html`<textarea class="text" rows="2" placeholder=${placeholder} value=${form[name]} onInput=${(e) => set({ [name]: e.currentTarget.value })}></textarea>`
    : html`<input class="text" placeholder=${placeholder} value=${form[name]} autocapitalize="off" onInput=${(e) => set({ [name]: e.currentTarget.value })} />`;

  return html`
    <${NavBar} title=${existing ? "Edit word" : "New word"}
      left=${html`<button class="bar-button" onClick=${() => back(existing ? "words" : "lookup")}>Cancel</button>`}
      right=${html`<button class="bar-button bold" disabled=${!canSave} onClick=${save} title="Save (⌘/Ctrl+Enter)">Save</button>`} />
    <div class="page">
      ${cloud.isConfigured ? html`<${Section} footer=${cloud.session
          ? "Gemini checks the translation, adds missing meanings and writes more example sentences. You choose what to keep before saving."
          : html`<a href=${href("account")}>Sign in</a> to let Gemini check this word and add example sentences.`}>
        <button class="cell action" disabled=${!canPolish} onClick=${askAI}>
          <${Icon} name="sparkles" /><span class="cell-main">${polish?.loading ? "Checking…" : "AI check & polish"}</span>
        </button>
      <//>` : null}
      ${polish?.error ? html`<div class="notice red" style="margin-top:12px">${polish.error}</div>` : null}
      ${polish?.suggestion ? html`<${PolishSuggestion} polish=${polish} form=${form} onToggle=${togglePick}
        onApply=${applyPolish} onDiscard=${() => setPolish(null)} />` : null}
      <${Section} header="Swedish">
        ${field("word", "Word")}
        <label class="cell"><span class="cell-main">Part of speech</span>
          <select class="menu" value=${form.partOfSpeech} onChange=${(e) => set({ partOfSpeech: e.currentTarget.value })}>
            ${POS_ALL.map((p) => html`<option value=${p}>${p[0].toUpperCase() + p.slice(1)}</option>`)}
          </select></label>
        ${form.partOfSpeech === "noun" ? html`<div class="cell"><span class="cell-main">Gender</span>
          <div style="width:180px"><${Segmented} label="Gender" options=${[["en", "en"], ["ett", "ett"], ["", "none"]]} value=${form.gender} onChange=${(gender) => set({ gender })} /></div>
        </div>` : null}
        ${field("forms", "Forms, comma separated (e.g. bilen, bilar, bilarna)", true)}
      <//>
      <${Section} header="English">${field("translation", "Translation", true)}<//>
      ${examples.map((p, i) => html`<${Section} header=${examples.length > 1 ? `Example sentence ${i + 1}` : "Example sentence"}
          headerRight=${examples.length > 1 ? html`<button class="btn plain small red" onClick=${() => setExamples((l) => l.filter((_, j) => j !== i))}>Remove</button>` : null}>
        <textarea class="text" rows="2" placeholder="Swedish sentence" value=${p.sv} onInput=${(e) => setExample(i, { sv: e.currentTarget.value })}></textarea>
        <textarea class="text" rows="2" placeholder="English translation" value=${p.en} onInput=${(e) => setExample(i, { en: e.currentTarget.value })}></textarea>
      <//>`)}
      <div style="margin-top:8px">
        <button class="btn plain" onClick=${() => setExamples((l) => [...l, { sv: "", en: "" }])}><${Icon} name="plusCircle" /> Add example sentence</button>
      </div>
    </div>`;
}

/** The AI's suggestion, field by field, with a checkbox for each change. Nothing is saved until the learner does. */
function PolishSuggestion({ polish, form, onToggle, onApply, onDiscard }) {
  const { suggestion: s, changed, picked } = polish;
  const row = (name, label, body) => changed.includes(name) ? html`<label class="cell" style="align-items:flex-start">
    <input type="checkbox" checked=${picked.has(name)} onChange=${() => onToggle(name)} style="margin-top:4px" />
    <div class="cell-main"><span class="footnote secondary">${label}</span>${body}</div></label>` : null;
  const grammar = (pos, gender) => pos === "noun" && gender ? `${pos}, ${gender}-word` : pos;

  return html`<${Section} header="AI suggestion">
    ${s.notes ? html`<div class="cell"><${Icon} name="sparkles" class="purple" /><span class="cell-main subheadline">${s.notes}</span></div>` : null}
    ${changed.length ? null : html`<div class="cell secondary">Nothing to change. This word looks good.</div>`}
    ${row("translation", "Translation", html`<span>${s.translation}</span>
      ${form.translation ? html`<span class="caption tertiary" style="text-decoration:line-through">${form.translation}</span>` : null}`)}
    ${row("grammar", "Part of speech", html`<span>${grammar(s.partOfSpeech, s.gender)}</span>
      <span class="caption tertiary" style="text-decoration:line-through">${grammar(form.partOfSpeech, form.gender)}</span>`)}
    ${row("forms", "Forms", html`<span>${s.forms || "(none)"}</span>
      ${form.forms ? html`<span class="caption tertiary" style="text-decoration:line-through">${form.forms}</span>` : null}`)}
    ${row("examples", `Example sentences (${s.examples.length})`, s.examples.map((p) => html`<div style="margin-top:4px">
      <div class="italic">${p.sv}</div><div class="caption secondary">${p.en}</div></div>`))}
    <div class="cell">
      ${changed.length ? html`<button class="btn prominent small" disabled=${!picked.size} onClick=${onApply}>Use selected</button>` : null}
      <button class="btn small" onClick=${onDiscard}>${changed.length ? "Discard" : "Close"}</button>
    </div>
  <//>`;
}
