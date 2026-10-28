import { html, useState } from "../../vendor/preact-htm.js";
import { BarChart, LineChart } from "../charts.js";
import {
  addDays, bestStreak, currentStreak, dayString, isSameDay, mastery, MASTERY, retention, retentionAfter, startOfDay, DAY,
} from "../scheduler.js";
import { useKeys } from "../keys.js";
import { store } from "../store.js";
import { Icon, NavBar, href } from "../ui.js";

const MASTERY_COLORS = { New: "var(--gray)", Learning: "var(--orange)", Familiar: "var(--blue)", Mastered: "var(--green)" };

export function SummaryView() {
  const words = [...store.words.values()];
  const logs = store.logs;
  const days = new Set(store.checkIns.keys());
  const now = Date.now();
  const since = now - 30 * DAY;
  const recent = logs.filter((l) => l.date >= since);
  const accuracy = recent.length ? recent.filter((l) => l.grade !== 0).length / recent.length : null;
  const hardest = words.filter((w) => w.lapses > 0).sort((a, b) => b.lapses - a.lapses).slice(0, 5);

  return html`
    <${NavBar} title="Summary" large />
    <div class="page"><div class="stack">
      <div class="tiles">
        <${Tile} value=${words.length} label="Words" icon="books" color="var(--blue)" />
        <${Tile} value=${words.filter((w) => mastery(w) === "Mastered").length} label="Mastered" icon="seal" color="var(--green)" />
        <${Tile} value=${currentStreak(days)} label="Day streak" icon="flame" color="var(--orange)" />
        <${Tile} value=${bestStreak(days)} label="Best streak" icon="trophy" color="var(--yellow)" />
        <${Tile} value=${logs.length} label="Reviews" icon="repeat" color="var(--purple)" />
        <${Tile} value=${accuracy == null ? "–" : `${Math.round(accuracy * 100)}%`} label="Accuracy 30d" icon="target" color="var(--pink)" />
      </div>
      <${Activity} words=${words} logs=${logs} />
      ${words.length ? html`<${MasteryCard} words=${words} /><${ForgettingCurve} words=${words} /><${Forecast} words=${words} />` : null}
      <${CheckInCalendar} days=${days} />
      ${hardest.length ? html`<div class="card"><h3>Trickiest words</h3>
        ${hardest.map((w) => html`<a class="row" style="color:inherit" href=${href("word", w.key)}>
          <span class="bold">${w.word}</span><span class="secondary clamp1" style="flex:1">${w.translation}</span>
          <span class="caption red">forgotten ${w.lapses}×</span></a>`)}
      </div>` : null}
    </div></div>`;
}

function Tile({ value, label, icon, color }) {
  return html`<div class="tile"><span style=${{ color }}><${Icon} name=${icon} /></span>
    <span class="value">${value}</span><span class="caption2 secondary">${label}</span></div>`;
}

const shortDate = new Intl.DateTimeFormat(undefined, { day: "numeric", month: "narrow" });
const weekdayShort = new Intl.DateTimeFormat(undefined, { weekday: "short" });

function Activity({ words, logs }) {
  const today = startOfDay(Date.now());
  const first = addDays(today, -13);
  // One pass over the history: counts per day key. Logs are oldest first, so stop at the first one in range.
  const reviews = new Map(), added = new Map();
  for (let i = logs.length - 1; i >= 0 && logs[i].date >= first; i--) {
    const k = dayString(logs[i].date);
    reviews.set(k, (reviews.get(k) ?? 0) + 1);
  }
  for (const w of words) {
    if (w.addedAt < first) continue;
    const k = dayString(w.addedAt);
    added.set(k, (added.get(k) ?? 0) + 1);
  }
  const columns = [];
  for (let offset = 13; offset >= 0; offset--) {
    const day = addDays(today, -offset);
    const k = dayString(day);
    columns.push({
      label: shortDate.format(day),
      values: [
        { value: reviews.get(k) ?? 0, color: "var(--accent)" },
        { value: added.get(k) ?? 0, color: "var(--purple)" },
      ],
    });
  }
  return html`<div class="card"><h3>Last 14 days</h3>
    <${BarChart} columns=${columns} labelEvery=${2} ariaLabel="Reviews and new words per day, last 14 days" />
    <div class="legend"><span style="--dot:var(--accent)">Reviews</span><span style="--dot:var(--purple)">New words</span></div>
  </div>`;
}

function MasteryCard({ words }) {
  const counts = Object.fromEntries(MASTERY.map((m) => [m, 0]));
  for (const w of words) counts[mastery(w)] += 1;
  const max = Math.max(1, ...Object.values(counts));
  return html`<div class="card"><h3>Mastery</h3>
    ${MASTERY.map((m) => html`<div class="row" style="gap:8px">
      <span class="caption secondary" style="width:64px">${m}</span>
      <div style="flex:1;display:flex;align-items:center;gap:6px">
        <div style=${{ width: `${(counts[m] / max) * 85}%`, minWidth: counts[m] ? "4px" : "0", height: "18px", borderRadius: "4px", background: MASTERY_COLORS[m] }}></div>
        <span class="caption">${counts[m]}</span>
      </div></div>`)}
    <div class="caption2 secondary">Learning: next review within a week · Familiar: 1–3 weeks · Mastered: 3+ weeks</div>
  </div>`;
}

