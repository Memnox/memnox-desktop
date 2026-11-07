// The console's own arithmetic, from memnox-client apps/app/lib/surface-world/geometry.ts, so both maps settle alike.
/**
 * Where a node is and how much room it needs, in world pixels.
 *
 * One unit means the same thing across and down, so a force is a force rather
 * than an ellipse and a resize never moves a node.
 */

/** One thing placed in the world, which is all the geometry needs of it. */
export type Placed = {
  id: string;
  /** World pixels, with the origin in the middle of the drawing. */
  x: number;
  y: number;
  /**
   * 0 at the back and 1 at the front: how big it is drawn and what it stacks
   * over. Set where the node is placed and never recomputed from where it ends
   * up, or panning the map would resize every mark on it.
   */
  depth: number;
  /** How wide the mark is, in world pixels, before depth scales it. */
  width: number;
  /** How tall it is where that is not its width; absent means round or square. */
  height?: number;
  /** False where the mark writes its own name inside itself, as a card does. */
  captioned?: boolean;
  /** The name under the mark, which is the widest part of a node. */
  label: string;
};

/** How far the camera may be pushed either way, in one place. */
export const ZOOM = { min: 0.2, max: 3 } as const;
/** How big a mark may be drawn, over whatever the camera is doing. */
export const NODE_SIZE = { min: 0.7, max: 1.8 } as const;

/** How wide a name is under a mark, and how far below it sits, in pixels. */
export const NAME_PX = { wide: 112, below: 18 } as const;

/** Scale at the back of the drawing, and how much more the front adds. */
const BACK_SCALE = 0.84;
const DEPTH_SCALE_RANGE = 0.32;

/** The air left between a line's end and the mark it points at, in pixels. */
const AIR = 5;

/** Below this a direction component counts as zero, so nothing divides by it. */
export const EPSILON = 1e-6;

/** Depth alone. What somebody set on the toolbar multiplies this. */
export function scaleOf(depth: number): number {
  return BACK_SCALE + depth * DEPTH_SCALE_RANGE;
}

/** Kept inside 0 to 1, for a depth read off a place before anything moved. */
export function depthAt(value: number): number {
  return Math.min(Math.max(value, 0), 1);
}

/** Half a node's mark plus a little air, in pixels, at the size it is drawn. */
export function edgeOf(node: Placed, sized: number): number {
  return (node.width / 2) * scaleOf(node.depth) * sized + AIR;
}

/** Half of `extent` over the share of it a unit ray spends on that axis. */
function reachAlong(halfExtent: number, component: number): number {
  return Math.abs(component) < EPSILON
    ? Infinity
    : halfExtent / Math.abs(component);
}

/**
 * How far the mark reaches along one direction, from its own middle.
 *
 * A card is measured as the box it is, so a line arrives at its edge rather
 * than a card's width short of it on one axis and inside it on the other.
 */
function reachOf(
  node: Placed,
  sized: number,
  unitX: number,
  unitY: number,
): number {
  if (node.height === undefined) return edgeOf(node, sized);
  const scale = scaleOf(node.depth) * sized;
  const across = reachAlong((node.width / 2) * scale, unitX);
  const down = reachAlong((node.height / 2) * scale, unitY);
  return Math.min(across, down) + AIR;
}

/**
 * The visible part of a line: centre to centre, minus both marks.
 *
 * Null where trimming would turn the line inside out, as a node dragged on
 * top of another does.
 */
export function between(
  from: Placed,
  to: Placed,
  sized: number,
): { x1: number; y1: number; x2: number; y2: number } | null {
  const span = Math.hypot(to.x - from.x, to.y - from.y);
  if (span === 0) return null;
  const unitX = (to.x - from.x) / span;
  const unitY = (to.y - from.y) / span;
  const start = reachOf(from, sized, unitX, unitY);
  const end = reachOf(to, sized, unitX, unitY);
  if (span <= start + end) return null;
  return {
    x1: from.x + unitX * start,
    y1: from.y + unitY * start,
    x2: to.x - unitX * end,
    y2: to.y - unitY * end,
  };
}

