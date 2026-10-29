// Swedish text-to-speech with the browser's sv-SE voices (Web Speech API), like SpeechService.swift.

import { store } from "./store.js";

const synth = globalThis.speechSynthesis;
let voices = [];

function loadVoices() {
  voices = synth?.getVoices() ?? [];
}
loadVoices();
synth?.addEventListener?.("voiceschanged", loadVoices);

/** The best installed Swedish voice: a natural or online one if there is one. */
export function swedishVoice() {
  const sv = voices.filter((v) => v.lang.replace("_", "-").toLowerCase().startsWith("sv"));
  const score = (v) => (/natural|neural|premium|enhanced|online|google/i.test(v.name) ? 2 : 0) + (v.localService ? 0 : 1);
  return sv.sort((a, b) => score(b) - score(a))[0] ?? null;
}

export const hasSpeech = Boolean(synth);
export const hasSwedishVoice = () => Boolean(swedishVoice());

export function speak(text, { slow = false } = {}) {
  speakAll([text], { slow });
}

/**
 * Speaks the word (when given) and then the example sentence, if "Pronounce example sentences automatically" is on.
 * Used where an example comes into view.
 */
export function speakWithExample(word, example) {
  speakAll([word, store.get("autoSpeakExamples") ? example : ""]);
}

export function stopSpeaking() {
  synth?.cancel();
}

/** Speaks the texts one after another, with a short pause between them. */
let pause;
function speakAll(texts, { slow = false } = {}) {
  const queue = texts.map((t) => (t || "").trim()).filter(Boolean);
  if (!queue.length || !synth) return;
  synth.cancel();
  clearTimeout(pause);
  const voice = swedishVoice();
  // The app's speed setting is an iOS speech rate, where 0.5 is normal speed; the web's normal rate is 1.
  const base = store.get("speechRate") / 0.5;
  const next = () => {
    const utterance = new SpeechSynthesisUtterance(queue.shift());
    utterance.lang = "sv-SE";
    if (voice) utterance.voice = voice;
    utterance.rate = Math.min(2, Math.max(0.3, slow ? base * 0.6 : base));
    // The Web Speech API has no pause between utterances, so the next one starts half a second after this ends.
    // A newer speak() cancels this one and clears the timer, so a stale example never follows the new word.
    if (queue.length) utterance.onend = () => { pause = setTimeout(next, 500); };
    synth.speak(utterance);
  };
  next();
}
