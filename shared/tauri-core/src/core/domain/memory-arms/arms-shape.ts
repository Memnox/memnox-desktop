import { hashOf } from "./arms-node";

/**
 * The brain silhouette the ARMS map is drawn on, as plain arithmetic: a side
 * view with the front to the right, measured in brain units where the outline
 * is about two and a half across. Every layer is the same outline scaled
 * towards the middle, so a band follows the brain rather than a circle.
 */

export type Vec2 = { x: number; y: number };
export type Vec3 = { x: number; y: number; z: number };

/** The ellipse the bumps sit on, wider than tall as a brain is from the side. */
const BASE = { rx: 1.22, ry: 0.86 } as const;

/** Each bump: the angle it peaks at, how wide it is, and how far it lifts the outline. */
const BUMPS: readonly { at: number; width: number; lift: number }[] = [
  { at: 0.35, width: 0.55, lift: 0.1 },
  { at: 1.45, width: 0.7, lift: 0.07 },
  { at: 2.55, width: 0.5, lift: 0.08 },
  { at: -2.75, width: 0.28, lift: -0.12 },
  { at: -2.25, width: 0.42, lift: 0.07 },
  { at: -1.25, width: 0.5, lift: -0.15 },
  { at: -0.45, width: 0.4, lift: 0.04 },
];

/**
 * The centre's share of the outline, and the furthest out the rules ring and
 * the app tiles can sit; a brain with less in it wraps them nearer in.
 */
export const LAYER_AT = {
  core: 0.2,
  rules: 0.98,
  apps: 1.22,
} as const;

/** Samples round the outline, enough that a lookup is smoother than a pixel. */
const SAMPLES = 1024;
const TAU = Math.PI * 2;

/** The signed gap between two angles, folded into one turn either way. */
export function angleGap(from: number, to: number): number {
  const gap = (((to - from) % TAU) + TAU * 1.5) % TAU;
  return gap - Math.PI;
}

/** The outline's distance scale at one angle, before the ellipse is applied. */
function liftAt(theta: number): number {
  let lift = 1;
  for (const bump of BUMPS) {
    const gap = angleGap(bump.at, theta) / bump.width;
    lift += bump.lift * Math.exp(-gap * gap);
  }
  return lift;
}

const TABLE: Vec2[] = Array.from({ length: SAMPLES + 1 }, (_, index) => {
  const theta = (index / SAMPLES) * TAU;
  const lift = liftAt(theta);
  return {
    x: Math.cos(theta) * BASE.rx * lift,
    y: Math.sin(theta) * BASE.ry * lift,
  };
});

/** One point on the outline, read off the table and blended between samples. */
export function outlineAt(theta: number): Vec2 {
  const turn = (((theta % TAU) + TAU) % TAU) / TAU;
  const at = turn * SAMPLES;
  const low = Math.floor(at);
  const share = at - low;
  const a = TABLE[low] ?? TABLE[0]!;
  const b = TABLE[low + 1] ?? TABLE[0]!;
  return { x: a.x + (b.x - a.x) * share, y: a.y + (b.y - a.y) * share };
}

/** A point on the layer `f` of the outline: 0 is the middle, 1 the outline itself. */
export function brainPoint(theta: number, f: number): Vec2 {
  const edge = outlineAt(theta);
  return { x: edge.x * f, y: edge.y * f };
}

/** How far the shells are pressed across, so a revolved outline reads as a brain and not an egg. */
const SHELL_DEPTH = 0.78;

/** The same point on a brain shaped shell in depth: the outline turned about its long axis by `phi`. */
export function shellPoint(theta: number, f: number, phi: number): Vec3 {
  const flat = brainPoint(theta, f);
  return {
    x: flat.x,
    y: flat.y * Math.cos(phi),
    z: flat.y * Math.sin(phi) * SHELL_DEPTH,
  };
}

/** How far the eye stands from the middle, in brain units; nearer is a stronger perspective. */
export const EYE_DISTANCE = 4.2;

export type Projected = { x: number; y: number; scale: number; depth: number };

