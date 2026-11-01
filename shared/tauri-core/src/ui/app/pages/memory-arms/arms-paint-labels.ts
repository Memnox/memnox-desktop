import type { ArmsEngine } from "./arms-engine";
import { ARMS_INK } from "../../../../core/domain/memory-arms/arms-ink";
import { haloLabel, plainLabel, spacedCaps, spacedWidth, strokeShare } from "./arms-draw";
import { clipped, placeLabels, type LabelBox } from "../../../../core/domain/memory-arms/arms-labels";
import { TIMELINE } from "../../../../core/domain/memory-arms/arms-lanes";
import { smoothstep } from "../../../../core/domain/memory-arms/arms-motion";
import { shownAlpha, type Open } from "./arms-paint";
import { layerOfPoint } from "../../../../core/domain/memory-arms/arms-shape";

/**
 * The words on the ARMS map: a caption for each layer that exists, the names
 * of the marks placed greedily so none lies over another, and the timeline's
 * axis with a caption for each undated row. The hovered name always shows.
 */

const TOP = Math.PI / 2;
const ORIGIN = { x: 0, y: 0 };
const LINE_HEIGHT = 13;
/** The longest a name is drawn before it is cut. */
const MOST_LETTERS = 28;
/** Below this zoom a piece's name is left for the hover card, since a whole brain of names is noise. */
const PIECE_NAMES_FROM = 1.6;
const FONT = { hub: "600 11px", piece: "500 10px" } as const;
/** How strongly each kind of mark holds its name against another's. */
const WEIGHT = { core: 10_000, hub: 5_000, app: 3_000, skill: 2_000, rule: 1_500, piece: 100, lit: 20_000 } as const;

export function paintLabels(engine: ArmsEngine, open: Open): void {
  const pen = engine.pen;
  const timeline = engine.timelineWeight;
  const captions = captionsOf(engine, open, timeline);
  const boxes: LabelBox[] = captions.map((caption) => caption.box);
  const texts = new Map<string, { text: string; font: string; x: number; top: number; ink: string; alpha: number }>();
  const { model, props } = engine;
  const zoom = engine.cam.k.value;
  model.items.forEach((item, at) => {
    const alpha = shownAlpha[at] ?? 0;
    const lit = engine.lit[at] ?? 0;
    const hovered = at === engine.hover;
    const matched = props.matches.has(item.id);
    if (!hovered && alpha < 0.3) return;
    const piece = item.hub !== true && item.layer === "memory";
    if (piece && !hovered && !matched && lit < 0.05 && zoom < PIECE_NAMES_FROM) return;
    const x = engine.sx[at]!;
    const y = engine.sy[at]!;
    if (x < -40 || y < -40 || x > engine.width + 40 || y > engine.height + 40) return;
    const font = `${item.hub === true ? FONT.hub : FONT.piece} ${pen.family}`;
    const name = clipped(item.label, MOST_LETTERS);
    const text = item.hub === true && item.core !== true && item.holds !== undefined ? `${name} · ${item.holds}` : name;
    const width = widthOf(engine, font, text);
    const below = (engine.sr[at] ?? 6) + (item.layer === "app" && item.lastUsed !== undefined ? 19 : 4);
    const top = y + below;
    const weight =
      (item.core === true ? WEIGHT.core : item.hub === true ? WEIGHT.hub + (item.holds ?? 0) : item.layer === "app" ? WEIGHT.app : item.layer === "skill" ? WEIGHT.skill : item.layer === "rule" ? WEIGHT.rule : WEIGHT.piece) +
      (lit > 0.05 || matched ? WEIGHT.lit : 0);
    boxes.push({ id: item.id, left: x - width / 2, top, width, height: LINE_HEIGHT, weight, ...(hovered ? { always: true } : {}) });
    texts.set(item.id, { text, font, x, top, ink: item.hub === true || lit > 0.05 ? ARMS_INK.ink : ARMS_INK.muted, alpha: hovered ? 1 : Math.max(alpha, lit) });
  });
  const shown = placeLabels(boxes);
  for (const caption of captions) caption.draw();
  for (const [id, label] of texts) {
    if (!shown.has(id)) continue;
    haloLabel(pen, label.text, label.x, label.top, label.font, label.ink, ARMS_INK.ground, label.alpha);
  }
  if (timeline > 0) paintAxis(engine, timeline);
}

function widthOf(engine: ArmsEngine, font: string, text: string): number {
  const key = `${font}|${text}`;
  const known = engine.widths.get(key);
  if (known !== undefined) return known;
  engine.pen.ctx.font = font;
  const width = engine.pen.ctx.measureText(text).width;
  engine.widths.set(key, width);
  return width;
}

/** The layer captions, only for the layers the brain holds, each held clear of every name. */
function captionsOf(engine: ArmsEngine, open: Open, timeline: number): { box: LabelBox; draw: () => void }[] {
  const { model } = engine;
  const has = (layer: string) => model.items.some((item) => item.layer === layer && item.core !== true);
  const coreShare = model.core === undefined ? 0 : layerOfPoint({ x: 0, y: model.core.r + 0.05 }).f;
  const layers = [
    { text: "Skills", f: coreShare, phase: open.skill, lane: -0.62, present: has("skill") },
    { text: "Memory", f: model.rings.envelope + 0.035, phase: open.memory, lane: 0.38, present: model.sectors.length > 0 },
    { text: "Rules", f: model.rings.rules + 0.045, phase: open.rule, lane: 0.67, present: has("rule") },
    { text: "Applications", f: model.rings.apps + 0.13, phase: open.app, lane: 0.97, present: has("app") },
  ];
  const out: { box: LabelBox; draw: () => void }[] = [];
  for (const layer of layers) {
    if (!layer.present) continue;
    const shown = smoothstep(layer.phase * 2);
    const brain = engine.at(TOP, layer.f, 0, ORIGIN);
    const lane = engine.at(0, 0, 0, { x: TIMELINE.left + 0.2, y: layer.lane });
    const x = brain.x + (lane.x - brain.x) * timeline;
    const y = brain.y + (lane.y - brain.y) * timeline;
    const width = spacedWidth(engine.pen, layer.text);
    out.push({
      box: { id: `caption:${layer.text}`, left: x - width / 2, top: y - 6, width, height: 12, weight: 0, always: true },
      draw: () => spacedCaps(engine.pen, layer.text, x, y, ARMS_INK.muted, 0.85 * shown),
    });
  }
  return out;
}

function dateOf(time: number): string {
  return new Date(time).toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" });
}

function paintAxis(engine: ArmsEngine, weight: number): void {
  const pen = engine.pen;
  const left = engine.at(0, 0, 0, { x: TIMELINE.left, y: TIMELINE.axis });
  const right = engine.at(0, 0, 0, { x: TIMELINE.right, y: TIMELINE.axis });
  strokeShare(pen, [left.x, left.y, right.x, right.y], 1, ARMS_INK.border, weight, 1, false);
  const { first, last, undated } = engine.timeline;
  if (first !== undefined) plainLabel(pen, dateOf(first), left.x, left.y + 8, ARMS_INK.muted, weight, "left");
  if (last !== undefined && last !== first) plainLabel(pen, dateOf(last), right.x, right.y + 8, ARMS_INK.muted, weight, "right");
  for (const row of undated) {
    const at = engine.at(0, 0, 0, { x: TIMELINE.left, y: row.y });
    plainLabel(pen, "Undated", at.x - 8, at.y - 6, ARMS_INK.muted, 0.8 * weight, "right");
  }
}
