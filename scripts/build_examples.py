#!/usr/bin/env python3
"""Fill in example sentences for dictionary words that have none.

Folkets lexikon only has an example for about one word in five. This script looks for one in
openly licensed sources and writes it into the empty example columns of folkets_sv_en.tsv:

  1. Wiktionary usage examples for the same word and part of speech, from kaikki.org's extract
     of the English Wiktionary (CC BY-SA 4.0). These were written for the word's meaning.
        curl -LO https://kaikki.org/dictionary/Swedish/kaikki.org-dictionary-Swedish.jsonl
  2. Otherwise a sentence that uses the word or one of its inflected forms, from Tatoeba
     (CC BY 2.0 FR), Wiktionary's examples for other words, or the examples the dictionary
     already has for other words:
        curl -LO https://downloads.tatoeba.org/exports/per_language/swe/swe_sentences.tsv.bz2
        curl -LO https://downloads.tatoeba.org/exports/per_language/eng/eng_sentences.tsv.bz2
        curl -LO https://downloads.tatoeba.org/exports/per_language/swe/swe-eng_links.tsv.bz2
     (bunzip2 them into a tatoeba/ subfolder). A spelling shared by two dictionary words
     ("springa" the verb and "springa" the noun) is left out, since the sentence could mean either.

Run from the repository root, after scripts/build_folkets.py, with the folder holding the files:

    python3 scripts/build_examples.py path/to/folder

Only empty example columns are filled, so running it again changes nothing.
"""

import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "SvenskaVocab" / "Resources"
CORE = RESOURCES / "core_vocabulary.tsv"
FOLKETS = RESOURCES / "folkets_sv_en.tsv"
NOTE = "# Extra examples: Wiktionary (kaikki.org), CC BY-SA 4.0; Tatoeba, CC BY 2.0 FR"

KAIKKI_POS = {
    "noun": "noun", "name": "noun", "verb": "verb", "adj": "adjective", "adv": "adverb",
    "pron": "pronoun", "prep": "preposition", "conj": "conjunction", "num": "numeral",
    "intj": "interjection", "phrase": "phrase", "prep_phrase": "phrase", "proverb": "phrase",
}

TOKEN = re.compile(r"\w+", re.UNICODE)
MIN_WORDS, MAX_WORDS, IDEAL_WORDS = 3, 14, 7


def tokens(text):
    return TOKEN.findall(text.lower())


def clean(text):
    return " ".join((text or "").replace("\t", " ").split())


def read_rows(path):
    header, rows = [], []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("#"):
            header.append(line)
        elif line:
            cols = line.split("\t")
            rows.append(cols + [""] * (7 - len(cols)))
    return header, rows


def good_sentence(sv, en):
    return bool(en) and MIN_WORDS <= len(tokens(sv)) <= MAX_WORDS


def score(sv):
    # Closest to a comfortable length wins; ties go to the shorter, then alphabetical, so runs are stable.
    n = len(tokens(sv))
    return (abs(n - IDEAL_WORDS), len(sv), sv)


def pick(a, b):
    return a if b is None or (score(a[0]), a[1]) < (score(b[0]), b[1]) else b


def wiktionary_examples(path, wanted):
    """(word, pos) -> best (sv, en) usage example from the word's own Wiktionary senses, and a
    list of all usable examples (for other words they happen to use).

    Folkets has no word class for many words ("phrase" in the app), so those are also found
    under (word, None) with whatever word class Wiktionary gives.
    """
    found, everything = {}, []
    with path.open(encoding="utf-8") as f:
        for line in f:
            if '"examples"' not in line:
                continue
            entry = json.loads(line)
            if entry.get("lang_code") != "sv":
                continue
            word = entry.get("word", "").lower()
            keys = [k for k in ((word, KAIKKI_POS.get(entry.get("pos"))), (word, None)) if k in wanted]
            for sense in entry.get("senses", []):
                for ex in sense.get("examples", []):
                    if ex.get("type") == "quotation":
                        continue  # dated literary quotes; usage examples read better
                    sv = clean(ex.get("text"))
                    # Drop editors' notes such as "[a]" or "[See vara for why…]" from the translation.
                    en = clean(re.sub(r"\[[^\]]*\]", "", ex.get("english") or ex.get("translation") or ""))
                    if "[" in sv or re.search(r"\([^)]{25,}\)", en) or not good_sentence(sv, en):
                        continue
                    everything.append((sv, en))
                    for key in keys:
                        found[key] = pick((sv, en), found.get(key))
    return found, everything