/**
 * How much room one node needs, as half a width and half a height in world
 * pixels, name included: the name is the part that collides, so two marks a
 * comfortable distance apart can still write their names across each other.
 */
export function roomFor(
  node: Placed,
  sized: number,
): { rx: number; ry: number } {
  const scale = scaleOf(node.depth) * sized;
  const hasCaption = node.captioned !== false;
  const wide = hasCaption ? Math.max(node.width, NAME_PX.wide) : node.width;
  const tall = node.height ?? node.width;
  const below = hasCaption ? NAME_PX.below : 0;
  return { rx: (wide / 2) * scale, ry: (tall / 2) * scale + below };
}

/* ---- placing them to begin with --------------------------------------- */

/**
 * How far a ring is squashed vertically. A screen is wider than tall and a
 * name is written across, so the wide axis has room to spare. Only the seed.
 */
export const FLATTEN = 0.7;

/** Where the first node on a ring goes: straight up, then clockwise. */
export const START = -Math.PI / 2;

/** The middle of a layout written in fractions of a notional card. */
const LAYOUT_MIDDLE = 0.5;
const LAYOUT_CENTRE = { x: LAYOUT_MIDDLE, y: LAYOUT_MIDDLE } as const;

/**
 * `count` angles spread over `width`, centred on `middle`. One child sits
 * exactly on its parent's angle, so a hub with one thing under it reads as a
 * line out from the centre instead of a lean.
 */
export function fan(
  middle: number,
  width: number,
  count: number,
  whole = false,
): number[] {
  if (count === 0) return [];
  if (count === 1) return [middle];
  /* A full circle leaves no gap at the end, or the last node lands on the first. */
  const step = whole ? width / count : width / (count - 1);
  const from = whole ? middle : middle - width / 2;
  return Array.from({ length: count }, (_, index) => from + index * step);
}

/** One point on a squashed ring around a centre, with the depth it lands at. */
export function at(
  angle: number,
  radius: number,
  centre: { x: number; y: number } = LAYOUT_CENTRE,
): { x: number; y: number; depth: number } {
  const y = centre.y + Math.sin(angle) * radius * FLATTEN;
  return { x: centre.x + Math.cos(angle) * radius, y, depth: depthAt(y) };
}

/** How far a set of values sits off the layout middle, by its bounding middle. */
function offsetToMiddle(values: number[]): number {
  return LAYOUT_MIDDLE - (Math.min(...values) + Math.max(...values)) / 2;
}

/**
 * The whole drawing shifted into the middle of the box, whatever shape the
 * data gave it. Only a shift, never a squeeze: the distance between two nodes
 * is the one thing this drawing is saying.
 */
export function centred<T extends { x: number; y: number; depth: number }>(
  nodes: readonly T[],
): T[] {
  if (nodes.length === 0) return [];
  const shiftX = offsetToMiddle(nodes.map((node) => node.x));
  const shiftY = offsetToMiddle(nodes.map((node) => node.y));
  if (shiftX === 0 && shiftY === 0) return [...nodes];
  return nodes.map((node) => ({
    ...node,
    x: node.x + shiftX,
    y: node.y + shiftY,
    depth: depthAt(node.y + shiftY),
  }));
}

/** What one layout fraction is worth once it lands in the world, in pixels. */
export const WORLD = 1100;

/** A layout written in fractions, as bodies in the world. */
export function seeded<T extends Placed>(nodes: readonly T[]): T[] {
  return nodes.map((node) => ({
    ...node,
    x: (node.x - LAYOUT_MIDDLE) * WORLD,
    y: (node.y - LAYOUT_MIDDLE) * WORLD * FLATTEN,
  }));
}
