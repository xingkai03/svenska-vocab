// Small SVG charts for the Summary and word pages (Swift Charts in the app).

import { html } from "../vendor/preact-htm.js";

const W = 340;

function niceMax(max) {
  if (max <= 4) return Math.max(max, 1);
  const step = Math.pow(10, Math.floor(Math.log10(max)));
  for (const m of [1, 2, 2.5, 5, 10]) if (m * step >= max) return m * step;
  return max;
}

/**
 * Vertical bars, stacked when a column has several values.
 * columns: [{ label, values: [{ value, color }] }]; labelEvery shows every n-th x label.
 */
export function BarChart({ columns, height = 160, labelEvery = 1, annotate = false, ariaLabel }) {
  const left = 26, bottom = 18, top = annotate ? 14 : 6;
  const plotH = height - bottom - top;
  const max = niceMax(Math.max(0, ...columns.map((c) => c.values.reduce((s, v) => s + v.value, 0))));
  const ticks = max <= 4 ? [...Array(max + 1).keys()] : [0, max / 2, max];
  const slot = (W - left) / columns.length;
  const barW = Math.max(4, Math.min(28, slot * 0.6));
  const y = (v) => top + plotH - (v / max) * plotH;
  return html`<svg class="chart" viewBox=${`0 0 ${W} ${height}`} role="img" aria-label=${ariaLabel}>
    ${ticks.map((t) => html`<line class="grid" x1=${left} x2=${W} y1=${y(t)} y2=${y(t)} />
      <text x=${left - 6} y=${y(t) + 4} text-anchor="end">${Math.round(t * 10) / 10}</text>`)}
    ${columns.map((c, i) => {
      const x = left + slot * i + (slot - barW) / 2;
      let base = 0;
      const total = c.values.reduce((s, v) => s + v.value, 0);
      return html`<g>
        ${c.values.map((v) => {
          const y0 = y(base), y1 = y(base + v.value);
          base += v.value;
          return v.value > 0 ? html`<rect x=${x} y=${y1} width=${barW} height=${y0 - y1} rx="2" fill=${v.color}><title>${c.label}: ${v.value}</title></rect>` : null;
        })}
        ${annotate && total > 0 ? html`<text x=${x + barW / 2} y=${y(total) - 3} text-anchor="middle">${total}</text>` : null}
        ${i % labelEvery === 0 ? html`<text x=${x + barW / 2} y=${height - 4} text-anchor="middle">${c.label}</text>` : null}
      </g>`;
    })}
  </svg>`;
}

/**
 * Lines over x = 0…xMax, y = 0…1 shown as percentages.
 * series: [{ color, points: [[x, y]], fill }]; marker: { x, label, color } draws a vertical rule.
 */
export function LineChart({ series, xMax, height = 180, yTicks = [0, 0.25, 0.5, 0.75, 1], xLabel, marker, ariaLabel }) {
  const left = 34, bottom = xLabel ? 30 : 18, top = marker ? 14 : 6, right = 6;
  const plotW = W - left - right, plotH = height - bottom - top;
  const x = (v) => left + (v / xMax) * plotW;
  const y = (v) => top + plotH - v * plotH;
  const xTicks = [0, 0.25, 0.5, 0.75, 1].map((f) => Math.round(f * xMax));
  return html`<svg class="chart" viewBox=${`0 0 ${W} ${height}`} role="img" aria-label=${ariaLabel}>
    ${yTicks.map((t) => html`<line class="grid" x1=${left} x2=${W - right} y1=${y(t)} y2=${y(t)} />
      <text x=${left - 6} y=${y(t) + 4} text-anchor="end">${Math.round(t * 100)}%</text>`)}
    ${xTicks.map((t) => html`<text x=${x(t)} y=${top + plotH + 14} text-anchor="middle">${t}</text>`)}
    ${xLabel ? html`<text x=${left + plotW / 2} y=${height - 2} text-anchor="middle">${xLabel}</text>` : null}
    ${series.map((s) => {
      const d = s.points.map(([px, py], i) => `${i ? "L" : "M"}${x(px).toFixed(1)},${y(py).toFixed(1)}`).join("");
      return html`<g>
        ${s.fill ? html`<path d=${`${d}L${x(s.points.at(-1)[0])},${y(0)}L${x(s.points[0][0])},${y(0)}Z`} fill=${s.color} opacity="0.1" />` : null}
        <path d=${d} fill="none" stroke=${s.color} stroke-width="2" stroke-linejoin="round" stroke-linecap="round" />
      </g>`;
    })}
    ${marker ? html`<line x1=${x(marker.x)} x2=${x(marker.x)} y1=${top} y2=${top + plotH} stroke=${marker.color} stroke-width="1.5" />
      <text x=${x(marker.x) + 3} y=${top - 3} style=${{ fill: marker.color }}>${marker.label}</text>` : null}
  </svg>`;
}