def tatoeba_pairs(folder):
    folder = folder / "tatoeba"
    if not folder.is_dir():
        return []
    swe = {}
    for line in (folder / "swe_sentences.tsv").open(encoding="utf-8"):
        cols = line.rstrip("\n").split("\t")
        if len(cols) >= 3:
            swe[cols[0]] = clean(cols[2])
    links = defaultdict(list)
    for line in (folder / "swe-eng_links.tsv").open(encoding="utf-8"):
        cols = line.rstrip("\n").split("\t")
        if len(cols) >= 2 and cols[0] in swe:
            links[cols[1]].append(cols[0])
    english = {}
    for line in (folder / "eng_sentences.tsv").open(encoding="utf-8"):
        cols = line.rstrip("\n").split("\t", 2)
        if len(cols) >= 3 and cols[0] in links:
            for sv_id in links[cols[0]]:
                # Lowest-numbered English translation, i.e. usually the original one.
                if sv_id not in english or int(cols[0]) < english[sv_id][0]:
                    english[sv_id] = (int(cols[0]), clean(cols[2]))
    return [(swe[i], en) for i, (_, en) in english.items()]


def spellings(row):
    word, forms = row[0].lower(), row[3].lower()
    out = {word}
    if " " not in word:
        out.update(f.strip().rstrip("!") for f in re.split(r"[,;]", forms) if f.strip())
    return {s for s in out if s and "~" not in s}


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    folder = Path(sys.argv[1])
    _, core = read_rows(CORE)
    header, rows = read_rows(FOLKETS)
    header = [h for h in header if not h.startswith("# Extra examples")]
    before = sum(1 for r in rows if r[5])
    missing = [r for r in rows if not r[5]]

    # Which dictionary entries each spelling (one word, or a phrase as a token tuple) can belong to.
    owners = defaultdict(set)
    for r in core + rows:
        for s in spellings(r):
            owners[tuple(tokens(s))].add((r[0].lower(), r[1]))

    # 1. Wiktionary usage examples for the exact word and part of speech.
    stats = defaultdict(int)
    kaikki = folder / "kaikki.org-dictionary-Swedish.jsonl"
    wanted = {(r[0].lower(), r[1]) for r in missing}
    wanted |= {(r[0].lower(), None) for r in missing
               if r[1] == "phrase" and len(owners[tuple(tokens(r[0]))]) == 1}
    wiki, wiki_all = wiktionary_examples(kaikki, wanted) if kaikki.exists() else ({}, [])
    for r in missing:
        found = wiki.get((r[0].lower(), r[1])) or wiki.get((r[0].lower(), None))
        if found:
            r[5], r[6] = found
            stats["Wiktionary"] += 1

    # 2. Sentences that use the word, from Tatoeba and from the dictionary's own examples
    #    (including those just added, which is why this repeats until nothing changes:
    #    a second run of the script then has nothing left to add).
    corpus = [(s, e, "Tatoeba") for s, e in tatoeba_pairs(folder)]
    corpus += [(s, e, "Wiktionary") for s, e in wiki_all]
    corpus += [(clean(r[5]), clean(r[6]), "Folkets/core") for r in core + rows if r[5] and r[6]]
    names = names_in(sv for sv, _, source in corpus if source == "Tatoeba")
    while fill_from_corpus(corpus, owners, names, missing, stats):
        known = {sv for sv, _, _ in corpus}
        corpus += [(r[5], r[6], "Folkets/core") for r in rows if r[5] and r[6] and r[5] not in known]

    after = sum(1 for r in rows if r[5])
    with FOLKETS.open("w", encoding="utf-8", newline="\n") as out:
        for h in header + [NOTE]:
            out.write(h + "\n")
        for r in rows:
            out.write("\t".join(r[:7]) + "\n")
    print(f"Examples: {before} → {after} of {len(rows)} words "
          f"({before / len(rows):.0%} → {after / len(rows):.0%})")
    for source, n in sorted(stats.items(), key=lambda kv: -kv[1]):
        print(f"  {source}: {n}")


def names_in(sentences):
    """Words written with a capital letter inside sentences more often than not are names
    ("Nick", "Kanton"), so a sentence using them says nothing about "nick" or "kanton"."""
    capital, lower = defaultdict(int), defaultdict(int)
    for sv in sentences:
        for t in TOKEN.findall(sv)[1:]:
            (capital if t[0].isupper() else lower)[t.lower()] += 1
    return {t for t in capital if capital[t] > lower[t]}


def fill_from_corpus(corpus, owners, names, missing, stats):
    """Give each word still missing an example the best sentence that uses it. Returns how many."""
    best = {}
    longest = max(len(k) for k in owners)
    for sv, en, source in corpus:
        if not good_sentence(sv, en):
            continue
        toks = tokens(sv)
        seen = set()
        for i in range(len(toks)):
            for n in range(1, min(longest, len(toks) - i) + 1):
                entries = owners.get(tuple(toks[i:i + n]))
                if not entries or len(entries) != 1 or (n == 1 and toks[i] in names):
                    continue
                key = next(iter(entries))
                if key in seen:
                    continue
                seen.add(key)
                best[key] = pick((sv, en, source), best.get(key))
    filled = 0
    for r in missing:
        key = (r[0].lower(), r[1])
        if not r[5] and key in best:
            r[5], r[6], source = best[key]
            stats[source] += 1
            filled += 1
    return filled


if __name__ == "__main__":
    main()
