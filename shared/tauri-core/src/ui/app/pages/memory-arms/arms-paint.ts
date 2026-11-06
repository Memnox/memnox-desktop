import type { ArmsEngine } from "./arms-engine";
import { faceInk, initialsFor } from "../../../../core/domain/memory-arms/arms-faces";
import { ARMS_INK } from "../../../../core/domain/memory-arms/arms-ink";
import { appTile, badge, chip, curve, face, fillDots, glow, markIn, particle, ruleMark, starPath, strokeShare, type DotBucket } from "./arms-draw";
import { TIMELINE } from "../../../../core/domain/memory-arms/arms-lanes";
import { ageChip } from "../../../../core/domain/memory-arms/arms-model";
import { alongPath, clamp01, easeInOutCubic, easeOutBack, easeOutCubic, heartbeatAt, openingOf, PARTICLE, smoothstep } from "../../../../core/domain/memory-arms/arms-motion";
import { paintLabels } from "./arms-paint-labels";
import { DUST_CORE, DUST_OUTLINE } from "../../../../core/domain/memory-arms/arms-scene";

/**
 * One frame of the ARMS map, back to front: dust, spokes, rules ring, lit
 * links, pieces, tiles, hubs, arrivals, names. Every mark's size grows with
 * the square root of the zoom while distances grow with the zoom itself, so
 * zooming in opens space between marks rather than only enlarging them.
 */

/** Alpha is drawn in this many steps, so the dust stays one fill per colour and step. */
const ALPHA_STEPS = 8;
const RING_SAMPLES = 180;
const ORIGIN = { x: 0, y: 0 };
/** How far a spoke bows, as a share of its length. */
const SPOKE_BEND = 0.16;
/** A halo's reach against its mark: small for a piece, larger for a hub. */
const HALO = { piece: 1.8, hub: 3 } as const;
/** A cluster this full or more draws its halos at their faintest, so a dense one is not a blot. */
const DENSE = 36;
/** A search dims what it does not match to this. */
const DIMMED = 0.18;
const buckets: DotBucket[] = [];
const ringXY: number[] = [];

/** Each item's alpha, scale and depth this frame; the names read the alpha so a hidden mark is never labelled. */
export let shownAlpha = new Float32Array(0);
let scales = new Float32Array(0);
let depths = new Float32Array(0);

function phases(engine: ArmsEngine) {
  if (engine.props.reduced) {
    const all = smoothstep(engine.opening / 0.8);
    return { skill: all, memory: all, rule: all, app: all };
  }
  const t = engine.opening;
  return { skill: openingOf("skill", t), memory: openingOf("memory", t), rule: openingOf("rule", t), app: openingOf("app", t) };
}

export type Open = ReturnType<typeof phases>;

export function paintFrame(engine: ArmsEngine): void {
  const { pen, width, height } = engine;
  const { ctx } = pen;
  ctx.clearRect(0, 0, width, height);
  if (engine.model.empty) return;
  const count = engine.model.items.length;
  if (shownAlpha.length !== count) {
    shownAlpha = new Float32Array(count);
    scales = new Float32Array(count);
    depths = new Float32Array(count);
  }
  const fade = engine.props.reduced ? smoothstep(engine.fade) : 1;
  ctx.globalAlpha = fade;
  const open = phases(engine);
  if (engine.model.core !== undefined) {
    const core = engine.at(0, 0, 0, ORIGIN);
    glow(pen, core.x, core.y, engine.unit * engine.cam.k.value * engine.model.rings.envelope * 0.9, ARMS_INK.glow, 0.06 * open.memory);
  }
  const front = engine.props.motion && !engine.props.reduced && engine.props.mode !== "timeline" ? heartbeatAt(engine.clock) : undefined;
  paintDots(engine, open.memory, front);
  placeItems(engine, open);
  paintSpokes(engine, open);
  paintRules(engine, open.rule);
  paintLinks(engine);
  paintItems(engine, open);
  paintParticles(engine);
  paintLabels(engine, open);
  ctx.globalAlpha = 1;
}

