import { html, useEffect, useRef, useState } from "../../vendor/preact-htm.js";
import { dictionary, formList, headword, shortPos } from "../dictionary.js";
import { AGAIN, apply, GOOD, GRADES, HARD, isDue, preview, retention } from "../scheduler.js";
import { enabledMethods, pickMethod } from "../methods.js";
import { checkSpelling as check } from "../spelling.js";
import { speak } from "../speech.js";
import { store } from "../store.js";
import { Kbd, useKeys } from "../keys.js";
import { WordDetailView } from "./detail.js";
import { back, ExampleText, HintLines, Icon, NavBar, SpeakButton } from "../ui.js";

export const REVIEW_MODES = [
  { id: "flashcards", title: "Flashcards", icon: "cards" },
  { id: "reverse", title: "English → Swedish", icon: "swap" },
  { id: "choice", title: "Multiple choice", icon: "list" },
  { id: "listening", title: "Listening", icon: "ear" },
  { id: "spelling", title: "Spelling", icon: "keyboard" },
];

const shuffle = (a) => {
  const b = [...a];
  for (let i = b.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [b[i], b[j]] = [b[j], b[i]];
  }
  return b;
};

/** Mixed review picks a method for each card (see methods.js). */
export const MIXED = { id: "mixed", title: "Mixed", icon: "shuffle" };

/**
 * Practice reviews are logged (they count toward the daily goal) but don't change the schedule. modeId "mixed" picks
 * a method for each card.
 */
