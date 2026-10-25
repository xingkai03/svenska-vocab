#!/usr/bin/env python3
"""Build the German and French memory hints (look-alike words) for the Swedish dictionary.

A hint pairs a Swedish word with a German or French word that means the same and looks or sounds
alike ("fönster" / "Fenster", "trottoar" / "trottoir"), or that the Swedish word was borrowed from.
Learners who already know German or French can switch them on in Settings.

Sources (both from Wiktionary, CC BY-SA):

  - WikDict Swedish → German and Swedish → French translations
        curl -LO https://download.wikdict.com/dictionaries/sqlite/2/sv-de.sqlite3
        curl -LO https://download.wikdict.com/dictionaries/sqlite/2/sv-fr.sqlite3
  - Kaikki.org's extract of the English Wiktionary's Swedish entries, for etymologies
        curl -LO https://kaikki.org/dictionary/Swedish/kaikki.org-dictionary-Swedish.jsonl

Run from the repository root with the folder holding the three files:

    python3 scripts/build_language_hints.py path/to/folder

Writes SvenskaVocab/Resources/language_hints.tsv: word, pos, language (de/fr), foreign word,
kind ("same": spelled the same, "similar": looks alike,
"from": the Swedish word was borrowed from it). Only words in the app's dictionary are kept.
"""

import json
import re
import sqlite3
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "SvenskaVocab" / "Resources"
OUTPUT = RESOURCES / "language_hints.tsv"

WIKDICT_POS = {
    "Substantiv": "noun", "Verb": "verb", "Adjektiv": "adjective", "Adverb": "adverb",
    "Pronomen": "pronoun", "Preposition": "preposition", "Konjunktion": "conjunction",
    "Räkneord": "numeral", "Interjektion": "interjection", "Fras": "phrase",
}
KAIKKI_POS = {
    "noun": "noun", "name": "noun", "verb": "verb", "adj": "adjective", "adv": "adverb",
    "pron": "pronoun", "prep": "preposition", "conj": "conjunction", "num": "numeral",
    "intj": "interjection", "phrase": "phrase",
}
LANGUAGES = {"de": "German", "fr": "French"}
# Below this similarity two translations are not alike enough to help memory.
THRESHOLD = 0.6


def strip_accents(s):
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")


def skeleton(word, lang, pos):
    """A rough phonetic spelling, so cognates spelled the Swedish, German or French way line up."""
    w = word.lower().strip()
    if lang == "sv":
        w = w.replace("å", "o").replace("ä", "e").replace("ö", "8")
        w = re.sub(r"s(k|t)?j|sch|ch", "S", w)
        w = re.sub(r"(t|k)j", "C", w)
        w = re.sub(r"tion", "Son", w)
        if pos == "verb":
            w = re.sub(r"(?<=.{2})a$", "", w)
    elif lang == "de":
        w = w.replace("ß", "ss").replace("ä", "e").replace("ö", "8").replace("ü", "y")
        w = w.replace("sch", "S").replace("tsch", "C").replace("ch", "k")
        w = w.replace("ei", "e").replace("ie", "i").replace("eu", "8").replace("au", "o")
        w = w.replace("pf", "p").replace("tz", "s").replace("z", "s").replace("v", "f").replace("w", "v")
        w = re.sub(r"^s(p|t)", r"s\1", w)
        w = re.sub(r"tion", "Son", w)
        if pos == "verb":
            w = re.sub(r"(?<=.{2})e?n$", "", w)
    elif lang == "fr":
        w = strip_accents(w.replace("œ", "oe"))
        w = re.sub(r"tion", "Son", w)
        w = w.replace("eau", "o").replace("eu", "8").replace("oe", "8").replace("ou", "u")
        w = w.replace("qu", "k").replace("ch", "S").replace("ph", "f").replace("gn", "nj")
        w = re.sub(r"c(?=[eiy])", "s", w).replace("c", "k")
        w = re.sub(r"g(?=[eiy])", "S", w)
        w = w.replace("j", "S")
        if pos == "verb":
            w = re.sub(r"(?<=.{2})(er|ir|re)$", "", w)
        w = re.sub(r"(?<=.{2})(e|es|s|t|x)$", "", w)
    w = w.replace("ck", "k").replace("c", "k").replace("q", "k").replace("x", "ks")
    w = w.replace("th", "t").replace("ph", "f").replace("w", "v").replace("z", "s").replace("dt", "t")
    w = re.sub(r"(.)\1+", r"\1", w)
    w = re.sub(r"(?<=.{3})[aeo]$", "", w)  # sv -a / -e, de -e, endings that differ between the languages
    return re.sub(r"[^a-zA-Z8]", "", w)


