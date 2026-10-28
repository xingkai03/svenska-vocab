#!/usr/bin/env node
// Checks the web version's scheduler, inflection rules, spelling checker and review-method picker against the test
// cases the iOS app's tests use too (SvenskaVocabTests/SharedCases.json), so the two implementations stay in step.
//
//     node scripts/test_web.mjs

import { readFileSync } from "node:fs";
import { inflectionStems } from "../web/src/dictionary.js";
import { enabledMethods, strength } from "../web/src/methods.js";
import { next, retentionAfter } from "../web/src/scheduler.js";
import { checkSpelling } from "../web/src/spelling.js";

const cases = JSON.parse(readFileSync(new URL("../SvenskaVocabTests/SharedCases.json", import.meta.url), "utf8"));
const round = (x) => Math.round(x * 1e6) / 1e6;
let failures = 0, count = 0;

function check(name, actual, expected) {
  count += 1;
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a === e) return;
  failures += 1;
  console.error(`✗ ${name}\n    expected ${e}\n    got      ${a}`);
}

for (const c of cases.scheduler) {
  const n = next(c.state, c.grade);
  check(`scheduler ${JSON.stringify(c.state)} grade ${c.grade}`,
    { easeFactor: round(n.easeFactor), interval: n.interval, repetitions: n.repetitions, lapses: n.lapses }, c.expected);
}
for (const c of cases.retention) {
  check(`retention ${c.elapsedDays}d / ${c.stability}`, round(retentionAfter(c.elapsedDays, c.stability)), c.expected);
}
for (const c of cases.stems) check(`stems of ${c.word}`, inflectionStems(c.word), c.expected);
for (const c of cases.spelling) {
  check(`spelling "${c.typed}" for ${c.word}`, checkSpelling(c.typed, c.word, c.forms), c.expected);
}
for (const c of cases.methodStrength) {
  check(`strength of ${c.mode} after ${c.attempts.length}`, round(strength(c.mode, c.attempts)), c.expected);
}
for (const c of cases.enabled) check(`enabled methods with "${c.disabled}" off`, enabledMethods(c.disabled), c.expected);

console.log(failures ? `${failures} of ${count} checks failed` : `All ${count} checks passed`);
process.exit(failures ? 1 : 0);
