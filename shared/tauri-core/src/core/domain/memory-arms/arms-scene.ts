import { seededRandom } from "./arms-node";

import { SALT, stableUnit } from "./arms-hash";
import type { ArmsModel, ArmsSector } from "./arms-model";
import { TIMELINE } from "./arms-lanes";
import { brainPoint, layerOfPoint, project, shellPoint, type Projected, type Vec2 } from "./arms-shape";

/**
 * Where everything stands in each of the three views, in brain units. The
 * dust is texture rather than records, so it is counted apart from the items
 * and never offered as something to open or search; it lies only inside the
 * clusters that exist and along the outline that wraps them, so an empty
 * brain has none.
 */

export const ARMS_MODES = ["brain", "orbs", "timeline"] as const;
export type ArmsMode = (typeof ARMS_MODES)[number];

/** The dust's own kinds beside the clusters: the outline and the centre. */
export const DUST_OUTLINE = -1;
export const DUST_CORE = -2;

export type Dots = {
  count: number;
  theta: Float32Array;
  f: Float32Array;
  phi: Float32Array;
  phase: Float32Array;
  rate: Float32Array;
  /** The cluster a mote belongs to, or one of the two dust kinds. */
  cluster: Int16Array;
  /** Where the mote rests in the timeline, laid along its axis. */
  lineX: Float32Array;
  lineY: Float32Array;
};

/** How far a mote strays from the outline, so the outline reads dotted rather than drawn. */
const OUTLINE_JITTER = 0.012;
/** The share of the dust that draws the outline; the rest fills the clusters by their area. */
const OUTLINE_SHARE = 0.2;
/** Twinkle rates in turns a second, slow enough to read as breathing. */
const TWINKLE = { slowest: 0.25, fastest: 0.9 } as const;
/** How far a cluster's dust turns in depth about its own, as its pieces do. */
const DUST_DEPTH = 0.5;

function emptyDots(count: number): Dots {
  return {
    count,
    theta: new Float32Array(count),
    f: new Float32Array(count),
    phi: new Float32Array(count),
    phase: new Float32Array(count),
    rate: new Float32Array(count),
    cluster: new Int16Array(count),
    lineX: new Float32Array(count),
    lineY: new Float32Array(count),
  };
}

/** The dust for one model, at most `budget` motes: none at all when the brain is empty. */
export function makeDots(model: ArmsModel, budget: number, seed: number): Dots {
  if (model.empty || (model.sectors.length === 0 && model.core === undefined)) return emptyDots(0);
  const random = seededRandom(seed);
  const discs = [
    ...(model.core === undefined ? [] : [{ kind: DUST_CORE, x: model.core.x, y: model.core.y, r: model.core.r, depth: 0 }]),
    ...model.sectors.map((sector, index) => ({ kind: index, x: sector.x, y: sector.y, r: sector.r, depth: stableUnit(sector.key, SALT.latitude) * Math.PI })),
  ];
  const area = discs.reduce((sum, disc) => sum + disc.r * disc.r, 0);
  const outline = Math.round(budget * OUTLINE_SHARE);
  const shares = discs.map((disc) => Math.round(((budget - outline) * disc.r * disc.r) / Math.max(1e-6, area)));
  const dots = emptyDots(outline + shares.reduce((sum, each) => sum + each, 0));
  let at = 0;
  const finish = () => {
    dots.phase[at] = random() * Math.PI * 2;
    dots.rate[at] = TWINKLE.slowest + random() * (TWINKLE.fastest - TWINKLE.slowest);
    dots.lineX[at] = TIMELINE.left + random() * (TIMELINE.right - TIMELINE.left);
    dots.lineY[at] = TIMELINE.axis + (random() * 2 - 1) * 0.03;
    at += 1;
  };
  for (let index = 0; index < outline; index += 1) {
    dots.cluster[at] = DUST_OUTLINE;
    dots.theta[at] = random() * Math.PI * 2;
    dots.f[at] = model.rings.envelope + (random() * 2 - 1) * OUTLINE_JITTER;
    dots.phi[at] = random() * Math.PI;
    finish();
  }
  discs.forEach((disc, index) => {
    for (let mote = 0; mote < shares[index]!; mote += 1) {
      const angle = random() * Math.PI * 2;
      const reach = disc.r * Math.sqrt(random());
      const spot = layerOfPoint({ x: disc.x + Math.cos(angle) * reach, y: disc.y + Math.sin(angle) * reach });
      dots.cluster[at] = disc.kind;
      dots.theta[at] = spot.theta;
      dots.f[at] = spot.f;
      dots.phi[at] = disc.depth + (random() - 0.5) * DUST_DEPTH;
      finish();
    }
  });
  return dots;
}

/** The cluster a flat point falls in, or -1 outside every one. */
export function sectorOfPoint(sectors: readonly ArmsSector[], point: Vec2): number {
  return sectors.findIndex((sector) => Math.hypot(point.x - sector.x, point.y - sector.y) <= sector.r);
}

export type View = { yaw: number; pitch: number };

/** One point's place in one view, with how near and how large it is drawn there. */
export function place(mode: ArmsMode, theta: number, f: number, phi: number, line: Vec2, view: View): Projected {
  if (mode === "orbs") return project(shellPoint(theta, f, phi), view.yaw, view.pitch);
  if (mode === "timeline") return { x: line.x, y: line.y, scale: 1, depth: 1 };
  const flat = brainPoint(theta, f);
  return { x: flat.x, y: flat.y, scale: 1, depth: 1 };
}

/** Two places blended for a morph, so a view change moves every dot rather than cutting. */
export function blend(from: Projected, to: Projected, t: number): Projected {
  return {
    x: from.x + (to.x - from.x) * t,
    y: from.y + (to.y - from.y) * t,
    scale: from.scale + (to.scale - from.scale) * t,
    depth: from.depth + (to.depth - from.depth) * t,
  };
}
