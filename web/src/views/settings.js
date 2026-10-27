import { html, useRef, useState } from "../../vendor/preact-htm.js";
import { cloud } from "../cloud.js";
import { convertList, dictionary, MY_LISTS } from "../dictionary.js";
import { enabledMethods } from "../methods.js";
import { hasSpeech, hasSwedishVoice, speak } from "../speech.js";
import { useKeys } from "../keys.js";
import { store } from "../store.js";
import { Icon, NavBar, Section, Stepper, Toggle, go, href, relative } from "../ui.js";
import { REVIEW_MODES } from "./review.js";

export function SyncStatus() {
  if (cloud.isSyncing) return html`<span>Syncing…</span>`;
  if (cloud.lastError) return html`<span class="red">${cloud.lastError}</span>`;
  if (cloud.lastSyncedAt) return html`<span>Synced ${relative(cloud.lastSyncedAt)}</span>`;
  return html`<span>Not synced yet</span>`;
}

function AccountSection() {
  if (!cloud.isConfigured) {
    return html`<${Section} header="Account"><div class="cell secondary"><${Icon} name="cloudOff" /> Cloud sync is not set up in this build</div><//>`;
  }
  if (cloud.session) {
    return html`<${Section} header="Account">
      <a class="cell" href=${href("account")}>
        <span class="accent title3"><${Icon} name="person" /></span>
        <div class="cell-main"><span>${cloud.session.email}</span><span class="caption secondary"><${SyncStatus} /></span></div>
        <span class="chevron"><${Icon} name="chevronRight" /></span>
      </a><//>`;
  }
  return html`<${Section} header="Account" footer="Sign in with the same account as the iPhone app to share your words, review progress, check-ins, settings and imported lists. Everything keeps working offline.">
    <a class="cell action" href=${href("signin")}><${Icon} name="personPlus" /> Sign in or create account
      <span class="chevron"><${Icon} name="chevronRight" /></span></a><//>`;
}

