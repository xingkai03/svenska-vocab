import { html } from "../../vendor/preact-htm.js";
import { useState } from "../../vendor/preact-htm.js";
import { dictionary, headword } from "../dictionary.js";
import { addDays, currentStreak, dayString, isDue, isToday, startOfDay } from "../scheduler.js";
import { entryId, store } from "../store.js";
import { Icon, NavBar, SpeakButton, go, href } from "../ui.js";
import { REVIEW_MODES } from "./review.js";

export function todayStats() {
  const words = [...store.words.values()];
  const today = startOfDay(Date.now());
  let reviewsToday = 0;
  for (let i = store.logs.length - 1; i >= 0 && store.logs[i].date >= today; i--) reviewsToday += 1;
  const newToday = words.filter((w) => isToday(w.addedAt)).length;
  return { words, reviewsToday, newToday, doneToday: reviewsToday + newToday, dueCount: words.filter((w) => isDue(w)).length };
}

function greeting() {
  const h = new Date().getHours();
  return h >= 5 && h < 10 ? "God morgon!" : h >= 10 && h < 18 ? "Hej!" : "God kväll!";
}

export function TodayView() {
  const { words, reviewsToday, newToday, doneToday, dueCount } = todayStats();
  const dailyGoal = store.get("dailyGoal");
  const days = new Set(store.checkIns.keys());
  const streak = currentStreak(days);
  const checkedInToday = days.has(dayString(Date.now()));
  const [celebrate, setCelebrate] = useState(0);

  const checkIn = () => {
    store.checkIn(doneToday);
    setCelebrate(Date.now());
    setTimeout(() => setCelebrate(0), 1600);
  };

  const progress = Math.min(1, doneToday / Math.max(dailyGoal, 1));
  const circumference = 2 * Math.PI * 32;

  return html`
    <${NavBar} title=${greeting()} large right=${html`
      <button class="bar-button" onClick=${() => go("settings")} aria-label="Settings" title="Settings"><${Icon} name="gear" /></button>`} />
    <div class="page"><div class="stack">

      <div class="card">
        <div class="row" style="gap:16px">
          <div class="ring">
            <svg viewBox="0 0 72 72"><circle cx="36" cy="36" r="32" fill="none" stroke="var(--fill)" stroke-width="8" />
              <circle cx="36" cy="36" r="32" fill="none" stroke="var(--accent)" stroke-width="8" stroke-linecap="round"
                stroke-dasharray=${circumference} stroke-dashoffset=${circumference * (1 - progress)} style="transition: stroke-dashoffset .4s ease-out" /></svg>
            <div class="label"><span class="title3 bold">${doneToday}</span><span class="caption2 secondary">of ${dailyGoal}</span></div>
          </div>
          <div style="display:flex;flex-direction:column;gap:4px">
            <div class=${`headline ${streak > 0 ? "orange" : "secondary"}`}><${Icon} name="flame" /> ${streak}-day streak</div>
            <div class="caption secondary">${reviewsToday} reviews · ${newToday} new words today</div>
            ${checkedInToday
              ? html`<div class="subheadline bold green"><${Icon} name="checkCircle" /> Checked in today</div>`
              : html`<div><button class="btn prominent small" disabled=${doneToday < dailyGoal} onClick=${checkIn}>
                  ${doneToday >= dailyGoal ? "Check in" : "Reach your goal to check in"}</button></div>`}
          </div>
        </div>
        <${WeekStrip} days=${days} />
      </div>

      <div class="card">
        <div class="row">
          <div style="flex:1">
            <div class="headline">Review</div>
            <div class="subheadline secondary">${words.length === 0 ? "Your collection is empty"
              : dueCount === 0 ? "All caught up — nothing due" : `${dueCount} words due now`}</div>
          </div>
          ${dueCount > 0 ? html`<a class="btn prominent" href=${href("review", "flashcards")}>Start</a>` : null}
        </div>
        ${words.length ? html`
          <div class="mode-grid">
            ${REVIEW_MODES.map((m) => html`<button onClick=${() => go("review", m.id, dueCount === 0 ? { practice: 1 } : {})}>
              <${Icon} name=${m.icon} />${m.title}</button>`)}
          </div>
          ${dueCount === 0 ? html`<div class="caption2 secondary">Practice mode: reviewing ahead of schedule won't change due dates.</div>` : null}` : null}
      </div>

      <a class="card card-link" href=${href("learn")}>
        <div class="row">
          <span class="purple title3"><${Icon} name="sparkles" /></span>
          <div style="flex:1">
            <div class="headline">Learn new words</div>
            <div class="caption secondary">Core words, CEFR levels A1–C2, coursebook, spoken and topic lists</div>
          </div>
          <span class="tertiary"><${Icon} name="chevronRight" /></span>
        </div>
      </a>

      <${WordOfTheDay} />
    </div></div>
    ${celebrate ? html`<div class="celebrate"><div>Bra jobbat! 🎉</div></div>` : null}`;
}

function WeekStrip({ days }) {
  const today = startOfDay(Date.now());
  const weekday = new Intl.DateTimeFormat(undefined, { weekday: "narrow" });
  return html`<div class="week">
    ${[6, 5, 4, 3, 2, 1, 0].map((offset) => {
      const day = addDays(today, -offset);
      const checked = days.has(dayString(day));
      return html`<div><div class="caption2 secondary">${weekday.format(day)}</div>
        <span class=${checked ? "orange" : "tertiary"}><${Icon} name=${checked ? "flame" : "circle"} /></span></div>`;
    })}
  </div>`;
}

function WordOfTheDay() {
  const entry = dictionary.wordOfTheDay();
  if (!entry) return null;
  const saved = store.words.has(entryId(entry));
  return html`<div class="card">
    <div class="caption bold secondary">Word of the day</div>
    <div class="row" style="gap:4px">
      <span class="title">${headword(entry)}</span>
      <${SpeakButton} text=${entry.word} />
      <span class="spacer"></span>
      <button class="icon-button" disabled=${saved} onClick=${() => store.addToCollection(entry)}
        aria-label=${saved ? "In your collection" : "Add to collection"} title=${saved ? "In your collection" : "Add to collection"}>
        <${Icon} name=${saved ? "bookmarkFill" : "bookmark"} /></button>
    </div>
    <div>${entry.translation}</div>
    ${entry.example ? html`<div class="italic">${entry.example}</div><div class="caption secondary">${entry.exampleTranslation}</div>` : null}
    <a class="subheadline" href=${href("word", entry.id)}>Details</a>
  </div>`;
}
