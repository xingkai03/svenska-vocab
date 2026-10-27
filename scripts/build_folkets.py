#!/usr/bin/env python3
"""Convert Folkets lexikon (Swedish → English) into the app's bundled TSV format.

Download the source first (CC BY-SA 2.5, © KTH):

    curl -LO https://folkets-lexikon.csc.kth.se/folkets/folkets_sv_en_public.xml

then run from the repository root:

    python3 scripts/build_folkets.py folkets_sv_en_public.xml

Writes SvenskaVocab/Resources/folkets_sv_en.tsv with the same seven columns as
core_vocabulary.tsv (word, pos, gender, forms, translation, example, example_en),
leaving out words the curated core vocabulary already covers. Run scripts/build_examples.py
afterwards to fill in example sentences for words Folkets has none for.
"""

import html
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "SvenskaVocab" / "Resources"
CORE = RESOURCES / "core_vocabulary.tsv"
OUTPUT = RESOURCES / "folkets_sv_en.tsv"

CLASSES = {
    "nn": "noun", "pm": "noun",
    "vb": "verb",
    "jj": "adjective", "pc": "adjective",
    "ab": "adverb",
    "pn": "pronoun", "hp": "pronoun",
    "pp": "preposition",
    "kn": "conjunction", "sn": "conjunction",
    "rg": "numeral", "ro": "numeral",
    "in": "interjection",
}


def clean(value):
    # Some values are double-escaped in the source ("&#39;" inside the attribute), hence unescape.
    return " ".join(html.unescape(value or "").replace("|", "").split())


def core_ids():
    ids = set()
    for line in CORE.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        cols = line.split("\t")
        if len(cols) >= 2:
            ids.add((cols[0].lower(), cols[1]))
    return ids


def gender(pos, forms):
    if pos != "noun" or not forms:
        return ""
    first = forms[0].lower()
    if first.endswith("t"):
        return "ett"
    if first.endswith("n"):
        return "en"
    return ""


def convert(source):
    skip = core_ids()
    rows = {}  # (lowercased word, pos) -> row; dicts keep first-seen order
    for _, word in ET.iterparse(source, events=("end",)):
        if word.tag != "word":
            continue
        if word.get("lang") == "sv":
            add_entry(word, rows, skip)
        word.clear()
    return list(rows.values())


def add_entry(word, rows, skip):
    value = clean(word.get("value"))
    pos = CLASSES.get(word.get("class", ""), "phrase")
    # Direct children only: translations nested in idioms, definitions, compounds etc. are not the word's meaning.
    translations = [clean(t.get("value")) for t in word.findall("translation")]
    translations = [t for t in translations if t]
    if not value or not translations:
        return
    key = (value.lower(), pos)
    if key in skip:
        return
    if key in rows:
        existing = rows[key]["translation"]
        for t in translations:
            if t not in existing:
                existing.append(t)
        return
    forms = [clean(i.get("value")) for i in word.findall("paradigm/inflection")]
    forms = [f for f in forms if f]
    example, example_en = "", ""
    first = word.find("example")
    if first is not None:
        example = clean(first.get("value"))
        t = first.find("translation")
        example_en = clean(t.get("value")) if t is not None else ""
    rows[key] = {
        "word": value, "pos": pos, "gender": gender(pos, forms), "forms": ", ".join(forms),
        "translation": translations, "example": example, "example_en": example_en,
    }


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    rows = convert(sys.argv[1])
    with OUTPUT.open("w", encoding="utf-8", newline="\n") as out:
        out.write("# Source: Folkets lexikon, KTH, CC BY-SA 2.5\n")
        for r in rows:
            cols = [r["word"], r["pos"], r["gender"], r["forms"], "; ".join(r["translation"]),
                    r["example"], r["example_en"]]
            out.write("\t".join(cols) + "\n")
    print(f"{len(rows)} entries, {OUTPUT.stat().st_size / 1024:.0f} KB → {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
