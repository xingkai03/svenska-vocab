# Svenska – Swedish vocabulary builder for iOS

A compact SwiftUI app for building Swedish vocabulary, with a full offline Swedish–English dictionary, spaced repetition and a daily check-in streak.

## Features

- **Lookup** – search in Swedish or English, with or without å/ä/ö ("bat" finds "båt"). About 37 000 words work offline: a curated core vocabulary of ~700 common words plus the whole of [Folkets lexikon](https://folkets-lexikon.csc.kth.se/folkets/) (KTH). Anything else is looked up in Folkets lexikon online. Recent searches are remembered.
- **Word details** – article (en/ett), inflected forms, translation, example sentence with translation, personal notes.
- **Pronunciation** – every word, form and example sentence can be spoken with the system's Swedish (sv-SE) voice, at normal or slow speed. Optional auto-pronounce.
- **Collection** – save words, add your own, edit, favourite, filter (due, learning, mastered, favourites), sort (recent, A–Z, next review, weakest memory), swipe to delete. Export as CSV.
- **Learn new words** – step through the core vocabulary in frequency order, or a CEFR word list (A1, A2, B1, B2, C1, C2) from the Swedish Kelly list, with progress per list: "Learn" adds a word, "I know it" skips it.
- **Open word lists** – in Learn new words, alongside Core and the Kelly CEFR levels:
  - **Coursebook A1–C1** – vocabulary of Swedish L2 coursebooks (SVALex), each word at the level where it first appears.
  - **Spoken top 1000 / 1001–3000** – the most frequent words in Swedish film and TV subtitles, mapped to dictionary headwords.
  - **Academic words** – 655 words typical of Swedish academic texts (Akademisk ordlista), ranked, in chapters of 100.
  - **Expressions** – multi-word expressions ("bland annat", "gifta sig", "känna igen") graded A1–C1 (Swe-MWELex), the ones the dictionary can translate.
  - **Topics** – 16 everyday themes (greetings, family, body & health, food, home, clothes, weather, time, numbers, travel, city, work & school, shopping, nature, feelings, hobbies), 30–50 words each.
  The picker shows learned / total for every list.
- **Word lists** – import your own lists (Settings › Word lists › Import word list…, from Files on the iPhone) as .tsv, .csv or .txt with Swedish, English and optionally part of speech, example and chapter. They appear in Learn new words with a chapter filter; missing grammar and examples are filled in from the dictionary.
- **CEFR levels** – about 7 500 words carry a level badge (A1–C2) in search results, word details and your collection, which you can filter by level.
- **Spaced repetition** – an SM-2 scheduler with Again / Hard / Good / Easy grading and interval previews. Forgotten words come back in the same session.
- **Forgetting curve** – each word has a modelled recall probability R(t) = 0.9^(t / interval), shown as a memory-strength bar and a curve on its detail page.
- **Review modes** – flashcards, English → Swedish, multiple choice, listening, and spelling (with å/ä/ö keys and "almost right" detection). When nothing is due you can practise without changing the schedule.
- **Daily check-in** – set a daily goal (reviews + new words). Once you reach it you can check in. Streak counter, a week strip, and a daily reminder notification.
- **Account & cloud sync** – optional sign-in (email and password, via [Supabase](https://supabase.com)). Your saved words with their review state, review history, check-ins, settings and imported word lists are backed up and kept in sync across devices; the dictionary and built-in lists stay on the device. The app works fully offline and syncs when it opens, closes and every few minutes. Words already on the device are merged into the account on first sign-in.
- **Summary** – words, mastered, current and best streak, total reviews, 30-day accuracy, a 14-day activity chart, mastery breakdown, a forgetting curve for your whole collection, a 7-day review forecast, a check-in calendar, and your trickiest words.

## Requirements

- Xcode 16 or later
- iOS 17 or later (SwiftData, Swift Charts)

## Running

1. Open `SvenskaVocab.xcodeproj` in Xcode.
2. Select the **SvenskaVocab** target › Signing & Capabilities and choose your team. If the bundle ID is taken, change `com.xingkai03.SvenskaVocab`.
3. Run on a simulator or a device.

### Cloud sync (optional)

Without configuration the app is offline-only. To turn on accounts:

1. Create a free project at [supabase.com](https://supabase.com).
2. In the dashboard › SQL Editor, run [`supabase/schema.sql`](supabase/schema.sql). It creates the tables with row-level security, so each account can only read and write its own rows.
3. Copy `supabase/Supabase.example.plist` to `SvenskaVocab/Config/Supabase.plist` and fill in the project URL and the **anon / publishable** key from Project Settings › API. `SvenskaVocab/Config/` is git-ignored. Never put the service_role / secret key in the app.
4. Optional: under Authentication › Sign In / Providers › Email, turn off "Confirm email" to skip the confirmation email when creating an account.

For the best pronunciation, download an enhanced Swedish voice on the device: Settings › Accessibility › Spoken Content › Voices › Swedish.

The project uses Xcode 16's folder-synchronised groups, so new files you add under `SvenskaVocab/` are picked up automatically. On older Xcode, regenerate the project with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.

### Web version

`web/` is a browser version with the same tabs and features (lookup, Learn new words, reviews in all five modes, check-ins, summary, settings, imported lists) and sv-SE pronunciation through the browser's speech voices. It signs in to the same Supabase accounts and syncs the same tables with the same merge rules as the app, so you can learn on the web and on the iPhone with one account. Without an account it keeps everything in the browser (IndexedDB).

On a computer everything works from the keyboard: T / L / W / S switch tabs, `/` searches, J / K or the arrow keys move through lists, Space and 1–4 answer reviews, ← / → skip or learn new words, P pronounces, Esc goes back, and `?` lists every shortcut for the current screen. In spelling, `[`, `'` and `;` type å, ä and ö (where they sit on a Swedish keyboard).

It is plain JavaScript modules with no build step (Preact + htm are vendored in `web/vendor/`). To run it locally:

```
python3 scripts/build_web.py           # copies the dictionary and open word lists into web/data
python3 -m http.server -d web 8000     # then open http://localhost:8000
```

`web/config.js` holds the Supabase URL and publishable key (public by design; the tables are protected by row-level security). `.github/workflows/web.yml` publishes the site to GitHub Pages on every push to `main` that touches it: in the repository settings › Pages, set Source to "GitHub Actions". The build only copies `Resources/Decks`, never `Resources/Private`. For confirmation emails to open the web version, add its URL under Supabase › Authentication › URL Configuration.

## Project layout

```
SvenskaVocab/
  App/            App entry point and tab bar
  Models/         SwiftData models (SavedWord, ReviewLog, CheckIn) and DictionaryEntry
  Services/       Dictionary (offline + Folkets lexikon), speech, scheduler, settings, reminders
    Cloud/        Supabase auth client and sync
  Views/          Today, Lookup, Collection, Review, Summary
  Resources/      core_vocabulary.tsv (curated), folkets_sv_en.tsv and kelly_levels.tsv (generated)
    Decks/        open word lists (deck_*.tsv)
    Private/      your personal lists (git-ignored)
scripts/          build_folkets.py, build_kelly.py, build_open_decks.py, build_web.py
web/              browser version (see Web version above)
```

### Extending the built-in vocabulary

`Resources/core_vocabulary.tsv` is tab-separated, one word per line, roughly in frequency order:

```
word  part_of_speech  gender(en/ett)  forms  translation  example  example_translation
```

Part of speech is one of `noun verb adjective adverb pronoun preposition conjunction numeral interjection phrase`. Lines starting with `#` are ignored.

Word of the day, "Learn new words" and quiz distractors use only this curated list; search covers it and the Folkets lexikon file.

### Updating the bundled Folkets lexikon

`Resources/folkets_sv_en.tsv` uses the same columns and is generated from the Folkets XML export by `scripts/build_folkets.py`, which skips words already in `core_vocabulary.tsv`:

```
curl -LO https://folkets-lexikon.csc.kth.se/folkets/folkets_sv_en_public.xml
python3 scripts/build_folkets.py folkets_sv_en_public.xml
```

Don't commit the XML. Rerun the script after editing `core_vocabulary.tsv` so the two files don't overlap.

### Personal word lists

Any `deck_*.tsv` file in the app bundle shows up as a word list in Learn new words. Format: optional `# deck: Display name` and `# group: Section` lines (lists without a group appear under "My lists"), then rows with the seven columns above plus an optional 8th `chapter` column (e.g. `Kapitel 3`). Only the word is required; empty columns are filled in from the dictionary entry with the same word.

Put personal lists, such as vocabulary from a textbook you own, in `SvenskaVocab/Resources/Private/`. That folder is in `.gitignore`: files there are bundled into your local builds but never committed. To get the same lists onto an iPhone, run the app from Xcode on the device, or AirDrop the .tsv to the phone and use Import word list.

### Updating the open word lists

The Coursebook, Spoken, Academic and Expressions lists in `Resources/Decks/` are generated by `scripts/build_open_decks.py` (run it after the two scripts above):

```
curl -LO https://cental.uclouvain.be/cefrlex/static/resources/sv/SVALex_v2.tsv
curl -LO https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/sv/sv_50k.txt
curl -LO https://svn.spraakbanken.gu.se/sb-arkiv/pub/lmf/ao/ao.xml
curl -LO https://spraakbanken.gu.se/resurser/data/swe-mwelex.xlsx
python3 scripts/build_open_decks.py SVALex_v2.tsv sv_50k.txt ao.xml swe-mwelex.xlsx
```

The topic lists (`deck_topic_*.tsv`) are written by hand. They hold just word and part of speech, and the app fills in the rest from the dictionary.

### Updating the CEFR levels

`Resources/kelly_levels.tsv` (word, part of speech, level, frequency rank) is generated from the Swedish Kelly list by `scripts/build_kelly.py`. It keeps only words found in the two dictionary files, so run it after `build_folkets.py`:

```
curl -LO https://svn.spraakbanken.gu.se/sb-arkiv/pub/lmf/kelly/kelly.xml
python3 scripts/build_kelly.py kelly.xml
```

About 90% of the 8 425 Kelly lemmas match. Most of the rest are multi-word expressions ("till exempel", "på grund av") and compounds that Folkets lexikon doesn't list as headwords.

## Credits

Dictionary data (bundled and online) comes from Folkets lexikon, © KTH, licensed CC BY-SA 2.5. The generated `folkets_sv_en.tsv` is a derivative work under the same licence.
Coursebook lists: SVALex, Thomas François, Elena Volodina, Ildikó Pilán and Anaïs Tack (2016), "SVALex: a CEFR-graded lexical resource for Swedish foreign and second language learners", LREC 2016, [CEFRLex](https://cental.uclouvain.be/cefrlex/svalex/), licensed CC BY-NC-SA 4.0. This app is non-commercial.
Spoken frequency lists: [FrequencyWords](https://github.com/hermitdave/FrequencyWords) by Hermit Dave, built from OpenSubtitles 2018, licensed CC BY-SA 4.0.
Academic words: Akademisk ordlista, Ribeck, Jansson & Sköldberg (2016), [Språkbanken](https://spraakbanken.gu.se/en/resources/ao), licensed CC BY 4.0.
Expressions: [Swe-MWELex](https://spraakbanken.gu.se/en/resources/swe-mwelex), Språkbanken, University of Gothenburg, licensed CC BY 4.0 (the .xlsx release).
CEFR levels come from the Swedish Kelly list, [Språkbanken](https://spraakbanken.gu.se/en/resources/kelly), University of Gothenburg, licensed CC BY 4.0.
