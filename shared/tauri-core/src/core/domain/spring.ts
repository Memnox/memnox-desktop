/**
 * The motion math the island moves with: SwiftUI's springs and timing curves as plain functions, so
 * the UI needs no animation library and a test can step them.
 */

/** A SwiftUI `spring(response:dampingFraction:)`. */
export interface Spring {
  readonly response: number;
  readonly damping: number;
}

/** The Mac's springs, each named for what moves with it. */
export const SPRINGS = {
  grow: { response: 0.5, damping: 0.72 },
  hover: { response: 0.28, damping: 0.6 },
  satellites: { response: 0.36, damping: 0.8 },
  satelliteSlide: { response: 0.42, damping: 0.72 },
  press: { response: 0.2, damping: 0.6 },
  notchPress: { response: 0.28, damping: 0.7 },
  notchHover: { response: 0.32, damping: 0.75 },
  tileArrival: { response: 0.38, damping: 0.78 },
  /** SwiftUI's `.snappy`: duration 0.5 with bounce 0.15. */
  snappy: { response: 0.5, damping: 0.85 },
} as const satisfies Record<string, Spring>;

/** The island shrinking: `timingCurve(0.45, 0, 0.2, 1, duration: 0.34)`. */
export const SHRINK = { x1: 0.45, y1: 0, x2: 0.2, y2: 1, seconds: 0.34 } as const;

/** Stiffness and damping per unit mass, as `(2π/response)²` and `4π·dampingFraction/response`. */
export function springConstants(spring: Spring): { stiffness: number; damping: number } {
  return {
    stiffness: ((2 * Math.PI) / spring.response) ** 2,
    damping: (4 * Math.PI * spring.damping) / spring.response,
  };
}

export interface Moving {
  readonly value: number;
  readonly velocity: number;
}

/** The longest step taken at once, so a frame that came late never flings the spring past its rest. */
const MAX_STEP_SECONDS = 1 / 120;

/** One step of a damped spring toward `target`, in substeps short enough to stay stable. */
export function springStep(now: Moving, target: number, spring: Spring, seconds: number): Moving {
  const { stiffness, damping } = springConstants(spring);
  let { value, velocity } = now;
  let left = Math.max(0, seconds);
  while (left > 0) {
    const dt = Math.min(MAX_STEP_SECONDS, left);
    const force = -stiffness * (value - target) - damping * velocity;
    velocity += force * dt;
    value += velocity * dt;
    left -= dt;
  }
  return { value, velocity };
}

/** Close enough to rest that drawing another frame shows nothing. */
export function atRest(now: Moving, target: number): boolean {
  return Math.abs(now.value - target) < 0.01 && Math.abs(now.velocity) < 0.01;
}

/** A CSS `cubic-bezier`, as progress for a share of the time, solved by Newton's method with bisection behind it. */
export function cubicBezier(x1: number, y1: number, x2: number, y2: number): (t: number) => number {
  const at = (a: number, b: number, s: number) => 3 * a * s * (1 - s) ** 2 + 3 * b * s * s * (1 - s) + s ** 3;
  const slope = (a: number, b: number, s: number) => 3 * a * (1 - s) ** 2 + 6 * (b - a) * s * (1 - s) + 3 * (1 - b) * s * s;
  return (t: number) => {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    let s = t;
    for (let i = 0; i < 8; i++) {
      const error = at(x1, x2, s) - t;
      const d = slope(x1, x2, s);
      if (Math.abs(error) < 1e-6) return at(y1, y2, s);
      if (Math.abs(d) < 1e-6) break;
      s -= error / d;
    }
    let low = 0;
    let high = 1;
    s = t;
    for (let i = 0; i < 30; i++) {
      const x = at(x1, x2, s);
      if (Math.abs(x - t) < 1e-6) break;
      if (x < t) low = s;
      else high = s;
      s = (low + high) / 2;
    }
    return at(y1, y2, s);
  };
}
