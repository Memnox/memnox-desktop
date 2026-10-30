import { useEffect, useRef, useState, type RefObject } from 'react';
import { fitted, inWorld, type Camera } from '../../../core/domain/surface-camera';
import { HEAT, step, type Body, type Forces } from '../../../core/domain/surface-forces';
import { seeded, type Placed } from '../../../core/domain/surface-geometry';

/**
 * The console's flat surface hooks, from memnox-client apps/app/components/canvas/surface, kept to what
 * the desktop's map needs: the stage's size, the settling simulation, panning and dragging, and a fit
 * that follows the drawing until somebody takes the camera.
 */

/** How far the pointer may travel, in screen pixels, before a press stops being a click. */
export const A_CLICK = 4;
/** How many steps one frame takes. The settling is worth watching, not sitting through. */
const PER_FRAME = 2;
/** Camera differences too small to be worth another render. */
const SETTLED_PAN = 0.5;
const SETTLED_ZOOM = 0.002;
/** The column the controls float in, which the drawing is fitted beside. */
export const PANEL_WIDTH = 220;

type Size = { width: number; height: number };
type Point = { x: number; y: number };
type PointerAt = { clientX: number; clientY: number };

/** The stage in pixels, measured at once rather than on the observer's first frame. */
export function useStageSize(ref: RefObject<HTMLDivElement | null>): Size {
  const [size, setSize] = useState<Size>({ width: 0, height: 0 });
  useEffect(() => {
    const box = ref.current;
    if (box === null) return;
    const first = box.getBoundingClientRect();
    if (first.width > 0 && first.height > 0) setSize({ width: first.width, height: first.height });
    const watch = new ResizeObserver(([entry]) => {
      if (entry !== undefined) setSize({ width: entry.contentRect.width, height: entry.contentRect.height });
    });
    watch.observe(box);
    return () => watch.disconnect();
  }, [ref]);
  return size;
}

interface Moment {
  nodes: readonly Placed[];
  links: readonly { from: string; to: string }[];
  sized: number;
  forces: Forces;
  pinned: string | undefined;
}

/**
 * The nodes arranging themselves and settling. Deterministic, since the seed is the ring layout and
 * nothing in a step is random, and it comes to a dead stop: every force is scaled by the heat left.
 */
export function useForces(nodes: readonly Placed[], links: readonly { from: string; to: string }[], sized: number, forces: Forces, pinned: string | undefined) {
  const bodies = useRef<Body[]>([]);
  const [, redraw] = useState(0);
  const heat = useRef<number>(HEAT.full);
  const latest = useRef<Moment>({ nodes, links, sized, forces, pinned });
  latest.current = { nodes, links, sized, forces, pinned };
  const frame = useRef(0);
  bodies.current = syncedBodies(bodies.current, nodes);

  const run = useRef((_stir: number) => undefined as void);
  run.current = (stir) => {
    heat.current = Math.max(heat.current, stir);
    if (frame.current !== 0) return;
    const tick = (): void => {
      const now = latest.current;
      heat.current = advance(bodies.current, now, heat.current);
      redraw((count) => count + 1);
      if (heat.current < HEAT.spent && now.pinned === undefined) {
        for (const body of bodies.current) still(body);
        heat.current = 0;
        frame.current = 0;
        return;
      }
      frame.current = requestAnimationFrame(tick);
    };
    frame.current = requestAnimationFrame(tick);
  };

  const signature = `${nodes.map((node) => node.id).join(',')}|${links.length}|${sized}|${forces.repel},${forces.link},${forces.gather}`;
  useEffect(() => {
    run.current(HEAT.full);
    return () => {
      cancelAnimationFrame(frame.current);
      frame.current = 0;
    };
  }, [signature]);

  return {
    placed: new Map(bodies.current.map((body) => [body.id, { x: body.x, y: body.y }] as const)),
    put: (id: string, x: number, y: number) => {
      const body = bodies.current.find((each) => each.id === id);
      if (body === undefined) return;
      body.x = x;
      body.y = y;
      still(body);
      // Enough for the neighbours to make room, not enough to rearrange everything.
      run.current(HEAT.stirred);
    },
    reseed: () => {
      const places = new Map(seeded(latest.current.nodes).map((node) => [node.id, node] as const));
      for (const body of bodies.current) {
        const place = places.get(body.id);
        if (place === undefined) continue;
        body.x = place.x;
        body.y = place.y;
        still(body);
      }
      run.current(HEAT.full);
    },
  };
}

/** A body per node, seeded where the layout put it, so a new node arrives at its seed. */
function syncedBodies(current: Body[], nodes: readonly Placed[]): Body[] {
  const known = new Map(current.map((body) => [body.id, body] as const));
  const next = seeded(nodes).map((seed) => known.get(seed.id) ?? { id: seed.id, x: seed.x, y: seed.y, vx: 0, vy: 0 });
  const changed = next.length !== current.length || next.some((body, index) => body.id !== current[index]?.id);
  return changed ? next : current;
}

