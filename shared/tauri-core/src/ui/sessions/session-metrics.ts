/**
 * The session windows' measures that layout logic computes with, each the Mac's own constant, in a plain module so
 * test/design-tokens.test.ts can hold them to the Swift.
 */

/** The tab the panel folds into, as the Mac's `SideMotion`: a sliver at rest, fuller under the pointer. */
export const SIDE_TAB = {
  resting: { width: 6, height: 64 },
  hovering: { width: 12, height: 96 },
  /** How far past the tab the pointer still counts as on it, since the edge is easy to overshoot. */
  slop: 8,
  /** Long enough that sweeping past the edge to reach a scroll bar does not open it. */
  dwellMs: 250,
  /** How long the pointer may be away from the open panel before it folds back into the tab. */
  graceMs: 450,
} as const;

/** `SideView`'s shape: the flare where it meets the screen's left edge, its right side's radius and the room inside it. */
export const SIDE_SHAPE = { flare: 14, radius: 22, padding: 10 } as const;

/** The card wall: each card `CardPanel.width` wide, `CardWall.gap` between them. */
export const WALL = { cardWidth: 440, gap: 16 } as const;
