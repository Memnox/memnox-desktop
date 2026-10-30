// The console's own arithmetic, from memnox-client apps/app/lib/surface-world/forces.ts, so both maps settle alike.
import { EPSILON, roomFor, type Placed } from './surface-geometry';

/**
 * The forces that settle a drawing: marks push apart so a name is readable,
 * lines pull what they join, and the middle gathers everything in.
 *
 * **Nothing here is random.** The same record seeds the same places and every
 * step is arithmetic on the last, so a map settles into the same picture every
 * time it is opened.
 */

/** What the forces are set to, named for what they do to the picture. */
export type Forces = {
  /** How hard two marks push each other away. */
  repel: number;
  /** How long a line wants to be. */
  link: number;
  /** How strongly the whole drawing is held together. */
  gather: number;
};

export const FORCES: Forces = { repel: 1, link: 1, gather: 1 };
export const FORCE_RANGE = { min: 0.2, max: 2.4 } as const;

/** One body the simulation moves, which is a node and how fast it is going. */
export type Body = { id: string; x: number; y: number; vx: number; vy: number };

type Room = { rx: number; ry: number };

/** The room assumed for a body whose node is not on the map. */
const FALLBACK_ROOM: Room = { rx: 20, ry: 20 };
/** How far apart two marks sit once nothing is pushing, over their own room. */
const BREATH = 1.25;
/** How hard two marks shove when they are actually touching. */
const CONTACT = 1;
/** How far a mark is felt by one it is not touching, in world pixels. */
const REACH = 900;
/** How hard it pushes at that distance, which is what opens the drawing out. */
const AFAR = 26000;
/** What a line settles to, in world pixels, before the knob moves it. */
const LINK_LENGTH = 128;
/** How hard a line pulls, as a share of the gap it closes each step. */
const LINK_PULL = 0.05;
/** How hard the middle pulls, so a drawing with no lines is still one drawing. */
const GATHER_PULL = 0.0023;
/**
 * How tall the gathered drawing is against how wide. The middle pulls harder
 * from above and below, so it settles as a wide ellipse: the shape of the
 * frame, and of a name written across it.
 */
const OVAL = 0.82;
/** How much speed survives a step, which is what makes it settle rather than ring. */
const DAMPING = 0.72;
/** The furthest anything may travel in one step, so nothing is flung off. */
const FASTEST = 34;
/** Each of a touching pair takes half the shove. */
const SHOVE_SHARE = 0.5;
/** Where exactly overlapping marks are pushed apart: the earlier one goes left. */
const OVERLAP_PUSH = { x: -1, y: 0 } as const;
/** Below this, nothing is moving enough to be worth another frame. */
export const STILL = 0.05;

/**
 * How much of its settling a drawing has left, from 1 to nothing.
 *
 * **This is what stops the marks shivering.** Every force is scaled by it, so
 * the arrangement converges and stops dead. It is wound back up only when
 * something changes: a node arrives, a knob moves, or a mark is picked up.
 */
export const HEAT = { full: 1, fade: 0.035, spent: 0.005, stirred: 0.35 } as const;

function roomsOf(
  bodies: Body[],
  nodes: ReadonlyMap<string, Placed>,
  sized: number,
): Map<string, Room> {
  const rooms = new Map<string, Room>();
  for (const body of bodies) {
    const node = nodes.get(body.id);
    rooms.set(body.id, node === undefined ? FALLBACK_ROOM : roomFor(node, sized));
  }
  return rooms;
}

/** Moves a pair apart by the same impulse in opposite directions. */
function pushApart(
  first: Body,
  second: Body,
  impulseX: number,
  impulseY: number,
): void {
  first.vx -= impulseX;
  first.vy -= impulseY;
  second.vx += impulseX;
  second.vy += impulseY;
}

/**
 * One pair's push. **Touching and merely near are two different forces**:
 * touching is measured in the pair's own room, so a wide card clears across
 * and a tall one down, while the far field is plain distance, or the widest
 * label would decide the shape of the whole drawing.
 */
