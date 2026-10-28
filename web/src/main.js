import { html, render, useEffect, useState } from "../vendor/preact-htm.js";
import { cloud } from "./cloud.js";
import { ShortcutHelp } from "./keys.js";
import { dictionary } from "./dictionary.js";
import { isDue } from "./scheduler.js";
import { store } from "./store.js";
import { Icon, href, parseRoute } from "./ui.js";
import { AccountView, SignInView } from "./views/account.js";
import { WordDetailView } from "./views/detail.js";
import { EditWordView } from "./views/edit.js";
import { LearnView } from "./views/learn.js";
import { LookupView } from "./views/lookup.js";
import { ReadView } from "./views/read.js";
import { ReviewView } from "./views/review.js";
import { SettingsView } from "./views/settings.js";
import { SummaryView } from "./views/summary.js";
import { SvtView } from "./views/svt.js";
import { TodayView } from "./views/today.js";
import { WordsView } from "./views/words.js";

const TABS = [
  { name: "today", title: "Today", icon: "sun" },
  { name: "lookup", title: "Lookup", icon: "search" },
  { name: "words", title: "Words", icon: "books" },
  { name: "summary", title: "Summary", icon: "chart" },
];
let lastTab = "today";

function Page({ route }) {
  const { name, args, query } = route;
  switch (name) {
    case "today": return html`<${TodayView} />`;
    case "lookup": return html`<${LookupView} query=${query.q ?? ""} />`;
    case "words": return html`<${WordsView} />`;
    case "summary": return html`<${SummaryView} />`;
    case "learn": return html`<${LearnView} />`;
    case "review": return html`<${ReviewView} key=${location.hash} modeId=${args[0]} practice=${query.practice === "1"} />`;
    case "svt": return html`<${SvtView} key=${route.hash} query=${query} />`;
    case "read": return html`<${ReadView} args=${args} query=${query} />`;
    case "word": return html`<${WordDetailView} key=${args[0]} id=${args[0]} />`;
    case "new": return html`<${EditWordView} key=${location.hash} prefill=${query.prefill ?? ""} />`;
    case "edit": return html`<${EditWordView} key=${args[0]} id=${args[0]} />`;
    case "settings": return html`<${SettingsView} />`;
    case "account": return html`<${AccountView} />`;
    case "signin": return html`<${SignInView} />`;
    default: return html`<${TodayView} />`;
  }
}

function App() {
  const [route, setRoute] = useState(parseRoute);
  const [, setVersion] = useState(0);

  useEffect(() => {
    const rerender = () => setVersion((v) => v + 1);
    const unsubscribe = [store.subscribe(rerender), cloud.subscribe(rerender)];
    const onHash = () => {
      setRoute(parseRoute());
      scrollTo(0, 0);
    };
    addEventListener("hashchange", onHash);
    // Relative times ("Synced 2 minutes ago") and due counts move on by themselves.
    const tick = setInterval(rerender, 30_000);
    return () => {
      unsubscribe.forEach((u) => u());
      removeEventListener("hashchange", onHash);
      clearInterval(tick);
    };
  }, []);

  if (TABS.some((t) => t.name === route.name)) lastTab = route.name;
  else if (route.name === "svt" || route.name === "read") lastTab = "lookup";
  const now = Date.now();
  let due = 0;
  for (const w of store.words.values()) if (isDue(w, now)) due += 1;

  return html`<div class="shell">
    <nav class="tabbar" aria-label="Main">
      <div class="brand"><img src="icon-180.png" alt="" />Svenska</div>
      ${TABS.map((t) => html`<a class=${`tab ${lastTab === t.name ? "active" : ""}`} href=${href(t.name)}
        aria-current=${route.name === t.name ? "page" : undefined}>
        <${Icon} name=${t.icon} /><span>${t.title}</span><span class="tab-key">${t.title[0]}</span>
        ${t.name === "words" && due > 0 ? html`<span class="badge">${due}</span>` : null}
      </a>`)}
    </nav>
    <main class="main"><${Page} route=${route} /></main>
    <${ShortcutHelp} />
  </div>`;
}

async function start() {
  const root = document.getElementById("app");
  try {
    await Promise.all([store.load(), cloud.signInFromLink(), dictionary.load()]);
  } catch (error) {
    root.innerHTML = "";
    root.append(Object.assign(document.createElement("div"), { className: "splash", textContent: error.message }));
    return;
  }
  // "I know it" words from older versions become saved, mastered words.
  const migrate = () => store.migrateSkippedWords((id) => dictionary.entry(id));
  migrate();
  store.subscribe(migrate);
  render(html`<${App} />`, root);

  // Sync when the page opens or comes back into view, a few seconds after each change, and every few minutes.
  store.onLocalChange = () => cloud.scheduleSync();
  if (cloud.session) {
    await cloud.loadStatus();
    cloud.sync();
  }
  setInterval(() => document.visibilityState === "visible" && cloud.sync(), 180_000);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") store.flush();
    cloud.sync();
  });
  addEventListener("online", () => cloud.sync());
}

start();