function bucketFor(index: number, ink: string, alpha: number): DotBucket {
  const bucket = buckets[index] ?? { ink, alpha, xy: [], size: [] };
  buckets[index] = bucket;
  bucket.ink = ink;
  bucket.alpha = alpha;
  return bucket;
}

/** The ink one dust kind is drawn in: the outline's muted, the centre's star, a cluster's own. */
function dustInk(engine: ArmsEngine, kind: number): string {
  if (kind === DUST_OUTLINE) return ARMS_INK.muted;
  if (kind === DUST_CORE) return ARMS_INK.star;
  return engine.model.sectors[kind]?.ink ?? ARMS_INK.muted;
}

function paintDots(engine: ArmsEngine, reveal: number, front: number | undefined): void {
  const { dots, model, sectorLight, props } = engine;
  const kinds = model.sectors.length + 2;
  for (let kind = 0; kind < kinds; kind += 1) {
    for (let step = 0; step < ALPHA_STEPS; step += 1) {
      const bucket = bucketFor(kind * ALPHA_STEPS + step, dustInk(engine, kind - 2), (step + 1) / ALPHA_STEPS);
      bucket.xy.length = 0;
      bucket.size.length = 0;
    }
  }
  const timeline = engine.timelineWeight;
  const zoom = Math.sqrt(engine.cam.k.value);
  const line = { x: 0, y: 0 };
  const searching = props.matches.size > 0 ? 0.4 : 1;
  for (let at = 0; at < dots.count; at += 1) {
    const f = dots.f[at]!;
    const kind = dots.cluster[at]!;
    line.x = dots.lineX[at]!;
    line.y = dots.lineY[at]!;
    const p = engine.at(dots.theta[at]!, f, dots.phi[at]!, line);
    if (p.x < -4 || p.y < -4 || p.x > engine.width + 4 || p.y > engine.height + 4) continue;
    const shown = smoothstep((reveal * 1.25 - f / 0.9) * 4);
    const twinkle = props.motion && !props.reduced ? 0.62 + 0.38 * Math.sin(engine.clock * dots.rate[at]! * Math.PI * 2 + dots.phase[at]!) : 0.85;
    const beat = front === undefined ? 1 : 1 + 1.6 * Math.exp(-(((f - front) / 0.05) ** 2));
    const light = kind >= 0 ? (sectorLight[kind] ?? 1) : kind === DUST_OUTLINE ? 0.5 : 0.8;
    const fog = props.mode === "orbs" || engine.morph < 1 ? 0.22 + 0.78 * p.depth : 1;
    const alpha = 0.55 * shown * twinkle * beat * light * fog * searching * (1 - 0.7 * timeline);
    if (alpha < 0.02) continue;
    const step = Math.min(ALPHA_STEPS - 1, Math.floor(alpha * ALPHA_STEPS));
    const bucket = buckets[(kind + 2) * ALPHA_STEPS + step]!;
    bucket.xy.push(p.x, p.y);
    bucket.size.push(1.4 * p.scale * zoom * (beat > 1.4 ? 1.35 : 1));
  }
  fillDots(engine.pen, buckets.slice(0, kinds * ALPHA_STEPS));
}

/** How far one item has grown out of its hub in the opening, from 0 at the hub to 1 at its spot. */
function growth(engine: ArmsEngine, open: Open, at: number): number {
  const item = engine.model.items[at]!;
  if (item.parent === undefined || engine.props.mode === "timeline") return 1;
  if (item.layer === "skill") return easeOutCubic(open.skill);
  const sector = engine.model.sectors.findIndex((each) => each.key === item.sector);
  const stagger = Math.max(0, sector) * 0.06;
  const hubDelay = item.hub === true ? 0 : 0.2;
  return easeOutCubic(clamp01((open.memory - stagger - hubDelay) / 0.55));
}

