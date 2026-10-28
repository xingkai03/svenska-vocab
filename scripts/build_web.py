#!/usr/bin/env python3
"""Copy the app's open word data into the web version.

    python3 scripts/build_web.py            # fills web/data for local testing
    python3 scripts/build_web.py _site      # writes a deployable copy of the web app to _site, with offline support

Then serve the folder, e.g. `python3 -m http.server -d web 8000`, and open http://localhost:8000.

Only the dictionary, Kelly levels and the open word lists in Resources/Decks are copied, never
Resources/Private (personal lists such as Rivstart must not end up on a public website).
"""
import hashlib
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


def stamp_service_worker(site: Path) -> None:
    """Lists the site's files in sw.js for offline use, with a version that changes whenever any of them does.

    SVT clip lists (svt/, about 5 MB) are left out; the service worker keeps the ones that get opened.
    """
    files = sorted(
        p.relative_to(site).as_posix() for p in site.rglob("*")
        if p.is_file() and p.name != "sw.js" and not p.relative_to(site).as_posix().startswith("svt/")
    )
    digest = hashlib.sha256()
    for name in files:
        digest.update(name.encode() + b"\0" + (site / name).read_bytes())
    version = digest.hexdigest()[:12]
    sw = site / "sw.js"
    text = sw.read_text()
    for old, new in [('const VERSION = "dev";', f'const VERSION = "{version}";'),
                     ("const FILES = [];", f"const FILES = {json.dumps(['./'] + files)};")]:
        if old not in text:
            sys.exit(f"sw.js no longer contains {old!r}; update stamp_service_worker.")
        text = text.replace(old, new)
    sw.write_text(text)
    print(f"Service worker version {version}: {len(files)} files cached for offline use")


def main() -> None:
    if len(sys.argv) > 1:
        out = (ROOT / sys.argv[1]).resolve()
        if out == WEB or out == ROOT:
            sys.exit("Choose an output folder other than web/ or the repository root.")
        if out.exists():
            shutil.rmtree(out)
        shutil.copytree(WEB, out, ignore=shutil.ignore_patterns("data", ".DS_Store"))
        copy_data(out / "data")
        stamp_service_worker(out)
    else:
        copy_data(WEB / "data")


if __name__ == "__main__":
    main()