export function ReviewView({ modeId, practice }) {
  // null for a mixed session.
  const mode = modeId === MIXED.id ? null : REVIEW_MODES.find((m) => m.id === modeId) ?? REVIEW_MODES[0];
  const [queue, setQueue] = useState(() => {
    const all = [...store.words.values()];
    const size = store.get("sessionSize");
    const picked = practice
      ? all.sort((a, b) => retention(a) - retention(b)).slice(0, size)
      : all.filter((w) => isDue(w)).sort((a, b) => a.dueDate - b.dueDate).slice(0, size);
    return shuffle(picked.map((w) => w.key));
  });
  // Each word's past answers ({ mode, grade }), oldest first, for picking methods in a mixed session.
  const attempts = useRef(null);
  if (!attempts.current) {
    attempts.current = new Map();
    if (!mode) {
      const keys = new Set(queue);
      for (const l of store.logs) {
        if (!l.mode || !keys.has(l.wordKey)) continue;
        if (!attempts.current.has(l.wordKey)) attempts.current.set(l.wordKey, []);
        attempts.current.get(l.wordKey).push({ mode: l.mode, grade: l.grade });
      }
    }
  }
  const [card, setCard] = useState({ method: mode?.id ?? null, revealed: false, picked: null, typed: "", spelling: null, forgot: false, options: [] });
  const [score, setScore] = useState({ reviewed: 0, correct: 0 });
  // The current word's detail page, shown over the card; the session stays as it was underneath.
  const [detail, setDetail] = useState(false);
  const typing = useRef(null);
  // The last answer, until the next one, so it can be undone: { word (as it was), log, queue, score, method }. Its
  // log is only saved once the answer can no longer be undone, because a log that has synced can't be taken back.
  const [last, setLast] = useState(null);
  const lastRef = useRef(null);
  lastRef.current = last;
  /** The method an undone card had, so it comes back the same. */
  const undoneMethod = useRef(null);
  const saveLast = () => {
    const pending = lastRef.current;
    if (!pending) return;
    lastRef.current = null;
    store.addLog(pending.log);
    store.flush();
  };
  // Leaving the session, or the page going into the background (it may be closed), saves the last answer's log.
  useEffect(() => {
    const onHide = () => document.visibilityState === "hidden" && saveLast();
    document.addEventListener("visibilitychange", onHide);
    return () => {
      document.removeEventListener("visibilitychange", onHide);
      saveLast();
    };
  }, []);

  // Words deleted during the session (e.g. on another device) drop out of the queue.
  const live = queue.filter((k) => store.words.has(k));
  const word = live.length ? store.words.get(live[0]) : null;
  const autoSpeak = store.get("autoSpeak");
  // The method of the current card.
  const method = mode?.id ?? card.method;

  // Prepare each new card.
  useEffect(() => {
    if (!word) return;
    const method = undoneMethod.current ?? mode?.id ?? pickMethod(enabledMethods(store.get("disabledReviewModes")), attempts.current.get(word.key) ?? []);
    let options = [];
    if (method === "choice" || method === "listening") {
      const wrong = new Set(shuffle(live.map((k) => store.words.get(k).translation).filter((t) => t !== word.translation)).slice(0, 3));
      for (const t of dictionary.distractors(word.translation, 6)) if (wrong.size < 3) wrong.add(t);
      options = shuffle([...wrong, word.translation]);
    }
    undoneMethod.current = null;
    setDetail(false);
    setCard({ method, revealed: false, picked: null, typed: "", spelling: null, forgot: false, options });
    if ((method === "flashcards" || method === "choice") && autoSpeak) speak(word.word);
    if (method === "listening") speak(word.word);
    if (method === "spelling") setTimeout(() => typing.current?.focus(), 0);
  }, [word?.key, score.reviewed]);

  const answer = (grade) => {
    if (!word) return;
    saveLast();
    const updated = practice ? word : apply(grade, word);
    if (!practice) store.updateWord(word.key, updated);
    const log = { date: Date.now(), wordKey: word.key, grade, intervalAfter: updated.interval, mode: method };
    setLast({ word, log, queue: live, score, method });
    if (!attempts.current.has(word.key)) attempts.current.set(word.key, []);
    attempts.current.get(word.key).push({ mode: method, grade });
    const rest = live.slice(1);
    // Forgotten words come back later in the same session, the last one too.
    if (grade === AGAIN) rest.splice(Math.min(rest.length, 4), 0, word.key);
    setQueue(rest);
    setScore((s) => ({ reviewed: s.reviewed + 1, correct: s.correct + (grade === AGAIN ? 0 : 1) }));
  };

  /** Takes back the last answer: the word's schedule, the score and the queue return to how they were. */
  const undo = () => {
    if (!last) return;
    lastRef.current = null;
    if (!practice && store.words.has(last.word.key)) store.updateWord(last.word.key, last.word);
    attempts.current.get(last.word.key)?.pop();
    undoneMethod.current = last.method;
    setLast(null);
    setQueue(last.queue);
    setScore(last.score);
  };

  const reveal = () => {
    setCard((c) => ({ ...c, revealed: true }));
    if (method === "reverse" && autoSpeak) speak(word.word);
  };

  const pick = (option) => {
    if (card.picked != null || card.forgot) return;
    setCard((c) => ({ ...c, picked: option }));
    if (method === "listening" || !autoSpeak) speak(word.word);
  };

  /** "I forget": shows the answer, and Continue grades the word Again. */
  const forget = () => {
    setCard((c) => ({
      ...c, forgot: true, revealed: true,
      spelling: method === "spelling" ? { grade: AGAIN, message: "Marked as forgotten" } : null,
    }));
    speak(word.word);
  };

  const checkSpelling = () => {
    if (!card.typed.trim()) return;
    const { kind, form } = check(card.typed, word.word, formList(word));
    const spelling = kind === "correct" ? { grade: GOOD, message: form ? `Rätt! ${form} is a form of ${word.word}.` : "Rätt! Correct." }
      : kind === "diacritics" ? { grade: HARD, message: `Almost — mind the å, ä, ö: ${word.word}` }
      : kind === "typo" ? { grade: HARD, message: form ? `Almost — small typo. It's spelled ${form}, a form of ${word.word}.` : `Almost — small typo. It's spelled ${word.word}.` }
      : { grade: AGAIN, message: `Answer: ${word.word}` };
    setCard((c) => ({ ...c, spelling }));
    speak(word.word);
  };

  // Keyboard: space or enter shows the answer and continues, 1–4 grade or pick an option, F (Esc in spelling) is
  // "I forget", P plays the word again.
  const flip = method === "flashcards" || method === "reverse";
  const choice = method === "choice" || method === "listening";
  const proceed = card.forgot ? () => answer(AGAIN)
    : card.spelling ? () => answer(card.spelling.grade)
    : choice && card.picked != null ? () => answer(card.picked === word.translation ? GOOD : AGAIN) : null;
  const answered = card.revealed || card.picked != null || card.spelling != null;
  const openDetail = () => { setDetail(true); scrollTo(0, 0); };
  // While the detail page is open, only its own keys apply.
  useKeys(detail ? [] : word ? [
    [["Space", "Enter"], "Show answer", flip && !card.revealed && reveal],
    [["f"], "I forget", !card.forgot && !card.revealed && card.picked == null && !card.spelling && forget],
    ...GRADES.map((g) => [[String(g.value + 1)], g.title, flip && card.revealed && !card.forgot && (() => answer(g.value))]),
    ...card.options.map((o, i) => [[String(i + 1)], `Answer ${i + 1}`, choice && card.picked == null && !card.forgot && (() => pick(o))]),
    [["Space", "Enter"], "Continue", proceed],
    // In English → Swedish and spelling, the word is the answer: it plays only once it's shown.
    ...(method === "reverse" || method === "spelling") && !(card.revealed || card.spelling) ? [] : [
      [["p"], "Play the word", () => speak(word.word)],
      [["P"], "Play it slowly", () => speak(word.word, { slow: true })],
    ],
    [["x"], "Play the example", word.example && answered && (() => speak(word.example))],
    [["d"], "Word details", answered && openDetail],
    [["u", "Mod+z"], "Undo the last answer", last && undo],
  ] : [[["Space", "Enter"], "Done", () => back("today")], [["u", "Mod+z"], "Undo the last answer", last && undo]]);

  const title = practice ? `${(mode ?? MIXED).title} · practice` : mode?.title ?? "Mixed review";
  // Until the first card's method is picked.
  if (word && !method) return html`<${NavBar} title=${title} backTo="today" backLabel="Today" />`;
  const undoButton = last ? html`<button class="bar-button" onClick=${undo} title="Undo the last answer (U)" aria-label="Undo the last answer">
    <${Icon} name="undo" /> Undo</button>` : null;
  if (!word) return html`<${NavBar} title=${title} backTo="today" backLabel="Today" right=${undoButton} /><${Finished} score=${score} />`;

  if (detail) return html`<${WordDetailView} id=${word.key} onBack=${() => setDetail(false)} />`;
  return html`
    <${NavBar} title=${title} backTo="today" backLabel="Today" right=${undoButton} />
    <div class="page"><div class="stack">
      <div class="row caption secondary mono">
        <span>${live.length} left</span><span class="spacer"></span>
        ${mode ? null : html`<span><${Icon} name=${REVIEW_MODES.find((m) => m.id === method).icon} /> ${REVIEW_MODES.find((m) => m.id === method).title}</span><span class="spacer"></span>`}
        ${score.reviewed ? html`<span>${Math.round((score.correct / score.reviewed) * 100)}% correct</span>` : null}
      </div>
      <div class="flashcard" key=${`${word.key}-${score.reviewed}`}>
        <${Prompt} mode=${method} word=${word} card=${card} />
        ${answered ? html`<${Details} mode=${method} word=${word} onOpen=${openDetail} />` : null}
      </div>
      <${Controls} mode=${method} word=${word} card=${card} practice=${practice} typing=${typing}
        onReveal=${reveal} onForget=${forget} onAnswer=${answer} onPick=${pick} onCheck=${checkSpelling}
        onType=${(typed) => setCard((c) => ({ ...c, typed }))}
      />
    </div></div>`;
}