/** Every item's screen place this frame, each grown out of its parent's, which the spokes and names read. */
function placeItems(engine: ArmsEngine, open: Open): void {
  const { model } = engine;
  for (let at = 0; at < model.items.length; at += 1) {
    const item = model.items[at]!;
    const line = engine.timeline.places.get(item.id) ?? ORIGIN;
    const p = engine.atItem(item, at, line);
    const grown = growth(engine, open, at);
    const parent = item.parent === undefined ? undefined : engine.index.get(item.parent);
    /* Parents come before their children in the model, so a parent's place is already this frame's. */
    if (parent !== undefined && grown < 1) {
      engine.sx[at] = engine.sx[parent]! + (p.x - engine.sx[parent]!) * grown;
      engine.sy[at] = engine.sy[parent]! + (p.y - engine.sy[parent]!) * grown;
    } else {
      engine.sx[at] = p.x;
      engine.sy[at] = p.y;
    }
    scales[at] = p.scale;
    depths[at] = p.depth;
  }
}

/** The centre's coloured spokes out to every area's hub, and each hub's faint threads to what it holds. */
function paintSpokes(engine: ArmsEngine, open: Open): void {
  const { model, pen, props } = engine;
  const { ctx } = pen;
  const fade = 1 - engine.timelineWeight;
  if (fade <= 0) return;
  const core = engine.index.get(coreIdOf(engine));
  const searching = props.matches.size > 0 ? 0.35 : 1;
  model.sectors.forEach((sector, at) => {
    const hub = engine.index.get(sector.hubId);
    if (hub === undefined) return;
    const light = engine.sectorLight[at] ?? 1;
    const hx = engine.sx[hub]!;
    const hy = engine.sy[hub]!;
    if (core !== undefined) {
      ctx.beginPath();
      curve(ctx, engine.sx[core]!, engine.sy[core]!, hx, hy, SPOKE_BEND);
      ctx.lineWidth = 1.4;
      ctx.strokeStyle = pen.paint(sector.ink, 0.42 * open.memory * light * fade * searching);
      ctx.stroke();
    }
    const thread = 0.1 * Math.min(1, 30 / Math.max(1, sector.count)) * light * fade * searching * open.memory;
    if (thread < 0.01) return;
    ctx.beginPath();
    model.items.forEach((item, index) => {
      if (item.parent !== sector.hubId || item.hub === true) return;
      ctx.moveTo(hx, hy);
      ctx.lineTo(engine.sx[index]!, engine.sy[index]!);
    });
    ctx.lineWidth = 0.8;
    ctx.strokeStyle = pen.paint(sector.ink, thread);
    ctx.stroke();
  });
}

function coreIdOf(engine: ArmsEngine): string {
  return engine.model.items.find((item) => item.core === true)?.id ?? "";
}

function paintRules(engine: ArmsEngine, drawn: number): void {
  if (drawn <= 0 || !engine.model.items.some((item) => item.layer === "rule")) return;
  ringXY.length = 0;
  for (let at = 0; at <= RING_SAMPLES; at += 1) {
    const share = at / RING_SAMPLES;
    const p = engine.at(Math.PI / 2 + share * Math.PI * 2, engine.model.rings.rules, 0, { x: TIMELINE.left + share * (TIMELINE.right - TIMELINE.left), y: 0.54 });
    ringXY.push(p.x, p.y);
  }
  const pen = engine.pen;
  const searching = engine.props.matches.size > 0 ? 0.4 : 1;
  strokeShare(pen, ringXY, easeInOutCubic(drawn), ARMS_INK.gold, 0.18 * searching, 6, true);
  strokeShare(pen, ringXY, easeInOutCubic(drawn), ARMS_INK.gold, 0.7 * searching, 1.2, true);
}

/** The hovered or picked mark's own lines, curved out to each neighbour it lights. */
function paintLinks(engine: ArmsEngine): void {
  const { model, links, pen } = engine;
  const lit = engine.hover >= 0 ? engine.hover : (engine.index.get(engine.props.selected ?? "") ?? -1);
  const item = model.items[lit];
  if (item === undefined) return;
  const strength = engine.lit[lit] ?? 0;
  const { ctx } = pen;
  ctx.lineWidth = 1.2;
  ctx.strokeStyle = pen.paint(ARMS_INK.glow, 0.6 * strength);
  ctx.beginPath();
  for (const other of links.get(item.id) ?? []) {
    const at = engine.index.get(other);
    if (at === undefined) continue;
    curve(ctx, engine.sx[lit]!, engine.sy[lit]!, engine.sx[at]!, engine.sy[at]!, SPOKE_BEND);
  }
  ctx.stroke();
}

