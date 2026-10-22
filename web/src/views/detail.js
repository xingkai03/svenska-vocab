import { html, useEffect } from "../../vendor/preact-htm.js";
import { LineChart } from "../charts.js";
import { dictionary, formList, headword } from "../dictionary.js";
import { isDue, mastery, retention, retentionAfter, DAY } from "../scheduler.js";
import { speak } from "../speech.js";
import { store } from "../store.js";
import { EmptyState, Icon, LevelBadge, NavBar, PosTag, Section, SpeakButton, go, relative } from "../ui.js";

export function WordDetailView({ id }) {
  const saved = store.words.get(id);
  const entry = saved ?? dictionary.entry(id);

  useEffect(() => {
    if (entry && store.get("autoSpeak")) speak(entry.word);
  }, [id]);

  if (!entry) {
    return html`<${NavBar} title="Word" backTo="lookup" />
      <div class="page"><${EmptyState} icon="search" title="Word not found">It may have been removed from your words.<//></div>`;
  }
  const level = entry.level || dictionary.entry(id)?.level || "";
  const forms = formList(entry);

  const remove = () => {
    if (confirm(`Remove “${entry.word}” and its review history?`)) store.deleteWord(id);
  };

  return html`
    <${NavBar} title=${entry.word} backTo="lookup" right=${saved ? html`
      <button class="bar-button" onClick=${() => store.updateWord(id, { isFavorite: !saved.isFavorite })} aria-label="Favorite" title="Favorite">
        <${Icon} name=${saved.isFavorite ? "starFill" : "star"} /></button>
      <button class="bar-button" onClick=${() => go("edit", id)}>Edit</button>` : null} />
    <div class="page">
      <${Section}>
        <div class="cell"><div class="cell-main" style="gap:8px">
          <div class="row baseline wrap" style="gap:8px">
            <span class="title" style="flex:1">${headword(entry)}</span><${PosTag} entry=${entry} /><${LevelBadge} level=${level} />
          </div>
          <div class="title3">${entry.translation}</div>
          <div class="row" style="gap:16px"><${SpeakButton} text=${entry.word} size="big" /><${SpeakButton} text=${entry.word} slow size="big" /></div>
        </div></div>
      <//>

      ${forms.length ? html`<${Section} header="Forms">
        ${forms.map((f) => html`<div class="cell"><span class="cell-main">${f}</span><${SpeakButton} text=${f} /></div>`)}
      <//>` : null}

      ${entry.example ? html`<${Section} header="Example">
        <div class="cell"><div class="cell-main">
          <span class="italic">${entry.example}</span>
          ${entry.exampleTranslation ? html`<span class="subheadline secondary">${entry.exampleTranslation}</span>` : null}
        </div><${SpeakButton} text=${entry.example} /></div>
      <//>` : null}

      ${saved ? html`<${Memory} word=${saved} />
        <${Section} header="My note">
          <textarea class="text" rows="2" placeholder="Mnemonic, context, related words…" value=${saved.note}
            onInput=${(e) => store.updateWord(id, { note: e.currentTarget.value })}></textarea>
        <//>` : null}

      <${Section} footer=${entry.source === "online" ? "From Folkets lexikon, CC BY-SA 2.5." : null}>
        ${saved
          ? html`<button class="cell destructive" onClick=${remove}><${Icon} name="bookmarkSlash" /> Remove from my words</button>`
          : html`<button class="cell action" onClick=${() => store.addToCollection(entry)}><${Icon} name="bookmark" /> Add to my words</button>`}
      <//>
    </div>`;
}

/** Spaced-repetition status plus the word's personal forgetting curve. */
function Memory({ word }) {
  const reviewed = word.lastReviewedAt != null;
  const horizon = Math.max(14, Math.min(120, word.interval * 2));
  const elapsed = reviewed ? (Date.now() - word.lastReviewedAt) / DAY : 0;
  const points = [];
  for (let step = 0; step <= horizon * 2; step++) points.push([step / 2, retentionAfter(step / 2, word.interval)]);
  return html`<${Section} header="Memory" footer=${reviewed
      ? "Each successful review flattens the curve, so the next review can wait longer."
      : "Review this word once to start its forgetting curve."}>
    <div class="cell"><span class="cell-main">Level</span><span class="value">${mastery(word)}</span></div>
    <div class="cell"><span class="cell-main">Next review</span><span class="value">${isDue(word) ? "Now" : relative(word.dueDate)}</span></div>
    <div class="cell"><span class="cell-main">Reviews</span><span class="value">${word.reviewCount} (${word.lapses} forgotten)</span></div>
    ${reviewed ? html`
      <div class="cell"><span class="cell-main">Memory now</span><span class="value">${Math.round(retention(word) * 100)}%</span></div>
      <div class="cell"><div class="cell-main">
        <${LineChart} height=${150} xMax=${horizon} yTicks=${[0, 0.5, 0.9, 1]} xLabel="days since last review"
          series=${[{ color: "var(--accent)", points, fill: true }]}
          marker=${{ x: Math.min(elapsed, horizon), label: "now", color: "var(--orange)" }}
          ariaLabel="Forgetting curve of this word" />
      </div></div>` : null}
  <//>`;
}
