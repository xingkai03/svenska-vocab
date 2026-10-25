// SVT Play clips: a links-only index (word → [episode, second]) of where each word is said in SVT's subtitles.
// web/svt/episodes.json lists the episodes; web/svt/<shard>.json holds the words starting with the same two letters.
// Moved here from xingkai03.github.io/svt-learn. Only word positions are stored, never SVT's subtitles.

export const PLAY = "https://www.svtplay.se";
const NEAR = 20; // seconds: the words of a multi-word search must be said this close together

const shardName = (w) => [...w.slice(0, 2)].map((c) => c.codePointAt(0).toString(16)).join("");
const today = () => new Date().toISOString().slice(0, 10);

/** "1:02:05" or "2:05". */
export const clipTime = (s) => {
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = String(s % 60).padStart(2, "0");
  return h ? `${h}:${String(m).padStart(2, "0")}:${sec}` : `${m}:${sec}`;
};

/** Link that starts the episode a moment before the word is said. */
export const clipLink = (episode, second) => `${PLAY}${episode.u}?position=${Math.max(0, second - 2)}`;

/** Search terms in a query: lower-case runs of two or more letters. */
export const svtTerms = (query) => query.toLowerCase().match(/[\p{L}]{2,}/gu) ?? [];

class SvtIndex {
  shards = new Map();
  meta = null;

  /** { built, episodes: [{ p: programme, n: name, u: path, to: "YYYY-MM-DD" }] }, newest episodes first. */
  load() {
    this.meta ??= fetch("svt/episodes.json").then((r) => {
      if (!r.ok) throw new Error("Couldn't load the SVT Play index.");
      return r.json();
    });
    return this.meta;
  }

  shard(word) {
    const name = shardName(word);
    if (!this.shards.has(name)) {
      this.shards.set(name, fetch(`svt/${name}.json`).then((r) => (r.ok ? r.json() : {})).catch(() => ({})));
    }
    return this.shards.get(name);
  }

  /** Hits for one term: the exact word, or (prefix) every word starting with it, most-said first. */
  async hitsFor(term, prefix) {
    const words = await this.shard(term);
    if (!prefix) return { matched: words[term] ? [term] : [], hits: words[term] ?? [] };
    const matched = Object.keys(words).filter((w) => w.startsWith(term)).sort((a, b) => words[b].length - words[a].length);
    return { matched, hits: matched.flatMap((w) => words[w]) };
  }

  /**
   * Episodes where every term is said within NEAR seconds of the first, newest first, leaving out episodes that have
   * left SVT Play. `anyOf` instead treats the terms as alternatives (a word and its inflected forms).
   * Returns { matched, results: [{ episode, times: [seconds] }] }.
   */
  async search(terms, { prefix = false, programme = "", anyOf = false } = {}) {
    const { episodes } = await this.load();
    const parts = await Promise.all(terms.map((t) => this.hitsFor(t, prefix)));
    let found;
    if (anyOf) {
      found = parts.flatMap((p) => p.hits);
    } else {
      found = parts[0]?.hits ?? [];
      for (const other of parts.slice(1)) {
        const byEpisode = new Map();
        for (const [ep, t] of other.hits) (byEpisode.get(ep) ?? byEpisode.set(ep, []).get(ep)).push(t);
        found = found.filter(([ep, t]) => (byEpisode.get(ep) ?? []).some((u) => Math.abs(u - t) <= NEAR));
      }
    }
    const now = today();
    const grouped = new Map();
    for (const [ep, t] of found) {
      const e = episodes[ep];
      if (!e || (programme && e.p !== programme) || (e.to && e.to < now)) continue;
      (grouped.get(ep) ?? grouped.set(ep, new Set()).get(ep)).add(t);
    }
    const results = [...grouped.keys()].sort((a, b) => a - b)
      .map((ep) => ({ episode: episodes[ep], times: [...grouped.get(ep)].sort((a, b) => a - b) }));
    return { matched: parts[0]?.matched ?? [], results };
  }
}

export const svt = new SvtIndex();