type Passable = { layer: string; hub?: boolean };

/** Pieces first, then rules, skills and tiles, and the hubs over all of them so their marks sit on top. */
const PASSES: readonly ((item: Passable) => boolean)[] = [
  (item) => item.layer === "memory" && item.hub !== true,
  (item) => item.layer === "rule",
  (item) => item.layer === "skill" && item.hub !== true,
  (item) => item.layer === "app",
  (item) => item.hub === true,
];

function paintItems(engine: ArmsEngine, open: Open): void {
  const { model, pen, props } = engine;
  const { ctx } = pen;
  const sectorIndex = new Map(model.sectors.map((sector, at) => [sector.key, at]));
  const searching = props.matches.size > 0;
  const live = props.motion && !props.reduced;
  const k = Math.sqrt(engine.cam.k.value);
  const now = Date.now();
  const ink = { ground: ARMS_INK.ground, glow: ARMS_INK.glow, text: ARMS_INK.ink, gold: ARMS_INK.gold };
  for (const pass of PASSES) {
    model.items.forEach((item, at) => {
      if (!pass(item)) return;
      const x = engine.sx[at]!;
      const y = engine.sy[at]!;
      const scale = scales[at] ?? 1;
      const lit = engine.lit[at]!;
      const fog = props.mode === "orbs" ? 0.3 + 0.7 * (depths[at] ?? 1) : 1;
      const matched = props.matches.has(item.id);
      const dim = searching && !matched ? DIMMED : 1;
      const sector = sectorIndex.get(item.sector ?? "") ?? -1;
      const light = sector < 0 ? 1 : (engine.sectorLight[sector] ?? 1);
      const color = model.sectors[sector]?.ink ?? ARMS_INK.muted;
      let r: number;
      let alpha: number;
      if (item.layer === "memory" && item.hub === true) {
        alpha = smoothstep(growth(engine, open, at) * 3) * light * fog * dim;
        r = (8 + 2 * lit) * scale * k;
        glow(pen, x, y, r * HALO.hub, color, (0.2 + 0.4 * lit) * alpha);
        ctx.beginPath();
        ctx.arc(x, y, r, 0, Math.PI * 2);
        ctx.fillStyle = pen.paint(ARMS_INK.ground, alpha);
        ctx.fill();
        ctx.lineWidth = 2;
        ctx.strokeStyle = pen.paint(color, alpha);
        ctx.stroke();
        const mark = engine.imageOf(item.logo);
        if (mark !== undefined) markIn(pen, x, y, r * 0.72, mark, alpha);
        else {
          ctx.beginPath();
          ctx.arc(x, y, r * 0.42, 0, Math.PI * 2);
          ctx.fillStyle = pen.paint(color, alpha);
          ctx.fill();
        }
      } else if (item.layer === "memory") {
        alpha = smoothstep(growth(engine, open, at) * 2) * light * fog * dim;
        const crowd = model.sectors[sector]?.count ?? 1;
        const isPerson = item.kind === "person" || item.kind === "group";
        const mark = engine.imageOf(item.logo);
        r = (isPerson || mark !== undefined ? 3.6 + 2 * lit : 2.4 + 2.2 * lit) * scale * k;
        const halo = Math.max(0.3, Math.min(1, Math.sqrt(DENSE / Math.max(1, crowd))));
        glow(pen, x, y, r * HALO.piece * 2, color, 0.5 * lit * alpha * halo);
        if (isPerson) {
          face(pen, x, y, r, engine.imageOf(item.picture), initialsFor(item.label), faceInk(item.label), alpha, ARMS_INK.ground);
        } else if (mark !== undefined && r >= 4) {
          ctx.beginPath();
          ctx.arc(x, y, r, 0, Math.PI * 2);
          ctx.fillStyle = pen.paint(ARMS_INK.ground, alpha);
          ctx.fill();
          ctx.lineWidth = 1;
          ctx.strokeStyle = pen.paint(color, alpha);
          ctx.stroke();
          markIn(pen, x, y, r * 0.78, mark, alpha);
        } else {
          ctx.fillStyle = pen.paint(color, Math.min(1, 0.95 * alpha));
          ctx.beginPath();
          ctx.arc(x, y, r, 0, Math.PI * 2);
          ctx.fill();
        }
      } else if (item.layer === "skill") {
        const local = clamp01((open.skill - (item.hub === true ? 0 : 0.035 * (at % 12))) / 0.58);
        const shimmer = live ? 1 + 0.12 * Math.sin(engine.clock * 2.4 + at * 1.7) : 1;
        r = (item.core === true ? 13 : 6) * easeOutBack(local) * shimmer * scale * k * (1 + 0.3 * lit);
        alpha = smoothstep(local * 2) * fog * dim;
        glow(pen, x, y, r * (item.core === true ? HALO.hub : HALO.piece), ARMS_INK.star, (0.16 + 0.5 * (1 - local) + 0.3 * lit) * dim * smoothstep(local * 3));
        starPath(ctx, x, y, r);
        ctx.fillStyle = pen.paint(ARMS_INK.star, alpha);
        ctx.fill();
      } else if (item.layer === "rule") {
        const share = ((((item.theta - Math.PI / 2) / (Math.PI * 2)) % 1) + 1) % 1;
        alpha = smoothstep((easeInOutCubic(open.rule) * 1.1 - share) * 12) * fog * dim;
        r = (4.5 + 1.5 * lit) * scale * k;
        glow(pen, x, y, r * HALO.hub, ARMS_INK.gold, 0.45 * lit * alpha);
        ruleMark(pen, x, y, r, item.effect, alpha, ink);
      } else {
        const local = clamp01((open.app * 1.1 - (at % 7) * 0.05) / 0.55);
        const drop = (1 - easeOutBack(local)) * 26;
        r = 14 * scale * k * (1 + 0.12 * lit);
        alpha = smoothstep(local * 2) * fog * dim;
        appTile(pen, x, y - drop, r, engine.imageOf(item.logo), item.label.slice(0, 1).toUpperCase(), alpha, lit, ink);
        if (item.number !== undefined) badge(pen, x + r * 0.74, y - drop - r * 0.74, String(item.number), alpha, { fill: ARMS_INK.glow, text: ARMS_INK.onGlow });
        if (item.lastUsed !== undefined) chip(pen, x, y - drop + r + 3, ageChip(item.lastUsed, now), alpha, { ground: ARMS_INK.ground, border: ARMS_INK.border, text: ARMS_INK.muted });
      }
      engine.sr[at] = Math.max(item.layer === "memory" && item.hub !== true ? 6 : 9, r);
      shownAlpha[at] = alpha;
      if (matched && alpha > 0.05) {
        ctx.beginPath();
        ctx.arc(x, y, r + 4, 0, Math.PI * 2);
        ctx.lineWidth = 1.6;
        ctx.strokeStyle = pen.paint(ARMS_INK.glow, 0.9);
        ctx.stroke();
      }
    });
  }
}

function paintParticles(engine: ArmsEngine): void {
  const { rings } = engine.model;
  for (const each of engine.particles) {
    const item = engine.model.items[each.item];
    if (item === undefined) continue;
    const progress = clamp01((engine.elapsed - each.start) / PARTICLE.life);
    const app = engine.model.items[each.app];
    const start = app === undefined ? engine.at(item.theta, rings.apps, item.phi, ORIGIN) : { x: engine.sx[each.app]!, y: engine.sy[each.app]! };
    const ring = engine.at(app?.theta ?? item.theta, rings.rules, item.phi, ORIGIN);
    const stops = [start, ring, { x: engine.sx[each.item]!, y: engine.sy[each.item]! }, engine.at(0, 0, 0, ORIGIN)];
    const head = alongPath(stops, easeInOutCubic(progress));
    each.trail.push(head.x, head.y);
    if (each.trail.length > PARTICLE.trail * 2) each.trail.splice(0, 2);
    particle(engine.pen, each.trail, ARMS_INK.pulse, Math.min(1, (1 - progress) * 3));
    if (progress > 0.55 && progress < 0.62) engine.lit[each.item] = 1;
  }
}
