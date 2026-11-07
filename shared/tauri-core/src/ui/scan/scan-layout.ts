/**
 * The scan's measures, as the Mac's `ScanOverlay` places them: the ring sits 10 under the window's centre, never
 * shorter than 80, under a heading 110 tall from 90 down and over the cards' half height; the rays are 55% at 1.2,
 * the light on a working ray is 3 round with a glow of 8, and the pulse rings fade from 45% while scanning to 12% once
 * found. The orb is 62% of the 200 ring, and the scan reads as found a beat after the last card lands. Leaving, it
 * grows to 1.03 and blurs 6; the totals rise 24 into place. A plain module, so test/design-tokens reads it in node.
 */
export const SCAN_LAYOUT = {
  centreDrop: 10,
  ringLeast: 80,
  headingTop: 90,
  headingHeight: 110,
  headingGap: 50,
  cardHalf: 100,
  summaryBottom: 70,
  rayOpacity: 0.55,
  rayWidth: 1.2,
  lightRadius: 3,
  lightGlow: 8,
  ringScanning: 0.45,
  ringFound: 0.12,
  orbDiameter: 200 * 0.62,
  foundAfterMs: 600,
  closeSlackMs: 50,
  leavingScale: 1.03,
  leavingBlur: 6,
  summaryDrop: 24,
  logo: 36,
} as const;