function csvExport() {
  const field = (s) => `"${String(s).replaceAll('"', '""')}"`;
  const header = "word,part_of_speech,gender,forms,translation,example,example_translation,note,interval_days,due";
  const words = [...store.words.values()].sort((a, b) => a.word.localeCompare(b.word, "sv"));
  const rows = words.map((w) => [w.word, w.partOfSpeech, w.gender, w.forms, w.translation, w.example, w.exampleTranslation,
    w.note, String(w.interval), new Date(w.dueDate).toISOString()].map(field).join(","));
  const blob = new Blob([[header, ...rows].join("\n")], { type: "text/csv" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "svenska-words.csv";
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

export function SettingsView() {
  const fileInput = useRef(null);
  const [importMessage, setImportMessage] = useState(null);
  const rate = store.get("speechRate");
  const enabled = enabledMethods(store.get("disabledReviewModes"));
  // The last method that is on can't be turned off.
  const setMode = (id, on) => {
    const off = new Set(store.get("disabledReviewModes").split(",").filter(Boolean));
    if (on) off.delete(id);
    else off.add(id);
    if (off.size < REVIEW_MODES.length) store.set("disabledReviewModes", REVIEW_MODES.map((m) => m.id).filter((id) => off.has(id)).join(","));
  };
  // Personal lists: imported ones (the open lists that ship with the app are in Learn new words).
  const myLists = dictionary.customDecks.filter((d) => d.group === MY_LISTS);

  useKeys([
    [["a"], cloud.session ? "Account" : "Sign in", cloud.isConfigured && (() => go(cloud.session ? "account" : "signin"))],
    [["i"], "Import a word list", () => fileInput.current.click()],
    [["p"], "Test pronunciation", () => speak("Hej, hur mår du?")],
  ]);

  const importList = async (file) => {
    if (!file) return;
    try {
      const buffer = await file.arrayBuffer();
      let text;
      try {
        text = new TextDecoder("utf-8", { fatal: true }).decode(buffer);
      } catch {
        // Spreadsheet exports are often Latin-1 rather than UTF-8.
        text = new TextDecoder("iso-8859-1").decode(buffer);
      }
      const list = convertList(file.name, text);
      store.setList(list.fileName, list.content);
      setImportMessage(`Imported ${list.count} words from “${list.name}”. Find the list in Learn new words.`);
    } catch (error) {
      setImportMessage(error.message);
    }
    fileInput.current.value = "";
  };

  return html`
    <${NavBar} title="Settings" backTo="today" backLabel="Today" />
    <div class="page" style="padding-bottom:24px">
      <${AccountSection} />

      <${Section} header="Daily goal">
        <${Stepper} label=${`${store.get("dailyGoal")} reviews or new words`} value=${store.get("dailyGoal")} min=${5} max=${200} step=${5}
          onChange=${(v) => store.set("dailyGoal", v)} />
        <${Stepper} label=${`${store.get("sessionSize")} cards per session`} value=${store.get("sessionSize")} min=${10} max=${200} step=${10}
          onChange=${(v) => store.set("sessionSize", v)} />
      <//>

      <${Section} header="Review methods" footer="Mixed review picks one of these for each card, and more often the ones you find hardest for that word, such as spelling a word you only recognise.">
        ${REVIEW_MODES.map((m) => html`<${Toggle} label=${html`<span class="row" style="gap:8px"><${Icon} name=${m.icon} />${m.title}</span>`} checked=${enabled.includes(m.id)}
          disabled=${enabled.length === 1 && enabled[0] === m.id} onChange=${(on) => setMode(m.id, on)} />`)}
      <//>

      <${Section} header="Pronunciation" footer=${!hasSpeech ? "This browser can't speak text aloud."
          : hasSwedishVoice() ? "Uses your browser's Swedish voice. Chrome and Edge have natural-sounding online voices; on a Mac you can add more in System Settings › Accessibility › Spoken Content."
          : "No Swedish voice found in this browser. Add one in your system's speech settings, or try Chrome or Edge."}>
        <${Toggle} label="Pronounce words automatically" checked=${store.get("autoSpeak")} onChange=${(v) => store.set("autoSpeak", v)} />
        <div class="cell"><div class="cell-main">
          <span>Speaking speed</span>
          <div class="row"><span class="secondary"><${Icon} name="slow" /></span>
            <input type="range" min="0.25" max="0.6" step="0.01" value=${rate} aria-label="Speaking speed"
              onInput=${(e) => store.set("speechRate", Number(e.currentTarget.value))} />
            <span class="secondary"><${Icon} name="speaker" /></span></div>
        </div></div>
        <button class="cell action" onClick=${() => speak("Hej, hur mår du?")}>Test: “Hej, hur mår du?”</button>
      <//>

      <${Section} header="Languages I know" footer="Many Swedish words look like their German or French translation (fönster – Fenster, biljett – billet). Turn on the languages you know to see these memory hints in Lookup, on word pages and on learn and review cards. Hints come from Wiktionary (via WikDict and kaikki.org), CC BY-SA 4.0.">
        <${Toggle} label="🇩🇪 German" checked=${store.get("knowsGerman")} onChange=${(v) => store.set("knowsGerman", v)} />
        <${Toggle} label="🇫🇷 French" checked=${store.get("knowsFrench")} onChange=${(v) => store.set("knowsFrench", v)} />
      <//>

      <${Section} header="Data">
        <button class="cell action" disabled=${!store.words.size} onClick=${csvExport}><${Icon} name="upload" /> Export collection as CSV</button>
      <//>

      <${Section} header="Word lists" footer="Import a .tsv, .csv or .txt file with one word per line: Swedish, English, and optionally part of speech, example and chapter (a header row is optional). Lists appear in Learn new words, here and in the app.">
        ${myLists.map((d) => html`<div class="cell">
          <span class="cell-main">${d.name}</span><span class="secondary">${d.entries.length} words</span>
          <button class="icon-button" style="color:var(--red)" aria-label=${`Delete ${d.name}`} title="Delete list"
            onClick=${() => confirm(`Delete the word list “${d.name}”?`) && store.deleteList(d.fileName)}><${Icon} name="trash" /></button>
        </div>`)}
        <button class="cell action" onClick=${() => fileInput.current.click()}><${Icon} name="download" /> Import word list…</button>
        <input ref=${fileInput} type="file" accept=".tsv,.csv,.txt,text/plain,text/csv,text/tab-separated-values" hidden
          onChange=${(e) => importList(e.currentTarget.files[0])} />
      <//>
      ${importMessage ? html`<div class="notice" style="margin-top:12px">${importMessage}</div>` : null}

      <div class="section-footer" style="margin-top:24px">Dictionary data © Folkets lexikon, CC BY-SA 2.5. Extra example sentences from Wiktionary (kaikki.org), CC BY-SA 4.0, and Tatoeba, CC BY 2.0 FR. CEFR levels from the Swedish Kelly list, Språkbanken, University of Gothenburg, CC BY 4.0. Coursebook lists from SVALex (François, Volodina, Pilán & Tack 2016), CC BY-NC-SA 4.0. Spoken frequency lists from FrequencyWords by Hermit Dave (OpenSubtitles), CC BY-SA 4.0. Academic words and Expressions from Akademisk ordlista and Swe-MWELex, Språkbanken, CC BY 4.0. German and French memory hints from Wiktionary (WikDict, kaikki.org), CC BY-SA 4.0. Daily reminders are set in the iPhone app.</div>
    </div>`;
}
