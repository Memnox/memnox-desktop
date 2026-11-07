import type { Vec2 } from "./arms-pack";

/**
 * The brain taken apart and put back together on a loop, the Mac's `BrainTour` value for value: **everything is a
 * function of one playhead**, so the pose of every layer, the camera's push and the turntable come from one time in
 * seconds and scrubbing works both ways. The core spreads, each area slides out from the core as a petal, the rules
 * ring telescopes out and unscrews, the applications fly out, then every mark flies apart and snaps back.
 */

export const TOUR_PARTS = ["assembled", "core", "areas", "rules", "applications", "teardown", "reassembly"] as const;
export type TourPart = (typeof TOUR_PARTS)[number];

export type TourSection = { start: number; part: TourPart };

/** How far open each assembly is, from 0 in place to 1 fully out, with the camera's push as times the fit and the extra turn. */
export type TourPose = { core: number; areas: number; rules: number; applications: number; apart: number; zoom: number; turn: number };

/** The layer a mark is opened with: the core's skills, an area's memory, the ring's rules, the outside's applications. */
export type TourLayer = "skill" | "memory" | "rule" | "app";

export const ASSEMBLED: TourPose = { core: 0, areas: 0, rules: 0, applications: 0, apart: 0, zoom: 1, turn: 0 };

/** One loop of the tour, in seconds. */
export const TOUR_LENGTH = 25;

export const TOUR_SECTIONS: readonly TourSection[] = [
  { start: 0, part: "assembled" },
  { start: 2.4, part: "core" },
  { start: 6, part: "areas" },
  { start: 10.2, part: "rules" },
  { start: 13.6, part: "applications" },
  { start: 16.8, part: "teardown" },
  { start: 20.6, part: "reassembly" },
  { start: 22.6, part: "assembled" },
];

type Track = readonly (readonly [number, number])[];

/** Each assembly's keys, seconds against how far open: opened once alone, then all at once in the teardown. */
const CORE: Track = [[2.6, 0], [3.6, 1], [5.4, 1], [6.2, 0], [17, 0], [18.2, 1], [20.8, 1], [22.2, 0]];
const AREAS: Track = [[6.2, 0], [7.4, 1], [9.6, 1], [10.4, 0], [17, 0], [18.2, 1], [20.8, 1], [22.2, 0]];
const RULES: Track = [[10.4, 0], [11.4, 1], [13, 1], [13.8, 0], [17, 0], [18.2, 1], [20.8, 1], [22.2, 0]];
const APPLICATIONS: Track = [[13.8, 0], [14.8, 1], [16.2, 1], [17, 0], [18.2, 1], [20.8, 1], [22.2, 0]];
const APART: Track = [[16.9, 0], [18.4, 1], [20.6, 1], [22.2, 0]];
/** The camera pushes in on the core, stands back for the petals and the ring, and further back for the teardown. */
const ZOOM: Track = [[0, 1], [2.6, 1], [3.6, 1.6], [5.4, 1.6], [6.4, 0.86], [9.6, 0.86], [10.4, 0.82], [13.8, 0.8], [16.8, 0.8], [17.8, 0.7], [21, 0.7], [22.6, 1]];
/** The turntable: one whole turn through the teardown, landing before the parts are home. */
const TURN: Track = [[16.9, 0], [21.6, 2 * Math.PI]];

/** The Mac's brain runs 480 points from its middle to its front and this one 1.22 brain units, so a Mac point is this many units. */
const MAC_POINT = 1.22 / 480;

/** How far each assembly travels at full open: spreads and reaches as times where they sit, slides and flights in brain units. */
export const TOUR_REACH = {
  coreSpread: 1.4,
  areaSlide: 150 * MAC_POINT,
  ringOut: 0.32,
  ringTwist: 0.7,
  tilesOut: 0.42,
  flightLeast: 60 * MAC_POINT,
  flightMore: 150 * MAC_POINT,
} as const;
/** A teardown's sideways stray, as a share of its flight, so the marks do not all fly on rays from the core. */
const STRAY = 0.35;
/** The brain's middle, which every assembly opens away from. */
const MIDDLE: Vec2 = { x: 0, y: 0 };
/** A mark's own fraction, spread by its index so no id is hashed in a frame. */
const GOLDEN_SHARE = 0.618_033_988_749_895;

/** The playhead a tour started a while ago stands at, wrapped onto the loop. */
export function playhead(seconds: number): number {
  const wrapped = seconds % TOUR_LENGTH;
  return wrapped < 0 ? wrapped + TOUR_LENGTH : wrapped;
}

export function sectionAt(seconds: number): TourSection {
  const at = playhead(seconds);
  return [...TOUR_SECTIONS].reverse().find((section) => section.start <= at) ?? TOUR_SECTIONS[0]!;
}

/** Which stretch it is, counted from one, for the deck's count. */
export function sectionNumber(seconds: number): number {
  const at = playhead(seconds);
  let found = 0;
  TOUR_SECTIONS.forEach((section, index) => {
    if (section.start <= at) found = index;
  });
  return found + 1;
}

