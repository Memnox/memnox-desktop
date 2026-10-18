import { notchPath } from '../../core';

/**
 * The island's black outline: an SVG path from the core's `notchPath`, redrawn each frame from the
 * animated size and radius, so the quadratic bottom corners stay exact while it grows. `width` is the
 * whole shape with both flares. The shadow deepens when open, as the Mac lifts an open island.
 */
export function NotchShape({
  width,
  height,
  flare,
  bottomRadius,
  open,
  className,
}: {
  width: number;
  height: number;
  flare: number;
  bottomRadius: number;
  open: boolean;
  className?: string;
}) {
  return (
    <svg
      className={className}
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      // CALayer's radius 18 shadow reads close to a CSS blur of 18 with the same 8 drop.
      style={{ overflow: 'visible', filter: `drop-shadow(0 8px 18px rgb(0 0 0 / ${open ? 0.45 : 0.2}))` }}
      aria-hidden
    >
      <path d={notchPath(width, height, flare, bottomRadius)} fill="#000" />
    </svg>
  );
}

/** The same outline as a CSS clip path, for a box that must be cut to the shape rather than drawn under it. */
export function notchClipPath(width: number, height: number, flare: number, bottomRadius: number): string {
  return `path('${notchPath(width, height, flare, bottomRadius)}')`;
}
