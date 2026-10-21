# Svenska – Swedish vocabulary builder for iOS

A compact SwiftUI app for building Swedish vocabulary, with a full offline Swedish–English dictionary, spaced repetition and a daily check-in streak.

## Features

- **Lookup** – search in Swedish or English, with or without å/ä/ö ("bat" finds "båt"). About 37 000 words work offline: a curated core vocabulary of ~700 common words plus the whole of [Folkets lexikon](https://folkets-lexikon.csc.kth.se/folkets/) (KTH). Anything else is looked up in Folkets lexikon online. Recent searches are remembered.
- **Word details** – article (en/ett), inflected forms, translation, example sentence with translation, personal notes.
- **Pronunciation** – every word, form and example sentence can be spoken with the system's Swedish (sv-SE) voice, at normal or slow speed. Optional auto-pronounce.
- **Collection** – save words, add your own, edit, favourite, filter (due, learning, mastered, favourites), sort (recent, A–Z, next review, weakest memory), swipe to delete. Export as CSV.
- **Learn new words** – step through the core vocabulary in frequency order, or a CEFR word list (A1, A2, B1, B2, C1, C2) from the Swedish Kelly list, with progress per list: "Learn" adds a word, "I know it" skips it.
- **CEFR levels** – about 7 500 words carry a level badge (A1–C2) in search results, word details and your collection, which you can filter by level.
- **Spaced repetition** – an SM-2 scheduler with Again / Hard / Good / Easy grading and interval previews. Forgotten words come back in the same session.
- **Forgetting curve** – each word has a modelled recall probability R(t) = 0.9^(t / interval), shown as a memory-strength bar and a curve on its detail page.
- **Review modes** – flashcards, English → Swedish, multiple choice, listening, and spelling (with å/ä/ö keys and "almost right" detection). When nothing is due you can practise without changing the schedule.
- **Daily check-in** – set a daily goal (reviews + new words). Once you reach it you can check in. Streak counter, a week strip, and a daily reminder notification.
- **Summary** – words, mastered, current and best streak, total reviews, 30-day accuracy, a 14-day activity chart, mastery breakdown, a forgetting curve for your whole collection, a 7-day review forecast, a check-in calendar, and your trickiest words.

## Requirements

- Xcode 16 or later
- iOS 17 or later (SwiftData, Swift Charts)

## Running

1. Open `SvenskaVocab.xcodeproj` in Xcode.
2. Select the **SvenskaVocab** target › Signing & Capabilities and choose your team. If the bundle ID is taken, change `com.xingkai03.SvenskaVocab`.
3. Run on a simulator or a device.

For the best pronunciation, download an enhanced Swedish voice on the device: Settings › Accessibility › Spoken Content › Voices › Swedish.

The project uses Xcode 16's folder-synchronised groups, so new files you add under `SvenskaVocab/` are picked up automatically. On older Xcode, regenerate the project with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.

## Project layout

```
SvenskaVocab/
  App/            App entry point and tab bar
  Models/         SwiftData models (SavedWord, ReviewLog, CheckIn) and DictionaryEntry
  Services/       Dictionary (offline + Folkets lexikon), speech, scheduler, settings, reminders
  Views/          Today, Lookup, Collection, Review, Summary
  Resources/      core_vocabulary.tsv (curated), folkets_sv_en.tsv and kelly_levels.tsv (generated)
scripts/          build_folkets.py, build_kelly.py
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

### Updating the CEFR levels

`Resources/kelly_levels.tsv` (word, part of speech, level, Kelly rank) is generated from the Swedish Kelly list by `scripts/build_kelly.py`. It keeps only words found in the two dictionary files, so run it after `build_folkets.py`:

```
curl -LO https://svn.spraakbanken.gu.se/sb-arkiv/pub/lmf/kelly/kelly.xml
python3 scripts/build_kelly.py kelly.xml
```

About 90% of the 8 425 Kelly lemmas match. Most of the rest are multi-word expressions ("till exempel", "på grund av") and compounds that Folkets lexikon doesn't list as headwords.

## Credits

Dictionary data (bundled and online) comes from Folkets lexikon, © KTH, licensed CC BY-SA 2.5. The generated `folkets_sv_en.tsv` is a derivative work under the same licence.
CEFR levels come from the Swedish Kelly list, [Språkbanken](https://spraakbanken.gu.se/en/resources/kelly), University of Gothenburg, licensed CC BY 4.0.
