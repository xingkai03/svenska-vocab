// "AI check & polish" for the word edit page (iOS app and web). Asks Google Gemini to check a word's translation,
// part of speech, gender and forms, add meanings that are missing, fix the example sentences and add a few more.
// The app shows the suggestion and the learner decides what to keep; nothing is saved here.
//
// The Gemini API key lives only in this function's secrets, never in the app or the public web site:
//   GEMINI_API_KEY          required
//   GEMINI_MODEL            optional, default gemini-3.8-flash
//   POLISH_ALLOWED_EMAILS   optional, comma separated; when set, only these accounts may use the function
// Deployed with JWT verification on, so only signed-in learners can call it.

const POS = ["noun", "verb", "adjective", "adverb", "pronoun", "preposition",
  "conjunction", "numeral", "interjection", "phrase"];
const MAX_EXAMPLES = 6;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const INSTRUCTIONS = `You are an expert Swedish lexicographer helping an adult learner (English is the learner's \
working language) keep a personal vocabulary list accurate. You get one saved entry as JSON. Check and improve it:

- translation: English meanings, most common first, separated by "; ". Fix wrong or misleading meanings and add \
common meanings that are missing (other senses of the word, important phrasal uses). Keep it concise: at most about \
8 short meanings, no explanations in sentences. For verbs start meanings with "to ".
- partOfSpeech: one of ${POS.join(", ")}. Change it only if it is wrong.
- gender: "en" or "ett" for nouns, "" for everything else.
- forms: the inflected forms, comma separated, in the usual dictionary order (nouns: definite singular, indefinite \
plural, definite plural; verbs: present, past, supine, imperative; adjectives: neuter, plural/definite, then \
comparative and superlative if they exist). Empty for words that do not inflect.
- examples: keep the learner's existing example sentences (correct any mistakes in them or in their English \
translations), then add new ones so there are 3 to 5 in total. Write natural, everyday Swedish of the kind a \
native speaker would say, around CEFR A2–B1 unless the word itself is advanced, one short sentence each. Use the \
word in different meanings and forms so each sentence teaches something. Each needs an accurate English translation.
- notes: one or two short sentences in English telling the learner what you changed and why (e.g. "Added the \
meaning 'to fit' and corrected the plural."). Say "Looks good." with nothing else if no change was needed.

Do not change the Swedish headword itself. Never invent meanings: if unsure, keep the original.`;

const schema = {
  type: "object",
  properties: {
    translation: { type: "string" },
    partOfSpeech: { type: "string", enum: POS },
    gender: { type: "string", enum: ["en", "ett", ""] },
    forms: { type: "string" },
    examples: {
      type: "array",
      items: {
        type: "object",
        properties: { sv: { type: "string" }, en: { type: "string" } },
        required: ["sv", "en"],
      },
    },
    notes: { type: "string" },
  },
  required: ["translation", "partOfSpeech", "gender", "forms", "examples", "notes"],
};

type Example = { sv: string; en: string };
type Entry = {
  word: string; partOfSpeech: string; gender: string; forms: string; translation: string; examples: Example[];
};

/** One line of text: trimmed, no line breaks (examples are stored one per line), and not absurdly long. */
const line = (value: unknown, max = 400) =>
  (typeof value === "string" ? value : "").replace(/\s*[\r\n]+\s*/g, " ").trim().slice(0, max);

function readEntry(body: Record<string, unknown>): Entry {
  const examples = Array.isArray(body.examples) ? body.examples : [];
  return {
    word: line(body.word, 100),
    partOfSpeech: line(body.partOfSpeech, 20),
    gender: line(body.gender, 3),
    forms: line(body.forms),
    translation: line(body.translation, 1000),
    examples: examples.slice(0, MAX_EXAMPLES).map((e) => ({ sv: line(e?.sv), en: line(e?.en) })).filter((e) => e.sv),
  };
}

function cleanSuggestion(raw: Record<string, unknown>, entry: Entry) {
  const partOfSpeech = POS.includes(raw.partOfSpeech as string) ? raw.partOfSpeech as string : entry.partOfSpeech;
  const gender = partOfSpeech === "noun" && ["en", "ett"].includes(raw.gender as string) ? raw.gender as string : "";
  const examples = (Array.isArray(raw.examples) ? raw.examples : [])
    .map((e) => ({ sv: line(e?.sv), en: line(e?.en) })).filter((e) => e.sv).slice(0, MAX_EXAMPLES);
  return {
    translation: line(raw.translation, 1000) || entry.translation,
    partOfSpeech,
    gender,
    forms: line(raw.forms),
    examples: examples.length ? examples : entry.examples,
    notes: line(raw.notes, 600),
  };
}

/** The signed-in user's email from the access token. The gateway has already verified the token's signature. */
function emailFromToken(req: Request): string {
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  try {
    const payload = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    return String(JSON.parse(atob(payload)).email ?? "").toLowerCase();
  } catch {
    return "";
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return json({ error: "AI polish is not set up yet: the Gemini API key is missing." }, 503);

  const allowed = (Deno.env.get("POLISH_ALLOWED_EMAILS") ?? "").split(",").map((s) => s.trim().toLowerCase())
    .filter(Boolean);
  if (allowed.length && !allowed.includes(emailFromToken(req))) {
    return json({ error: "AI polish is not available for this account." }, 403);
  }

  let entry: Entry;
  try {
    entry = readEntry(await req.json());
  } catch {
    return json({ error: "Invalid request." }, 400);
  }
  if (!entry.word) return json({ error: "The word is empty." }, 400);

  const model = Deno.env.get("GEMINI_MODEL") || "gemini-3.8-flash";
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: INSTRUCTIONS }] },
        contents: [{ role: "user", parts: [{ text: JSON.stringify(entry) }] }],
        generationConfig: { responseMimeType: "application/json", responseJsonSchema: schema },
      }),
    },
  ).catch(() => null);

  if (!response) return json({ error: "Could not reach Gemini. Try again in a moment." }, 502);
  const result = await response.json().catch(() => ({}));
  if (!response.ok) {
    console.error("Gemini error", response.status, JSON.stringify(result).slice(0, 2000));
    const message = response.status === 429
      ? "Gemini's rate limit was reached. Try again in a minute."
      : `Gemini returned an error (${response.status})${result.error?.message ? `: ${line(result.error.message, 300)}` : "."}`;
    return json({ error: message }, 502);
  }

  const text = (result.candidates?.[0]?.content?.parts ?? [])
    .filter((p: { thought?: boolean }) => !p.thought).map((p: { text?: string }) => p.text ?? "").join("");
  try {
    return json(cleanSuggestion(JSON.parse(text), entry));
  } catch {
    console.error("Unreadable Gemini answer", text.slice(0, 2000));
    return json({ error: "Gemini's answer could not be read. Try again." }, 502);
  }
});
