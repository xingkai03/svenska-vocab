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
  const trimmed = (text ?? "").trim();
  if (!trimmed || !synth) return;
  synth.cancel();
  const utterance = new SpeechSynthesisUtterance(trimmed);
  utterance.lang = "sv-SE";
  const voice = swedishVoice();
  if (voice) utterance.voice = voice;
  // The app's speed setting is an iOS speech rate, where 0.5 is normal speed; the web's normal rate is 1.
  const base = store.get("speechRate") / 0.5;
  utterance.rate = Math.min(2, Math.max(0.3, slow ? base * 0.6 : base));
  synth.speak(utterance);
}
