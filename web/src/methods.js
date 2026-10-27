// Mixed review: picks a review method for each card, leaning toward the methods the learner finds hardest for that
// word (e.g. a word recognised at a glance but not spelled from English). Strength per method comes from the review
// history, which records the method used, so it is the same on every device.
// Keep in sync with SvenskaVocab/Services/ReviewMethods.swift.

import { AGAIN, HARD } from "./scheduler.js";

export const METHOD_IDS = ["flashcards", "reverse", "choice", "listening", "spelling"];

/** Methods turned on in Settings (`disabled` is the disabledReviewModes setting); all of them if every one is off. */
export function enabledMethods(disabled) {
  const off = new Set(disabled.split(",").filter(Boolean));
  const on = METHOD_IDS.filter((id) => !off.has(id));
  return on.length ? on : METHOD_IDS;
}

const credit = (grade) => (grade === AGAIN ? 0 : grade === HARD ? 0.5 : 1);

/**
 * How well the learner does in `mode` on this word, from 0 (always wrong) to 1 (always right). `attempts` are the
 * word's answers ({ mode, grade }), oldest first. Recent answers count most; a method never tried starts at 0.5.
 */
export function strength(mode, attempts) {
  let score = 0.5, weight = 1, w = 1;
  for (let i = attempts.length - 1; i >= 0; i--) {
    if (attempts[i].mode !== mode) continue;
    score += w * credit(attempts[i].grade);
    weight += w;
    w *= 0.6;
  }
  return score / weight;
}

/**
 * Chooses a method for the next card. Weak methods are picked most, but strong ones still come up now and then so a
 * fading skill gets noticed. A method just answered right is less likely next time, for variety.
 */
export function pickMethod(methods, attempts) {
  if (methods.length <= 1) return methods[0] ?? "flashcards";
  const last = attempts.at(-1);
  const rested = last && last.grade !== AGAIN ? last.mode : null;
  const weights = methods.map((m) => {
    const w = 0.1 + (1 - strength(m, attempts)) ** 2;
    return m === rested ? w * 0.5 : w;
  });
  let r = Math.random() * weights.reduce((a, b) => a + b, 0);
  for (let i = 0; i < methods.length; i++) {
    if (r < weights[i]) return methods[i];
    r -= weights[i];
  }
  return methods.at(-1);
}