/** A point turned by yaw and pitch and seen in perspective; `depth` runs from far (0) to near (1). */
export function project(point: Vec3, yaw: number, pitch: number): Projected {
  const cy = Math.cos(yaw);
  const sy = Math.sin(yaw);
  const x1 = point.x * cy + point.z * sy;
  const z1 = -point.x * sy + point.z * cy;
  const cp = Math.cos(pitch);
  const sp = Math.sin(pitch);
  const y2 = point.y * cp - z1 * sp;
  const z2 = point.y * sp + z1 * cp;
  const scale = EYE_DISTANCE / (EYE_DISTANCE - z2);
  const reach = LAYER_AT.apps * BASE.rx * 1.2;
  const depth = Math.min(1, Math.max(0, (z2 + reach) / (reach * 2)));
  return { x: x1 * scale, y: y2 * scale, scale, depth };
}

/** A stable number from 0 to 1 for an id and a salt, so a place never changes between loads. */
export function unitOf(id: string, salt: string): number {
  return hashOf(`${salt}:${id}`) / 0x1_0000_0000;
}

/** The widest the drawing reaches, in brain units, which Fit measures against. */
export const REACH = { x: BASE.rx * LAYER_AT.apps * 1.18, y: BASE.ry * LAYER_AT.apps * 1.3 } as const;

/** The angle and layer share a flat point sits at, the inverse of `brainPoint`. */
export function layerOfPoint(point: Vec2): { theta: number; f: number } {
  const theta = Math.atan2(point.y / BASE.ry, point.x / BASE.rx);
  const edge = outlineAt(theta);
  return { theta, f: Math.hypot(point.x, point.y) / Math.max(1e-6, Math.hypot(edge.x, edge.y)) };
}

/** The outline's length from the angle 0 to each sample, so a ring can be spaced by distance rather than by angle. */
const ARC: number[] = TABLE.reduce<number[]>((out, point, index) => {
  const before = TABLE[index - 1];
  out.push(before === undefined ? 0 : out[index - 1]! + Math.hypot(point.x - before.x, point.y - before.y));
  return out;
}, []);

/** The whole outline's length at share one; at share `f` it is `f` times this. */
export const OUTLINE_LENGTH = ARC[SAMPLES]!;

/** The area inside the outline at share one, by the shoelace sum; at share `f` it is `f` squared times this. */
export const OUTLINE_AREA = Math.abs(
  TABLE.slice(0, SAMPLES).reduce((sum, point, index) => {
    const next = TABLE[(index + 1) % SAMPLES]!;
    return sum + point.x * next.y - next.x * point.y;
  }, 0) / 2,
);

/** How far along the outline an angle is, as a share of its length from 0 to under 1. */
export function arcShareOf(theta: number): number {
  const turn = (((theta % TAU) + TAU) % TAU) / TAU;
  const at = turn * SAMPLES;
  const low = Math.floor(at);
  const a = ARC[low] ?? 0;
  const b = ARC[low + 1] ?? OUTLINE_LENGTH;
  return (a + (b - a) * (at - low)) / OUTLINE_LENGTH;
}

/** The angle that lies a share of the outline's length along it, the inverse of `arcShareOf`. */
export function thetaAtArcShare(share: number): number {
  const want = (((share % 1) + 1) % 1) * OUTLINE_LENGTH;
  let low = 0;
  let high = SAMPLES;
  while (high - low > 1) {
    const middle = (low + high) >> 1;
    if (ARC[middle]! <= want) low = middle;
    else high = middle;
  }
  const a = ARC[low]!;
  const b = ARC[low + 1] ?? OUTLINE_LENGTH;
  const into = b === a ? 0 : (want - a) / (b - a);
  return ((low + into) / SAMPLES) * TAU;
}

/** `count` angles an equal distance apart round the outline, the first at `start`. */
export function arcSpaced(count: number, start: number): number[] {
  const from = arcShareOf(start);
  return Array.from({ length: count }, (_, index) => thetaAtArcShare(from + index / Math.max(1, count)));
}
