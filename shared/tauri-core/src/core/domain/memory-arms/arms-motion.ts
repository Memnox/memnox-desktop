import type { Vec2 } from "./arms-shape";

/** The timing of the ARMS map's motion, kept pure so a test can read every curve. */

export function clamp01(value: number): number {
  return value < 0 ? 0 : value > 1 ? 1 : value;
}

export function smoothstep(value: number): number {
  const t = clamp01(value);
  return t * t * (3 - 2 * t);
}

export function easeOutCubic(value: number): number {
  const t = clamp01(value);
  return 1 - (1 - t) ** 3;
}

export function easeInOutCubic(value: number): number {
  const t = clamp01(value);
  return t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2;
}

/** How far past its mark a tile overshoots before it settles. */
const OVERSHOOT = 1.9;

export function easeOutBack(value: number): number {
  const t = clamp01(value);
  const back = OVERSHOOT + 1;
  return 1 + back * (t - 1) ** 3 + OVERSHOOT * (t - 1) ** 2;
}

/** The opening, in seconds at speed one: each layer has its own window inside it. */
export const OPENING = {
  total: 2.5,
  skill: [0, 0.8],
  memory: [0.35, 1.6],
  rule: [1.1, 2.0],
  app: [1.65, 2.5],
} as const;

export type OpeningLayer = Exclude<keyof typeof OPENING, "total">;

/** How far one layer's opening has run, from 0 to 1, at `t` seconds in. */
export function openingOf(layer: OpeningLayer, t: number): number {
  const [from, to] = OPENING[layer];
  return clamp01((t - from) / (to - from));
}

/** One step of a damped spring, which is what makes zoom and Fit land rather than snap. */
export type Spring = { value: number; velocity: number };

const STIFFNESS = 170;
const DAMPING = 24;
/** Under these the spring is at rest and the loop may sleep. */
const REST = { gap: 1e-4, velocity: 1e-3 } as const;

export function springStep(spring: Spring, target: number, dt: number): Spring {
  const force = STIFFNESS * (target - spring.value) - DAMPING * spring.velocity;
  const velocity = spring.velocity + force * dt;
  return { value: spring.value + velocity * dt, velocity };
}

export function springAtRest(spring: Spring, target: number): boolean {
  return Math.abs(target - spring.value) < REST.gap && Math.abs(spring.velocity) < REST.velocity;
}

/** One value eased towards another at `rate` per second, frame rate independent. */
export function approach(value: number, target: number, rate: number, dt: number): number {
  return value + (target - value) * (1 - Math.exp(-rate * dt));
}

/** A point along a smooth path through every stop, by Catmull Rom, at `t` from 0 to 1. */
export function alongPath(stops: readonly Vec2[], t: number): Vec2 {
  if (stops.length === 0) return { x: 0, y: 0 };
  if (stops.length === 1) return stops[0]!;
  const legs = stops.length - 1;
  const at = clamp01(t) * legs;
  const leg = Math.min(legs - 1, Math.floor(at));
  const u = at - leg;
  const p0 = stops[Math.max(0, leg - 1)]!;
  const p1 = stops[leg]!;
  const p2 = stops[leg + 1]!;
  const p3 = stops[Math.min(legs, leg + 2)]!;
  const blend = (a: number, b: number, c: number, d: number) =>
    0.5 * (2 * b + (-a + c) * u + (2 * a - 5 * b + 4 * c - d) * u * u + (-a + 3 * b - 3 * c + d) * u * u * u);
  return { x: blend(p0.x, p1.x, p2.x, p3.x), y: blend(p0.y, p1.y, p2.y, p3.y) };
}

/** How often the heartbeat leaves the core, and how long it takes to reach the outside. */
export const HEARTBEAT = { every: 4.6, travel: 1.8 } as const;

/** Where the heartbeat's front is, as a share of the outline, or undefined between beats. */
export function heartbeatAt(t: number): number | undefined {
  const into = t % HEARTBEAT.every;
  return into > HEARTBEAT.travel ? undefined : easeOutCubic(into / HEARTBEAT.travel) * 1.25;
}

/** How long an arrival takes to travel from its app to the core, and how much trail it keeps. */
export const PARTICLE = { life: 2.2, trail: 14 } as const;
