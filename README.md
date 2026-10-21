# Svenska – Swedish vocabulary builder for iOS

A compact SwiftUI app for building Swedish vocabulary, with an offline core dictionary, spaced repetition and a daily check-in streak.

## Features

- **Lookup** – search in Swedish or English, with or without å/ä/ö ("bat" finds "båt"). About 700 common words work offline; anything else is looked up in [Folkets lexikon](https://folkets-lexikon.csc.kth.se/folkets/) (KTH). Recent searches are remembered.
- **Word details** – article (en/ett), inflected forms, translation, example sentence with translation, personal notes.
- **Pronunciation** – every word, form and example sentence can be spoken with the system's Swedish (sv-SE) voice, at normal or slow speed. Optional auto-pronounce.
- **Collection** – save words, add your own, edit, favourite, filter (due, learning, mastered, favourites), sort (recent, A–Z, next review, weakest memory), swipe to delete. Export as CSV.
- **Learn new words** – step through the built-in vocabulary in frequency order: "Learn" adds a word, "I know it" skips it.
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
  Resources/      core_vocabulary.tsv
```

### Extending the built-in vocabulary

`Resources/core_vocabulary.tsv` is tab-separated, one word per line, roughly in frequency order:

```
word  part_of_speech  gender(en/ett)  forms  translation  example  example_translation
```

Part of speech is one of `noun verb adjective adverb pronoun preposition conjunction numeral interjection phrase`. Lines starting with `#` are ignored.

## Credits

Online dictionary data comes from Folkets lexikon, © KTH, licensed CC BY-SA 2.5.
