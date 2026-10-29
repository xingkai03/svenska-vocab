// A word can have several example sentences. They are stored one per line in `example`, with the English
// translations on the matching lines of `exampleTranslation`, so the cloud schema and older app versions stay as
// they were (an older version simply shows all of them). Same rules as ExampleSentences.swift in the app.

/** The example sentences of a word, as { sv, en } pairs. Lines without a Swedish sentence are left out. */
export function splitExamples(example = "", translation = "") {
  const en = translation.split("\n");
  return example.split("\n").map((sv, i) => ({ sv: sv.trim(), en: (en[i] ?? "").trim() })).filter((p) => p.sv);
}

/** The stored form of a list of example sentences: { example, exampleTranslation }. */
export function joinExamples(pairs) {
  const line = (s) => (s ?? "").replace(/\s*[\r\n]+\s*/g, " ").trim();
  const kept = pairs.map((p) => ({ sv: line(p.sv), en: line(p.en) })).filter((p) => p.sv);
  return {
    example: kept.map((p) => p.sv).join("\n"),
    exampleTranslation: kept.map((p) => p.en).join("\n").replace(/\n+$/, ""),
  };
}

/** The first example sentence, shown on cards that have room for only one. */
export function mainExample(entry) {
  return splitExamples(entry?.example, entry?.exampleTranslation)[0] ?? { sv: "", en: "" };
}
