#!/usr/bin/env python3
"""Build CEFR word lists (A1–C2) from the Swedish Kelly list.

Download the source first (CC BY 4.0, Språkbanken, University of Gothenburg):

    curl -LO https://svn.spraakbanken.gu.se/sb-arkiv/pub/lmf/kelly/kelly.xml

then run from the repository root, after build_folkets.py:

    python3 scripts/build_kelly.py kelly.xml

Writes SvenskaVocab/Resources/kelly_levels.tsv (word, pos, level, rank), keeping only
lemmas that exist in core_vocabulary.tsv or folkets_sv_en.tsv. Rank is by frequency
(words per million, highest first); the hand-added words, whose WPM is a placeholder
1 000 000, come last. Word and part of speech
are written as they appear in the dictionary, so the app can match them on its entry id.
"""

import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "SvenskaVocab" / "Resources"
DICTIONARIES = [RESOURCES / "core_vocabulary.tsv", RESOURCES / "folkets_sv_en.tsv"]
OUTPUT = RESOURCES / "kelly_levels.tsv"

LEVELS = {"1": "A1", "2": "A2", "3": "B1", "4": "B2", "5": "C1", "6": "C2"}

CLASSES = {
    "noun": "noun", "noun-en": "noun", "noun-ett": "noun", "noun-en/-ett": "noun", "proper name": "noun",
    "verb": "verb", "aux verb": "verb",
    "adjective": "adjective", "particip": "adjective",
    "adverb": "adverb",
    "pronoun": "pronoun", "det": "pronoun",
    "prep": "preposition",
    "conj": "conjunction", "subj": "conjunction",
    "numeral": "numeral",
    "interj": "interjection",
}


def dictionary():
    """(lowercased word, pos) -> (word, pos), and lowercased word -> first (word, pos)."""
    by_id, by_word = {}, {}
    for path in DICTIONARIES:
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line or line.startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) < 2:
                continue
            key = (cols[0].lower(), cols[1])
            by_id.setdefault(key, (cols[0], cols[1]))
            by_word.setdefault(cols[0].lower(), (cols[0], cols[1]))
    return by_id, by_word


def kelly_entries(source):
    for entry in ET.parse(source).getroot().iter("LexicalEntry"):
        feats = {f.get("att"): f.get("val") for f in entry.find("Lemma/FormRepresentation").iter("feat")}
        level = LEVELS.get(feats.get("cefr", ""))
        word = " ".join((feats.get("writtenForm") or "").split())
        if level and word:
            pos = CLASSES.get(feats.get("kellyPartOfSpeech", ""), "phrase")
            manual = feats.get("source") == "manual"
            wpm = float((feats.get("wpm") or "0").replace(",", "."))
            yield word, pos, level, (manual, -wpm, int(feats["kellyID"]))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    by_id, by_word = dictionary()
    rows, assigned = [], set()
    total, matched = Counter(), Counter()
    for rank, (word, pos, level, _) in enumerate(sorted(kelly_entries(sys.argv[1]), key=lambda e: e[3]), 1):
        total[level] += 1
        target = by_id.get((word.lower(), pos)) or by_word.get(word.lower())
        if target is None or target in assigned:
            continue
        assigned.add(target)
        matched[level] += 1
        rows.append((target[0], target[1], level, str(rank)))
    with OUTPUT.open("w", encoding="utf-8", newline="\n") as out:
        out.write("# Source: Swedish Kelly list, Språkbanken, University of Gothenburg, CC BY 4.0\n")
        for row in rows:
            out.write("\t".join(row) + "\n")
    for level in LEVELS.values():
        print(f"{level}: {matched[level]} of {total[level]}")
    print(f"{len(rows)} of {sum(total.values())} lemmas matched → {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