function SwedishHeader({ word }) {
  return html`<div style="display:flex;flex-direction:column;align-items:center;gap:8px">
    <div class="review-word">${headword(word)}</div>
    <${SpeakButton} text=${word.word} size="big" hotkey="p" />
  </div>`;
}

function Prompt({ mode, word, card }) {
  if (mode === "flashcards" || mode === "choice") return html`<${SwedishHeader} word=${word} />`;
  if (mode === "listening") {
    return html`<div class="row" style="gap:32px;padding:16px">
        <span class="speak"><button class="icon-button huge" onClick=${() => speak(word.word)} aria-label="Play again" title="Play again (P)"><${Icon} name="speaker" /></button><${Kbd} k="p" /></span>
        <span class="speak"><button class="icon-button big" onClick=${() => speak(word.word, { slow: true })} aria-label="Play slowly" title="Play slowly (Shift+P)"><${Icon} name="slow" /></button><${Kbd} k="P" /></span>
      </div>
      ${card.picked != null || card.forgot ? html`<${SwedishHeader} word=${word} />` : null}`;
  }
  return html`<div class="title" style="font-size:28px">${word.translation}</div>
    <div class="secondary">${word.gender ? `${word.gender} …` : shortPos(word.partOfSpeech)}</div>
    ${card.revealed || card.spelling ? html`<hr /><${SwedishHeader} word=${word} />` : null}`;
}

