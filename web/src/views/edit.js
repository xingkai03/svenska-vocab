import { html, useEffect, useState } from "../../vendor/preact-htm.js";
import { POS_ALL } from "../dictionary.js";
import { useKeys } from "../keys.js";
import { entryId, store } from "../store.js";
import { back, NavBar, Section, Segmented } from "../ui.js";

/** Add a custom word, or edit a word already in the collection. */
export function EditWordView({ id, prefill = "" }) {
  const existing = id ? store.words.get(id) : null;
  const [form, setForm] = useState(() => existing
    ? { word: existing.word, partOfSpeech: existing.partOfSpeech, gender: existing.gender, forms: existing.forms,
        translation: existing.translation, example: existing.example, exampleTranslation: existing.exampleTranslation }
    : { word: prefill.trim(), partOfSpeech: "noun", gender: "en", forms: "", translation: "", example: "", exampleTranslation: "" });
  const set = (patch) => setForm((f) => ({ ...f, ...patch }));
  const canSave = form.word.trim() && form.translation.trim();

  const save = () => {
    const t = Object.fromEntries(Object.entries(form).map(([k, v]) => [k, v.trim()]));
    t.gender = t.partOfSpeech === "noun" ? form.gender : "";
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
      <${Section} header="Example sentence">
        ${field("example", "Swedish sentence", true)}
        ${field("exampleTranslation", "English translation", true)}
      <//>
    </div>`;
}