function repelPair(
  first: Body,
  second: Body,
  rooms: Map<string, Room>,
  repel: number,
  heat: number,
): void {
  const dx = second.x - first.x;
  const dy = second.y - first.y;
  const firstRoom = rooms.get(first.id) as Room;
  const secondRoom = rooms.get(second.id) as Room;
  const need = {
    x: (firstRoom.rx + secondRoom.rx) * BREATH,
    y: (firstRoom.ry + secondRoom.ry) * BREATH,
  };
  const off = { x: dx / need.x, y: dy / need.y };
  const apart = Math.hypot(off.x, off.y);
  if (apart < 1) {
    const push =
      apart < EPSILON ? OVERLAP_PUSH : { x: off.x / apart, y: off.y / apart };
    const shove = (1 - apart) * CONTACT * repel * heat;
    pushApart(
      first,
      second,
      push.x * shove * need.x * SHOVE_SHARE,
      push.y * shove * need.y * SHOVE_SHARE,
    );
    return;
  }
  const span = Math.hypot(dx, dy);
  if (span > REACH || span < EPSILON) return;
  const far = ((AFAR / (span * span)) * repel * heat) / span;
  pushApart(first, second, dx * far, dy * far);
}

/* Every pair, which is fine at tens of nodes: a quadtree would be a second
   thing to get right for a saving nobody can perceive. */
function repelAll(
  bodies: Body[],
  rooms: Map<string, Room>,
  repel: number,
  heat: number,
): void {
  for (let one = 0; one < bodies.length; one += 1) {
    for (let two = one + 1; two < bodies.length; two += 1) {
      repelPair(bodies[one] as Body, bodies[two] as Body, rooms, repel, heat);
    }
  }
}

function pullLinks(
  bodies: Body[],
  links: readonly { from: string; to: string }[],
  linkScale: number,
  heat: number,
): void {
  const byId = new Map(bodies.map((body) => [body.id, body] as const));
  const want = LINK_LENGTH * linkScale;
  for (const link of links) {
    const from = byId.get(link.from);
    const to = byId.get(link.to);
    if (from === undefined || to === undefined) continue;
    const dx = to.x - from.x;
    const dy = to.y - from.y;
    const span = Math.hypot(dx, dy);
    if (span < EPSILON) continue;
    const pull = ((span - want) / span) * LINK_PULL * heat;
    pushApart(from, to, -dx * pull, -dy * pull);
  }
}

/** Gathers, damps, caps and moves every body; answers the fastest speed. */
function integrate(
  bodies: Body[],
  gatherScale: number,
  heat: number,
  pinned: string | undefined,
): number {
  const gather = GATHER_PULL * gatherScale * heat;
  let fastest = 0;
  for (const body of bodies) {
    if (body.id === pinned) {
      body.vx = 0;
      body.vy = 0;
      continue;
    }
    body.vx = (body.vx - body.x * gather) * DAMPING;
    body.vy = (body.vy - (body.y / (OVAL * OVAL)) * gather) * DAMPING;
    const speed = Math.hypot(body.vx, body.vy);
    if (speed > FASTEST) {
      body.vx = (body.vx / speed) * FASTEST;
      body.vy = (body.vy / speed) * FASTEST;
    }
    body.x += body.vx;
    body.y += body.vy;
    fastest = Math.max(fastest, Math.min(speed, FASTEST));
  }
  return fastest;
}

/**
 * One step of the simulation, in place. Answers how fast the fastest body is
 * going, which is what tells the loop it can stop.
 */
export function step(
  bodies: Body[],
  nodes: ReadonlyMap<string, Placed>,
  links: readonly { from: string; to: string }[],
  sized: number,
  forces: Forces,
  pinned?: string,
  heat = 1,
): number {
  const rooms = roomsOf(bodies, nodes, sized);
  repelAll(bodies, rooms, forces.repel, heat);
  pullLinks(bodies, links, forces.link, heat);
  return integrate(bodies, forces.gather, heat, pinned);
}