function Details({ mode, word, onOpen }) {
  return html`<hr class="fade-in" />
    ${mode === "flashcards" || mode === "listening" || mode === "choice" ? html`<div class="title3 fade-in">${word.translation}</div>` : null}
    <${HintLines} word=${word.word} partOfSpeech=${word.partOfSpeech} />
    ${word.forms ? html`<div class="subheadline secondary fade-in">${formList(word).join(" · ")}</div>` : null}
    ${word.example ? html`<div class="fade-in" style="display:flex;flex-direction:column;align-items:center;gap:4px">
      <${ExampleText} text=${word.example} />
      <div class="subheadline secondary">${word.exampleTranslation}</div>
      <${SpeakButton} text=${word.example} hotkey="x" /></div>` : null}
    ${word.note ? html`<div class="footnote secondary fade-in"><${Icon} name="note" /> ${word.note}</div>` : null}
    <button class="btn small fade-in" onClick=${onOpen} title="Open the word's page (D)">Word details<${Icon} name="chevronRight" /><${Kbd} k="d" /></button>`;
}

const forgotten = html`<div class="headline red fade-in"><${Icon} name="xCircle" /> Marked as forgotten</div>`;

function Controls({ mode, word, card, practice, typing, onReveal, onForget, onAnswer, onPick, onCheck, onType }) {
  const forgetButton = (k) => html`<button class="btn large" onClick=${onForget}>I forget<${Kbd} k=${k} /></button>`;
  const continueButton = (grade) => html`<button class="btn prominent large full" onClick=${() => onAnswer(grade)}>Continue<${Kbd} k="Enter" /></button>`;
  if (mode === "flashcards" || mode === "reverse") {
    if (card.forgot) return html`<div style="display:flex;flex-direction:column;gap:10px">${forgotten}${continueButton(AGAIN)}</div>`;
    if (!card.revealed) return html`<div class="row" style="gap:12px">${forgetButton("f")}
      <button class="btn prominent large full" onClick=${onReveal}>Show answer<${Kbd} k="Space" /></button></div>`;
    return html`<div class="grade-row">
      ${GRADES.map((g) => html`<button class="btn tinted" style=${{ "--tint": `var(--${g.color})` }} onClick=${() => onAnswer(g.value)}
        title=${`${g.title} (${g.value + 1})`}>
        <span class="subheadline bold">${g.title}</span>${practice ? null : html`<span class="caption2">${preview(g.value, word)}</span>`}<${Kbd} k=${String(g.value + 1)} />
      </button>`)}
    </div>`;
  }
  if (mode === "choice" || mode === "listening") {
    const answered = card.picked != null || card.forgot;
    const tint = (option) => !answered ? null : option === word.translation ? "green" : option === card.picked ? "red" : "gray";
    return html`<div style="display:flex;flex-direction:column;gap:10px">
      ${card.options.map((option, i) => html`<button class=${`btn large full ${tint(option) ? "tinted" : ""}`}
        style=${tint(option) ? { "--tint": `var(--${tint(option)})`, fontWeight: 500 } : { fontWeight: 500 }} onClick=${() => onPick(option)}>
        <span class="clamp2">${option}</span>${!answered ? html`<${Kbd} k=${String(i + 1)} />` : null}</button>`)}
      ${card.forgot ? html`${forgotten}${continueButton(AGAIN)}`
        : card.picked != null ? continueButton(card.picked === word.translation ? GOOD : AGAIN)
        : forgetButton("f")}
    </div>`;
  }
  // Spelling
  if (card.spelling) {
    const s = card.spelling;
    return html`<div style="display:flex;flex-direction:column;gap:10px">
      <div class="headline" style=${{ color: `var(--${GRADES[s.grade].color})` }}><${Icon} name=${s.grade === AGAIN ? "xCircle" : "checkCircle"} /> ${s.message}</div>
      ${continueButton(s.grade)}
    </div>`;
  }
  const insert = (letter) => {
    onType(card.typed + letter);
    typing.current?.focus();
  };
  return html`<div style="display:flex;flex-direction:column;gap:10px">
    <input ref=${typing} class="typing" placeholder="Type the Swedish word" value=${card.typed} autocomplete="off" autocapitalize="off"
      spellcheck=${false} onInput=${(e) => onType(e.currentTarget.value)} onKeyDown=${(e) => {
        if (e.key === "Enter") return onCheck();
        if (e.key === "Escape") {
          e.preventDefault();
          return onForget();
        }
        // å, ä, ö sit where [, ' and ; are on an English keyboard; Swedish words never use those characters.
        const letter = SWEDISH_KEYS[e.key];
        if (letter && !e.metaKey && !e.ctrlKey) {
          e.preventDefault();
          insert(letter);
        }
      }} />
    <div class="row wrap" style="gap:8px">
      ${[["å", "["], ["ä", "'"], ["ö", ";"]].map(([l, k]) => html`<button class="btn" onClick=${() => insert(l)} title=${`Type ${l} (or press ${k})`}>${l}<${Kbd} k=${k} /></button>`)}
      <span class="spacer"></span>
      <button class="btn plain" onClick=${onForget}>I forget<${Kbd} k="Escape" /></button>
      <button class="btn prominent" disabled=${!card.typed.trim()} onClick=${onCheck}>Check</button>
    </div>
  </div>`;
}

const SWEDISH_KEYS = { "[": "å", "{": "Å", "'": "ä", '"': "Ä", ";": "ö", ":": "Ö" };

function Finished({ score }) {
  return html`<div class="page"><div class="empty" style="gap:16px;padding-top:64px">
    <span class="accent"><${Icon} name=${score.reviewed ? "party" : "checkCircle"} /></span>
    <h2 style="font-size:28px">${score.reviewed ? "Session complete!" : "Nothing to review"}</h2>
    <div>${score.reviewed ? `${score.reviewed} answers · ${Math.round((score.correct / score.reviewed) * 100)}% correct` : "Add words to your collection first."}</div>
    <button class="btn prominent large" onClick=${() => back("today")}>Done<${Kbd} k="Enter" /></button>
  </div></div>`;
}
