/**
 * The notch's own outline grown downward, ported from the Mac's `NotchShape`: square along the top,
 * flowing into the screen edge either side with a concave curve, and rounded at the bottom with
 * quadratic corners rather than arcs, which is why a CSS border radius is close but not the same.
 */

/** The bottom radius actually drawn, never more than half of what the shape has room for. */
export function notchRadius(width: number, height: number, flare: number, bottomRadius: number): number {
  return Math.min(bottomRadius, Math.max(0, (height - flare) / 2), Math.max(0, (width - 2 * flare) / 2));
}

/** An SVG path for a shape `width` wide, both flares included, and `height` tall, its top at y 0. */
export function notchPath(width: number, height: number, flare: number, bottomRadius: number): string {
  const r = notchRadius(width, height, flare, bottomRadius);
  const left = flare;
  const right = width - flare;
  const n = (value: number) => Number(value.toFixed(2));
  return [
    'M 0 0',
    `Q ${n(left)} 0 ${n(left)} ${n(flare)}`,
    `L ${n(left)} ${n(height - r)}`,
    `Q ${n(left)} ${n(height)} ${n(left + r)} ${n(height)}`,
    `L ${n(right - r)} ${n(height)}`,
    `Q ${n(right)} ${n(height)} ${n(right)} ${n(height - r)}`,
    `L ${n(right)} ${n(flare)}`,
    `Q ${n(right)} 0 ${n(width)} 0`,
    'Z',
  ].join(' ');
}
