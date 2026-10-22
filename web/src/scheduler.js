// SM-2 style spaced repetition with an exponential forgetting curve; the same rules as Scheduler.swift.
// The interval is treated as the memory's "stability": the number of days after which recall probability
// has decayed to about 90 %, i.e. R(t) = 0.9^(t / interval).

export const DAY = 86_400_000;

export const GRADES = [
  { value: 0, title: "Again", color: "red", quality: 1 },
  { value: 1, title: "Hard", color: "orange", quality: 3 },
  { value: 2, title: "Good", color: "green", quality: 4 },
  { value: 3, title: "Easy", color: "blue", quality: 5 },
];
export const AGAIN = 0, HARD = 1, GOOD = 2, EASY = 3;

const RELEARN_DELAY = 10 * 60 * 1000;

export function next(s, grade) {
  const n = { ...s };
  if (grade === AGAIN) {
    n.repetitions = 0;
    n.lapses += 1;
    n.interval = 0;
  } else {
    n.repetitions += 1;
    if (n.repetitions === 1) {
      n.interval = grade === EASY ? 4 : grade === HARD ? 1 : 2;
    } else if (n.repetitions === 2) {
      n.interval = grade === HARD ? 3 : grade === EASY ? 8 : 6;
    } else {
      const bonus = grade === HARD ? 0.8 : grade === EASY ? 1.3 : 1.0;
      n.interval = Math.max(s.interval + 1, Math.round(Math.max(s.interval, 1) * s.easeFactor * bonus));
    }
    n.interval = Math.min(n.interval, 3650);
  }
  const q = GRADES[grade].quality;
  n.easeFactor = Math.max(1.3, s.easeFactor + 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02));
  return n;
}

/** Returns the word with the grade applied (a new object). */
export function apply(grade, word, now = Date.now()) {
  const n = next(word, grade);
  const dueDate = n.interval === 0 ? now + RELEARN_DELAY : addDays(startOfDay(now), n.interval);
  return {
    ...word,
    easeFactor: n.easeFactor, interval: n.interval, repetitions: n.repetitions, lapses: n.lapses,
    reviewCount: word.reviewCount + 1, lastReviewedAt: now, dueDate,
  };
}

/** Human-readable interval that a grade would produce, for the answer buttons. */
export const preview = (grade, word) => formatInterval(next(word, grade).interval);

export function formatInterval(days) {
  if (days === 0) return "10m";
  if (days < 30) return `${days}d`;
  if (days < 365) return `${Math.floor(days / 30)}mo`;
  return `${(days / 365).toFixed(1)}y`;
}

/** Probability of recall at `date` according to the forgetting curve. */
export function retention(word, date = Date.now()) {
  if (word.lastReviewedAt == null) return 0;
  return retentionAfter(Math.max(0, (date - word.lastReviewedAt) / DAY), word.interval);
}

export function retentionAfter(elapsedDays, stability) {
  // A just-failed card has low stability; give it a short half-life rather than zero.
  return Math.pow(0.9, elapsedDays / Math.max(stability, 0.25));
}

export const isDue = (word, now = Date.now()) => word.dueDate <= now;

export function mastery(word) {
  if (word.reviewCount === 0) return "New";
  if (word.interval < 7) return "Learning";
  if (word.interval < 21) return "Familiar";
  return "Mastered";
}
export const MASTERY = ["New", "Learning", "Familiar", "Mastered"];

// Calendar helpers (local time, like Calendar.current in the app).

export function startOfDay(t) {
  const d = new Date(t);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

export function addDays(t, days) {
  const d = new Date(t);
  d.setDate(d.getDate() + days);
  return d.getTime();
}

export const isSameDay = (a, b) => startOfDay(a) === startOfDay(b);
export const isToday = (t) => isSameDay(t, Date.now());

/** The local calendar day as "2026-10-21", the key check-ins are stored under. */
export function dayString(t) {
  const d = new Date(t);
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

export function dayFromString(s) {
  const [y, m, d] = s.split("-").map(Number);
  return new Date(y, m - 1, d).getTime();
}

/** Consecutive checked-in days ending today (or yesterday, if today is not checked in yet). */
export function currentStreak(days, now = Date.now()) {
  let day = startOfDay(now);
  if (!days.has(dayString(day))) day = addDays(day, -1);
  let count = 0;
  while (days.has(dayString(day))) {
    count += 1;
    day = addDays(day, -1);
  }
  return count;
}

export function bestStreak(days) {
  let best = 0, run = 0, previous = null;
  for (const s of [...days].sort()) {
    const day = dayFromString(s);
    run = previous != null && dayString(addDays(previous, 1)) === s ? run + 1 : 1;
    best = Math.max(best, run);
    previous = day;
  }
  return best;
}