def distance(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def similarity(sv, other, lang, pos):
    a, b = skeleton(sv, "sv", pos), skeleton(other, lang, pos)
    if min(len(a), len(b)) < 2:
        return 0.0
    return 1 - distance(a, b) / max(len(a), len(b))


def dictionary_words():
    """word -> set of parts of speech in the app's bundled dictionary."""
    words = {}
    for name in ("core_vocabulary.tsv", "folkets_sv_en.tsv"):
        for line in (RESOURCES / name).read_text(encoding="utf-8").splitlines():
            if line.startswith("#"):
                continue
            c = line.split("\t")
            if len(c) >= 2 and c[0]:
                words.setdefault(c[0].lower(), set()).add(c[1])
    return words


def translations(path):
    """(sv word, pos) -> foreign words, best first, from a WikDict SQLite file."""
    senses = {}
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    rows = db.execute("SELECT lexentry, written_rep, trans_list, score, importance FROM translation "
                      "WHERE is_good ORDER BY score DESC")
    for lexentry, word, trans_list, score, importance in rows:
        parts = (lexentry or "").split("__")
        pos = WIKDICT_POS.get(parts[1], "") if len(parts) > 1 else ""
        senses.setdefault((word.lower(), pos), []).append((score or 0, importance or 0, trans_list))
    result = {}
    for key, rows in senses.items():
        # Only the main senses: "barn" is also a unit in physics (German "Barn"), "kaka" a parrot.
        top_score = max(r[0] for r in rows)
        top_importance = max(r[1] for r in rows)
        options = result.setdefault(key, [])
        for score, importance, trans_list in rows:
            if score < 0.7 * top_score or importance < 0.3 * top_importance:
                continue
            for t in trans_list.split(" | "):
                t = t.strip()
                if t and t not in options:
                    options.append(t)
    return result


def borrowings(path):
    """(sv word, pos) -> (lang, source word) where Wiktionary says the word came from French or German."""
    result = {}
    for line in Path(path).open(encoding="utf-8"):
        d = json.loads(line)
        pos = KAIKKI_POS.get(d.get("pos"), "")
        # "t" is a trimmed copy holding only the etymology templates.
        for t in d.get("t") or d.get("etymology_templates") or []:
            if t["name"] not in ("bor", "bor+", "der", "der+", "lbor", "inh", "inh+"):
                continue
            # Only the nearest source counts: "from Middle Low German …, from Latin …" is not a French hint.
            lang, source = t["args"].get("2"), t["args"].get("3", "")
            if lang in LANGUAGES and source and not source.startswith("*"):
                result[(d["word"].lower(), pos)] = (lang, source)
            break
    return result


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    folder = Path(sys.argv[1])
    words = dictionary_words()
    borrowed = borrowings(folder / "sv_etym.jsonl" if (folder / "sv_etym.jsonl").exists()
                          else folder / "kaikki.org-dictionary-Swedish.jsonl")
    hints = {}  # (word, pos, lang) -> (foreign, kind, score)

    meanings = {lang: translations(folder / f"sv-{lang}.sqlite3") for lang in LANGUAGES}
    for lang in LANGUAGES:
        for (word, pos), options in meanings[lang].items():
            if pos not in words.get(word, ()) or " " in word or len(word) < 3:
                continue
            best = None
            for foreign in options[:6]:
                if " " in foreign:
                    continue
                score = similarity(word, foreign, lang, pos)
                if foreign.lower() == word:
                    score = 1.01
                if score >= THRESHOLD and (best is None or score > best[1]):
                    best = (foreign, score)
            if best:
                kind = "same" if best[1] > 1 else "similar"
                hints[(word, pos, lang)] = (best[0], kind, best[1])

    for (word, pos), (lang, source) in borrowed.items():
        if pos not in words.get(word, ()):
            continue
        # Keep a look-alike translation. Otherwise name the source word, but only if it still means the same:
        # "snäll" (kind) comes from German "schnell" (fast), which would mislead.
        if (word, pos, lang) in hints or similarity(word, source, lang, pos) < 0.45:
            continue
        options = meanings[lang].get((word, pos), [])
        if source.lower() not in (o.lower() for o in options):
            continue
        hints[(word, pos, lang)] = (source, "from", 0.0)

    lines = ["# Source: Wiktionary, via WikDict and kaikki.org, CC BY-SA 4.0. Built by scripts/build_language_hints.py"]
    for (word, pos, lang), (foreign, kind, _) in sorted(hints.items()):
        lines.append("\t".join([word, pos, lang, foreign, kind]))
    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    counts = {lang: sum(1 for k in hints if k[2] == lang) for lang in LANGUAGES}
    print(f"Wrote {len(hints)} hints to {OUTPUT.relative_to(ROOT)}: {counts}")


if __name__ == "__main__":
    main()