/** Average predicted recall of the collection over the next 30 days if no reviews happen,
 *  compared with a single unreviewed memory (classic Ebbinghaus curve). */
function ForgettingCurve({ words }) {
  const reviewed = words.filter((w) => w.lastReviewedAt != null);
  const now = Date.now();
  const without = [], yours = [];
  for (let day = 0; day <= 30; day++) {
    without.push([day, retentionAfter(day, 1)]);
    if (reviewed.length) {
      const date = addDays(now, day);
      yours.push([day, reviewed.reduce((s, w) => s + retention(w, date), 0) / reviewed.length]);
    }
  }
  const series = [{ color: "var(--gray)", points: without }];
  if (yours.length) series.push({ color: "var(--accent)", points: yours });
  return html`<div class="card"><h3>Forgetting curve</h3>
    <${LineChart} series=${series} xMax=${30} xLabel="days from today" ariaLabel="Predicted recall over the next 30 days" />
    <div class="legend">${yours.length ? html`<span style="--dot:var(--accent)">Your words</span>` : null}<span style="--dot:var(--gray)">Without review</span></div>
    <div class="caption2 secondary">Predicted recall if you stop reviewing today. Each review resets a word's curve and makes it decay more slowly — that's why the app schedules reviews just before you'd forget.</div>
  </div>`;
}

function Forecast({ words }) {
  const today = startOfDay(Date.now());
  const columns = [];
  for (let offset = 0; offset < 7; offset++) {
    const day = addDays(today, offset);
    const end = addDays(day, 1);
    const count = words.filter((w) => (offset === 0 ? w.dueDate < end : w.dueDate >= day && w.dueDate < end)).length;
    columns.push({ label: weekdayShort.format(day), values: [{ value: count, color: "var(--teal)" }] });
  }
  return html`<div class="card"><h3>Upcoming reviews</h3>
    <${BarChart} columns=${columns} height=${140} annotate ariaLabel="Words due on each of the next 7 days" /></div>`;
}

/** Month calendar with check-in days highlighted. */
function CheckInCalendar({ days }) {
  const [month, setMonth] = useState(() => {
    const d = new Date();
    return new Date(d.getFullYear(), d.getMonth(), 1).getTime();
  });
  const first = new Date(month);
  const count = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
  const firstWeekday = weekStart();
  const leading = (first.getDay() - firstWeekday + 7) % 7;
  const weekdayNarrow = new Intl.DateTimeFormat(undefined, { weekday: "narrow" });
  // 2023-01-01 was a Sunday.
  const symbols = [...Array(7)].map((_, i) => weekdayNarrow.format(new Date(2023, 0, 1 + ((i + firstWeekday) % 7))));
  const cells = [...Array(leading).fill(null), ...[...Array(count)].map((_, i) => new Date(first.getFullYear(), first.getMonth(), i + 1).getTime())];
  const isCurrentMonth = first.getFullYear() === new Date().getFullYear() && first.getMonth() === new Date().getMonth();
  const shift = (n) => setMonth(new Date(first.getFullYear(), first.getMonth() + n, 1).getTime());
  useKeys([
    [["["], "Previous month", () => shift(-1)],
    [["]"], "Next month", !isCurrentMonth && (() => shift(1))],
  ]);
  const inMonth = cells.filter((d) => d != null && days.has(dayString(d))).length;
  return html`<div class="card">
    <div class="row">
      <h3 style="flex:1">Check-ins</h3>
      <button class="icon-button" onClick=${() => shift(-1)} aria-label="Previous month"><${Icon} name="chevronLeft" /></button>
      <span class="subheadline mono">${first.toLocaleDateString(undefined, { month: "long", year: "numeric" })}</span>
      <button class="icon-button" disabled=${isCurrentMonth} onClick=${() => shift(1)} aria-label="Next month"><${Icon} name="chevronRight" /></button>
    </div>
    <div class="calendar">
      ${symbols.map((s) => html`<span class="caption2 secondary">${s}</span>`)}
      ${cells.map((d) => d == null ? html`<span></span>`
        : html`<span class=${`day ${days.has(dayString(d)) ? "checked" : ""} ${isSameDay(d, Date.now()) ? "today" : ""}`}>${new Date(d).getDate()}</span>`)}
    </div>
    <div class="caption secondary">${inMonth} check-ins this month</div>
  </div>`;
}

/** First day of the week for the browser's locale (0 = Sunday). */
function weekStart() {
  try {
    const info = new Intl.Locale(navigator.language).weekInfo ?? new Intl.Locale(navigator.language).getWeekInfo?.();
    if (info?.firstDay) return info.firstDay % 7;
  } catch {}
  return /^en-US|^en-CA|^ja|^zh-TW|^he/.test(navigator.language) ? 0 : 1;
}