export function poseAt(seconds: number): TourPose {
  const at = playhead(seconds);
  return {
    core: sample(CORE, at),
    areas: sample(AREAS, at),
    rules: sample(RULES, at),
    applications: sample(APPLICATIONS, at),
    apart: sample(APART, at),
    zoom: sample(ZOOM, at),
    turn: sample(TURN, at),
  };
}

export function isAssembled(pose: TourPose): boolean {
  return pose.core === 0 && pose.areas === 0 && pose.rules === 0 && pose.applications === 0 && pose.apart === 0 && pose.zoom === 1 && pose.turn === 0;
}

/** A track at a moment: its first value before its first key, its last after its last, eased between. */
export function sample(keys: Track, at: number): number {
  const first = keys[0];
  if (first === undefined) return 0;
  if (at <= first[0]) return first[1];
  for (let index = 1; index < keys.length; index += 1) {
    const before = keys[index - 1]!;
    const after = keys[index]!;
    if (at > after[0]) continue;
    if (after[0] <= before[0]) return after[1];
    const share = (at - before[0]) / (after[0] - before[0]);
    return before[1] + (after[1] - before[1]) * share * share * (3 - 2 * share);
  }
  return keys[keys.length - 1]![1];
}

/** A mark's own seed for the teardown, from its index. */
export function tourSeed(index: number): number {
  return (index * GOLDEN_SHARE) % 1;
}

/**
 * Where a flat mark stands with its assembly opened: the core's spread from the middle, an area's slid out with its
 * hub, the ring pushed out and turned, the tiles pushed out, then the teardown's flight on top. `seed` runs 0 to 1.
 */
export function opened(spot: Vec2, layer: TourLayer, area: Vec2 | undefined, seed: number, pose: TourPose): Vec2 {
  let at = spot;
  switch (layer) {
    case "skill":
      at = scaled(at, 1 + TOUR_REACH.coreSpread * pose.core);
      break;
    case "memory":
      if (area !== undefined) {
        const out = unit(MIDDLE, area);
        at = { x: at.x + out.x * TOUR_REACH.areaSlide * pose.areas, y: at.y + out.y * TOUR_REACH.areaSlide * pose.areas };
      }
      break;
    case "rule":
      at = turned(scaled(at, 1 + TOUR_REACH.ringOut * pose.rules), TOUR_REACH.ringTwist * pose.rules);
      break;
    case "app":
      at = scaled(at, 1 + TOUR_REACH.tilesOut * pose.applications);
      break;
  }
  return scattered(at, seed, pose.apart);
}

/** A spot flown out on its own line in the teardown: away from the middle, a little to one side, further for some marks. */
export function scattered(spot: Vec2, seed: number, apart: number): Vec2 {
  if (apart <= 0) return spot;
  const out = unit(MIDDLE, spot, seed * 2 * Math.PI);
  const flight = (TOUR_REACH.flightLeast + TOUR_REACH.flightMore * seed) * apart;
  const side = (seed - 0.5) * 2 * STRAY * flight;
  return { x: spot.x + out.x * flight - out.y * side, y: spot.y + out.y * flight + out.x * side };
}

function scaled(spot: Vec2, factor: number): Vec2 {
  return { x: MIDDLE.x + (spot.x - MIDDLE.x) * factor, y: MIDDLE.y + (spot.y - MIDDLE.y) * factor };
}

function turned(spot: Vec2, angle: number): Vec2 {
  const x = spot.x - MIDDLE.x;
  const y = spot.y - MIDDLE.y;
  return { x: MIDDLE.x + x * Math.cos(angle) - y * Math.sin(angle), y: MIDDLE.y + x * Math.sin(angle) + y * Math.cos(angle) };
}

/** The way from one spot to another as a unit, or along an angle where they stand on one another. */
function unit(from: Vec2, to: Vec2, fallback = 0): Vec2 {
  const x = to.x - from.x;
  const y = to.y - from.y;
  const length = Math.hypot(x, y);
  if (length <= Number.EPSILON) return { x: Math.cos(fallback), y: Math.sin(fallback) };
  return { x: x / length, y: y / length };
}

/**
 * The tour's clock, the Mac's `BrainTourClock`: when it started, in milliseconds, and where it is held while paused,
 * in seconds, so scrubbing and pausing only ever move the start.
 */
export type TourClock = { readonly started: number; readonly held?: number };

export function tourSeconds(clock: TourClock, now: number): number {
  return clock.held ?? (now - clock.started) / 1000;
}

export function toggleTour(clock: TourClock, now: number): TourClock {
  if (clock.held !== undefined) return { started: now - clock.held * 1000 };
  return { started: clock.started, held: playhead((now - clock.started) / 1000) };
}

export function scrubTour(clock: TourClock, seconds: number, now: number): TourClock {
  return clock.held !== undefined ? { started: clock.started, held: seconds } : { started: now - seconds * 1000 };
}
