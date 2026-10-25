#!/usr/bin/env python3
"""Copy the app's open word data into the web version.

    python3 scripts/build_web.py            # fills web/data for local testing
    python3 scripts/build_web.py _site      # writes a deployable copy of the web app to _site

Then serve the folder, e.g. `python3 -m http.server -d web 8000`, and open http://localhost:8000.

Only the dictionary, Kelly levels and the open word lists in Resources/Decks are copied, never
Resources/Private (personal lists such as Rivstart must not end up on a public website).
"""
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "SvenskaVocab" / "Resources"
WEB = ROOT / "web"
FILES = ["core_vocabulary.tsv", "folkets_sv_en.tsv", "kelly_levels.tsv", "language_hints.tsv"]


def copy_data(data: Path) -> None:
    if data.exists():
        shutil.rmtree(data)
    (data / "decks").mkdir(parents=True)
    for name in FILES:
        shutil.copy2(RESOURCES / name, data / name)
    decks = sorted(p.name for p in (RESOURCES / "Decks").glob("deck_*.tsv"))
    for name in decks:
        shutil.copy2(RESOURCES / "Decks" / name, data / "decks" / name)
    (data / "decks.json").write_text(json.dumps(decks, indent=0) + "\n")
    print(f"{len(FILES)} dictionary files and {len(decks)} word lists → {data.relative_to(ROOT)}")


def main() -> None:
    if len(sys.argv) > 1:
        out = (ROOT / sys.argv[1]).resolve()
        if out == WEB or out == ROOT:
            sys.exit("Choose an output folder other than web/ or the repository root.")
        if out.exists():
            shutil.rmtree(out)
        shutil.copytree(WEB, out, ignore=shutil.ignore_patterns("data", ".DS_Store"))
        copy_data(out / "data")
    else:
        copy_data(WEB / "data")


if __name__ == "__main__":
    main()
