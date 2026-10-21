#!/usr/bin/env python3
"""Build the open word-list decks (Resources/Decks/deck_*.tsv) from two openly licensed sources.

Download the sources first:

    curl -LO https://cental.uclouvain.be/cefrlex/static/resources/sv/SVALex_v2.tsv
    curl -LO https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/sv/sv_50k.txt

then run from the repository root, after build_folkets.py and build_kelly.py:

    python3 scripts/build_open_decks.py SVALex_v2.tsv sv_50k.txt

- SVALex (CC BY-NC-SA 4.0): vocabulary of Swedish L2 coursebooks with frequencies per CEFR level.
  Each lemma gets the first level where it occurs in at least two coursebook texts (or, failing that,
  the first level where it occurs at all), giving decks "Coursebook A1" … "Coursebook C1", most
  frequent first.
- FrequencyWords sv_50k (CC BY-SA 4.0, from OpenSubtitles): spoken-language word forms by frequency.
  Forms are mapped to dictionary headwords through the dictionary's inflected forms, giving
  "Spoken top 1000" and "Spoken 1001–3000".

Only words that exist in core_vocabulary.tsv or folkets_sv_en.tsv are kept; rows hold just word and
part of speech, and the app fills in the rest from the dictionary.
"""

import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "SvenskaVocab" / "Resources"
DECKS = RESOURCES / "Decks"

LEVELS = ["a1", "a2", "b1", "b2", "c1"]

SVALEX_TAGS = {
    "NN": "noun", "VB": "verb", "JJ": "adjective", "AB": "adverb", "PP": "preposition",
    "PN": "pronoun", "HP": "pronoun", "DT": "pronoun", "KN": "conjunction", "SN": "conjunction",
    "RG": "numeral", "RO": "numeral", "IN": "interjection", "PC": "adjective",
}


def load_dictionary():
    """Entries in file order: (word, pos, forms, is_core)."""
    entries = []
    for name, core in [("core_vocabulary.tsv", True), ("folkets_sv_en.tsv", False)]:
        for line in (RESOURCES / name).read_text(encoding="utf-8").splitlines():
            if not line or line.startswith("#"):
                continue
            c = line.split("\t")
            if len(c) >= 5:
                entries.append((c[0], c[1], c[3], core))
    return entries


ENTRIES = load_dictionary()
BY_ID, BY_WORD = {}, {}
for word, pos, _, core in ENTRIES:
    BY_ID.setdefault((word.lower(), pos), (word, pos, core))
    BY_WORD.setdefault(word.lower(), (word, pos, core))


def match(word, pos):
    return BY_ID.get((word.lower(), pos)) or BY_WORD.get(word.lower())


def write_deck(filename, name, group, source, rows):
    DECKS.mkdir(parents=True, exist_ok=True)
    with (DECKS / filename).open("w", encoding="utf-8", newline="\n") as out:
        out.write(f"# deck: {name}\n# group: {group}\n# Source: {source}\n")
        for word, pos in rows:
            out.write(f"{word}\t{pos}\n")
    print(f"{name}: {len(rows)} words")


def svalex(path):
    decks = {level: [] for level in LEVELS}
    seen = set()
    with open(path, encoding="utf-8") as f:
        rows = list(csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE))
    rows.sort(key=lambda r: -float(r["total_freq@total"] or 0))
    total = 0
    for r in rows:
        word = (r["word"] or "").strip()
        tag = (r["tag"] or "").split("_")[0]
        if not word or tag.startswith("PM") or tag in ("PL", "MAD", "MID", "PAD"):
            continue
        total += 1
        pos = SVALEX_TAGS.get(tag.removesuffix("M"), "phrase")
        docs = [float(r[f"nb_doc@{level}"] or 0) for level in LEVELS]
        freqs = [float(r[f"level_freq@{level}"] or 0) for level in LEVELS]
        level_index = next((i for i, d in enumerate(docs) if d >= 2), None)
        if level_index is None:
            level_index = next((i for i, f in enumerate(freqs) if f > 0), None)
        target = match(word, pos)
        if level_index is None or target is None or target[:2] in seen:
            continue
        seen.add(target[:2])
        decks[LEVELS[level_index]].append(target[:2])
    source = ("SVALex, François, Volodina, Pilán & Tack (2016), "
              "https://cental.uclouvain.be/cefrlex/svalex/, CC BY-NC-SA 4.0")
    for i, level in enumerate(LEVELS, 1):
        write_deck(f"deck_svalex_{i}_{level}.tsv", f"Coursebook {level.upper()}", "Coursebook", source, decks[level])
    print(f"  SVALex: {len(seen)} of {total} lemmas matched")


def spoken(path):
    # Word form -> headword. Core words (headwords, then their forms) win over Folkets entries, so
    # "skrivit" maps to skriva rather than to a Folkets participle entry.
    by_form = {}
    for tier in (True, False):
        entries = [e for e in ENTRIES if e[3] == tier]
        for word, pos, forms, core in entries:
            by_form.setdefault(word.lower(), (word, pos))
        for word, pos, forms, core in entries:
            for form in forms.split(","):
                form = form.strip().lower()
                if form:
                    by_form.setdefault(form, (word, pos))
    core_words = {word.lower() for word, _, _, core in ENTRIES if core}
    result, seen = [], set()
    for line in open(path, encoding="utf-8"):
        parts = line.split()
        if len(parts) != 2 or len(parts[0]) < 2:
            continue
        target = by_form.get(parts[0].lower())
        if target is None or target in seen:
            continue
        word, pos = target
        # Names and filler sounds ("eh", "mm") aren't vocabulary; keep interjections the core list has (hej, tack).
        if word[:1].isupper() or (pos == "interjection" and word.lower() not in core_words):
            continue
        seen.add(target)
        result.append(target)
        if len(result) == 3000:
            break
    source = "FrequencyWords (Hermit Dave), OpenSubtitles 2018 sv_50k, CC BY-SA 4.0"
    write_deck("deck_spoken_1_top1000.tsv", "Spoken top 1000", "Spoken frequency", source, result[:1000])
    write_deck("deck_spoken_2_1001_3000.tsv", "Spoken 1001–3000", "Spoken frequency", source, result[1000:3000])


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    svalex(sys.argv[1])
    spoken(sys.argv[2])


if __name__ == "__main__":
    main()
