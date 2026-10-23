import { fold } from "./dictionary.js";

/**
 * Grades a typed answer in the spelling exercise. Accepts the base word or any of its inflected
 * forms, and counts a missing å/ä/ö or a small typo as "almost" instead of wrong.
 * Returns { kind: "correct" | "diacritics" | "typo" | "wrong", form }, where form is the
 * inflected form that matched (null for the base word). Mirrors SpellingChecker.swift.
 */
export function checkSpelling(typed, word, forms) {
  const given = normalize(typed);
  const base = normalize(word);
  if (!given || !base) return { kind: "wrong", form: null };
  const candidates = [base, ...forms.map(normalize).filter((f) => f && f !== base)];
  const form = (c) => (c === base ? null : c);

  const hit = candidates.find((c) => c === given);
  if (hit) return { kind: "correct", form: form(hit) };
  const folded = fold(given);
  if (candidates.some((c) => fold(c) === folded)) return { kind: "diacritics", form: null };
  let close = null;
  for (const c of candidates) {
    const d = distance(folded, fold(c));
    if (d <= allowedTypos([...c].length) && (!close || d < close.d)) close = { c, d };
  }
  if (close) return { kind: "typo", form: form(close.c) };
  return { kind: "wrong", form: null };
}

/** Short words allow no typos, since one changed letter usually makes another word. */
export const allowedTypos = (length) => (length < 4 ? 0 : length < 8 ? 1 : 2);

/** Lowercased, single spaced, without a leading "en", "ett" or "att". */
export function normalize(s) {
  let t = s.toLowerCase().trim().split(/\s+/).join(" ");
  for (const prefix of ["en ", "ett ", "att "]) if (t.startsWith(prefix)) t = t.slice(prefix.length);
  return t;
}

/** Edit distance counting insertions, deletions, substitutions and swapped neighbours. */
export function distance(a, b) {
  a = [...a];
  b = [...b];
  if (!a.length) return b.length;
  if (!b.length) return a.length;
  const d = Array.from({ length: a.length + 1 }, (_, i) => Array.from({ length: b.length + 1 }, (_, j) => (i === 0 ? j : j === 0 ? i : 0)));
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
    }
  }
  return d[a.length][b.length];
}