function advance(bodies: Body[], now: Moment, heat: number): number {
  const placed = new Map(now.nodes.map((node) => [node.id, node] as const));
  let left = heat;
  for (let pass = 0; pass < PER_FRAME; pass += 1) {
    step(bodies, placed, now.links, now.sized, now.forces, now.pinned, left);
    // No cooling while held, or the rest of the map freezes around the drag.
    if (now.pinned === undefined) left -= left * HEAT.fade;
  }
  return left;
}

function still(body: Body): void {
  body.vx = 0;
  body.vy = 0;
}

type Offset = { id: string; dx: number; dy: number };
type Grab = Offset & { along: Offset[]; from: Point; moved: boolean };
type Sweep = Point & { camera: Camera; moved: boolean };

/** Panning the ground and dragging nodes, bound to the window for as long as a drag lasts. */
export function useSurfaceGestures({
  stage,
  size,
  camera,
  setCamera,
  put,
  setHeld,
}: {
  stage: RefObject<HTMLDivElement | null>;
  size: Size;
  camera: Camera;
  setCamera: (next: Camera) => void;
  put: (id: string, x: number, y: number) => void;
  setHeld: (id: string | undefined) => void;
}) {
  const grab = useRef<Grab | undefined>(undefined);
  const sweep = useRef<Sweep | undefined>(undefined);
  /** True once somebody has taken the camera, so it stops following the fit. */
  const own = useRef(false);
  const [panning, setPanning] = useState(false);
  const eye = useRef(camera);
  eye.current = camera;
  const putLatest = useRef(put);
  putLatest.current = put;

  const onStage = (event: PointerAt): Point | undefined => {
    const box = stage.current?.getBoundingClientRect();
    if (box === undefined) return undefined;
    return { x: event.clientX - box.left, y: event.clientY - box.top };
  };

  useEffect(() => {
    const panBy = (pan: Sweep, on: Point): void => {
      const by = { x: on.x - pan.x, y: on.y - pan.y };
      if (Math.hypot(by.x, by.y) > A_CLICK) {
        pan.moved = true;
        own.current = true;
      }
      setCamera({ k: pan.camera.k, x: pan.camera.x - by.x / pan.camera.k, y: pan.camera.y - by.y / pan.camera.k });
    };
    const dragTo = (drag: Grab, on: Point): void => {
      const point = inWorld(on, eye.current, size);
      if (Math.hypot(point.x - drag.from.x, point.y - drag.from.y) > A_CLICK / eye.current.k) drag.moved = true;
      // A hand that trembles while clicking is not a drag, and must not stir the map.
      if (!drag.moved) return;
      putLatest.current(drag.id, point.x + drag.dx, point.y + drag.dy);
      for (const each of drag.along) putLatest.current(each.id, point.x + each.dx, point.y + each.dy);
    };
    const move = (event: PointerEvent): void => {
      const on = onStage(event);
      if (on === undefined) return;
      if (sweep.current !== undefined) panBy(sweep.current, on);
      else if (grab.current !== undefined) dragTo(grab.current, on);
    };
    const drop = (): void => {
      sweep.current = undefined;
      setPanning(false);
      setHeld(undefined);
      // A tick late, so the click that follows can still ask whether this was a drag.
      window.setTimeout(() => {
        grab.current = undefined;
      }, 0);
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', drop);
    window.addEventListener('pointercancel', drop);
    return () => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', drop);
      window.removeEventListener('pointercancel', drop);
    };
  }, [size.width, size.height]);

  return {
    panning,
    own,
    startPan: (event: PointerAt): void => {
      const on = onStage(event);
      if (on === undefined) return;
      sweep.current = { ...on, camera, moved: false };
      setPanning(true);
    },
    holdNode: (id: string, event: PointerAt, at: ReadonlyMap<string, Placed>, carried: readonly string[]): void => {
      const on = onStage(event);
      const from = at.get(id);
      if (on === undefined || from === undefined) return;
      const point = inWorld(on, eye.current, size);
      sweep.current = undefined;
      setPanning(false);
      setHeld(id);
      grab.current = {
        id,
        dx: from.x - point.x,
        dy: from.y - point.y,
        along: carried.flatMap((other) => {
          const each = at.get(other);
          return each === undefined ? [] : [{ id: other, dx: each.x - point.x, dy: each.y - point.y }];
        }),
        from: point,
        moved: false,
      };
    },
    wasDrag: (): boolean => grab.current?.moved === true,
    wasPan: (): boolean => sweep.current?.moved === true,
  };
}

/** Keeps the drawing fitted while it settles, until somebody takes the camera or picks a node. */
export function useFollowFit({
  own,
  selected,
  placed,
  size,
  nodeSize,
  camera,
  setCamera,
}: {
  own: RefObject<boolean>;
  selected: string | undefined;
  placed: readonly Placed[];
  size: Size;
  nodeSize: number;
  camera: Camera;
  setCamera: (next: Camera) => void;
}): void {
  useEffect(() => {
    if (own.current || selected !== undefined || size.width === 0 || placed.length === 0) return;
    const want = fitted(placed, size, nodeSize, PANEL_WIDTH);
    const there = Math.abs(want.x - camera.x) < SETTLED_PAN && Math.abs(want.y - camera.y) < SETTLED_PAN && Math.abs(want.k - camera.k) < SETTLED_ZOOM;
    if (!there) setCamera(want);
  });
}
