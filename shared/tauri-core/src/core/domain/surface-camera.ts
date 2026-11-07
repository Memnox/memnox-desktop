// The console's own arithmetic, from memnox-client apps/app/lib/surface-world/camera.ts, so both maps settle alike.
import { roomFor, ZOOM, type Placed } from './surface-geometry';

/**
 * What the drawing is looked at from: a world point, and how close.
 *
 * Screen = (world minus camera) times zoom, plus the frame's middle. Every
 * gesture is arithmetic on this one object, so panning never touches layout.
 */
export type Camera = { x: number; y: number; k: number };

type Point = { x: number; y: number };
type Size = { width: number; height: number };

export const AT_REST: Camera = { x: 0, y: 0, k: 1 };

/** How far the drawing is held off the edge of the frame when it is fitted. */
const MARGIN = 28;
/** Fit never draws closer than life size: marks are sized to be read as drawn. */
const MAX_FIT_ZOOM = 1;
/** The smallest box dimension fitting divides by, so a single node cannot divide by zero. */
const MIN_BOX_SIDE = 1;

/** A world point on the screen it is drawn at. */
export function onScreen(point: Point, camera: Camera, size: Size): Point {
  return {
    x: (point.x - camera.x) * camera.k + size.width / 2,
    y: (point.y - camera.y) * camera.k + size.height / 2,
  };
}

/** A point on the screen back in the world it came from. */
export function inWorld(point: Point, camera: Camera, size: Size): Point {
  return {
    x: (point.x - size.width / 2) / camera.k + camera.x,
    y: (point.y - size.height / 2) / camera.k + camera.y,
  };
}

/** The camera, zoomed about a point that stays under the pointer. */
export function zoomedAt(
  camera: Camera,
  by: number,
  pointer: Point,
  size: Size,
): Camera {
  const k = Math.min(Math.max(camera.k * by, ZOOM.min), ZOOM.max);
  if (k === camera.k) return camera;
  const held = inWorld(pointer, camera, size);
  return {
    k,
    x: held.x - (pointer.x - size.width / 2) / k,
    y: held.y - (pointer.y - size.height / 2) / k,
  };
}

/** How much room the whole drawing takes in the world, marks and names. */
export function extent(
  nodes: readonly Placed[],
  sized: number,
): { x: number; y: number; width: number; height: number } | null {
  if (nodes.length === 0) return null;
  let left = Infinity;
  let right = -Infinity;
  let top = Infinity;
  let bottom = -Infinity;
  for (const node of nodes) {
    const room = roomFor(node, sized);
    left = Math.min(left, node.x - room.rx);
    right = Math.max(right, node.x + room.rx);
    top = Math.min(top, node.y - room.ry);
    bottom = Math.max(bottom, node.y + room.ry);
  }
  return { x: left, y: top, width: right - left, height: bottom - top };
}

/* The frame less the panel's column, and never less than half of it: on a
   narrow screen the panel is most of the width. */
function roomBesidePanel(size: Size, inset: number): Size {
  return {
    width: Math.max(size.width - inset, size.width / 2) - MARGIN * 2,
    height: size.height - MARGIN * 2,
  };
}

/**
 * The camera that holds the whole drawing, which is what Fit means.
 *
 * Fitted beside the panel's column rather than under it, because a node under
 * the toolbar is the one node nobody can click.
 */
export function fitted(
  nodes: readonly Placed[],
  size: Size,
  sized: number,
  inset = 0,
): Camera {
  const box = extent(nodes, sized);
  if (box === null || size.width === 0 || size.height === 0) return AT_REST;
  const room = roomBesidePanel(size, inset);
  const k = Math.min(
    MAX_FIT_ZOOM,
    Math.max(
      ZOOM.min,
      Math.min(
        room.width / Math.max(box.width, MIN_BOX_SIDE),
        room.height / Math.max(box.height, MIN_BOX_SIDE),
      ),
    ),
  );
  /* Centred in the room it was fitted into, so the panel covers margin. */
  const middle = size.width - room.width / 2 - MARGIN;
  return {
    k,
    x: box.x + box.width / 2 - (middle - size.width / 2) / k,
    y: box.y + box.height / 2,
  };
}
