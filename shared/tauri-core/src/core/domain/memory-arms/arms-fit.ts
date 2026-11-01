import type { Vec2 } from "./arms-shape";

/**
 * Fit, measured against what is drawn rather than against the silhouette:
 * the camera centres on the bounds of the marks and zooms until they fill
 * the frame, so a brain of three things is not a speck in the middle.
 */

export const ZOOM = { least: 0.45, most: 12 } as const;

/** The share of the frame the marks may fill, so a tile at the edge keeps its name on screen. */
const FILL = { across: 0.84, down: 0.76 } as const;
/** Room round the bounds, in brain units, for a mark's own size and the label under it. */
const PAD = 0.14;
/** A brain whose bounds are a point is shown at this span rather than at infinite zoom. */
const LEAST_SPAN = 0.6;

export type Camera = { x: number; y: number; k: number };

export function fitTo(points: readonly Vec2[], frame: { width: number; height: number; unit: number }): Camera {
  if (points.length === 0 || frame.unit <= 0) return { x: 0, y: 0, k: 1 };
  let left = Number.POSITIVE_INFINITY;
  let right = Number.NEGATIVE_INFINITY;
  let low = Number.POSITIVE_INFINITY;
  let high = Number.NEGATIVE_INFINITY;
  for (const point of points) {
    left = Math.min(left, point.x);
    right = Math.max(right, point.x);
    low = Math.min(low, point.y);
    high = Math.max(high, point.y);
  }
  const across = Math.max(LEAST_SPAN, right - left + PAD * 2);
  const down = Math.max(LEAST_SPAN, high - low + PAD * 2);
  const k = Math.min((frame.width * FILL.across) / (across * frame.unit), (frame.height * FILL.down) / (down * frame.unit));
  return { x: (left + right) / 2, y: (low + high) / 2, k: Math.min(ZOOM.most, Math.max(ZOOM.least, k)) };
}
