import { SALT, stableUnit } from "./arms-hash";

/**
 * Where each area's cluster sits and where each thing sits inside it, as
 * arithmetic a test can read. Clusters are discs sized by the square root of
 * what they hold, packed largest first along a golden angle spiral out from
 * the middle, so none lies over another; inside a disc the pieces follow a
 * sunflower spiral, which spaces them evenly with nothing stacked. No step
 * draws a random number, so the same record packs the same brain every load,
 * by the same steps as the Mac's `BrainClusters.pack`.
 */

export type Vec2 = { x: number; y: number };
export type Disc = { x: number; y: number; r: number };

/** Brain units throughout, where the outline is about two and a half across. */
export const CLUSTER = {
  /** A cluster's least radius, and how it grows with the square root of what it holds. */
  least: 0.07,
  per: 0.028,
  /** The air between two clusters. */
  gap: 0.035,
  /** Pieces sit from this share of the radius out, so the hub stands clear and its spokes read. */
  inner: 0.3,
  /** The share of the room the clusters may fill before they are drawn smaller, so packing always has room. */
  fillShare: 0.55,
  /** The spiral walks this much further out at each step's square root, and gives up after this many. */
  spiralStep: 0.018,
  mostTries: 3200,
  /** When a packing cannot fit everything, every disc is drawn this much smaller and it starts again. */
  shrink: 0.86,
  mostShrinks: 6,
  /** How many points of a disc's rim are checked against the room. */
  rimSamples: 12,
} as const;

const TAU = Math.PI * 2;
const GOLDEN = Math.PI * (3 - Math.sqrt(5));

export function clusterRadius(count: number): number {
  return CLUSTER.least + CLUSTER.per * Math.sqrt(Math.max(0, count));
}

/** The room the clusters are packed into. */
export type PackRoom = {
  /** Whether one point is inside the room. */
  contains: (point: Vec2) => boolean;
  /** The area the discs share, which bounds how large they may be drawn. */
  area: number;
  /** Where the spiral starts. */
  middle: Vec2;
  /** Width over height, so the spiral follows the room's proportions rather than a circle's. */
  stretch: number;
  /** Discs already standing, as the core does, which nothing may lie over. */
  taken?: readonly Disc[];
};

/** Whether a disc lies wholly in the room: its middle and every sampled point of its rim. */
export function discInside(disc: Disc, contains: (point: Vec2) => boolean): boolean {
  if (!contains(disc)) return false;
  for (let at = 0; at < CLUSTER.rimSamples; at += 1) {
    const angle = (at / CLUSTER.rimSamples) * TAU;
    if (!contains({ x: disc.x + Math.cos(angle) * disc.r, y: disc.y + Math.sin(angle) * disc.r })) return false;
  }
  return true;
}

/**
 * Centres for discs of these radii, in the order given, none over another or
 * over a taken disc. Drawn smaller and packed again when they do not all fit;
 * the last try lets a disc lie over another rather than leave it off the brain.
 */
export function packDiscs(radii: readonly number[], room: PackRoom): { discs: Disc[]; scale: number } {
  const wanted = radii.reduce((sum, r) => sum + Math.PI * (r + CLUSTER.gap / 2) ** 2, 0);
  let scale = wanted > 0 ? Math.min(1, Math.sqrt((CLUSTER.fillShare * room.area) / wanted)) : 1;
  for (let attempt = 0; attempt <= CLUSTER.mostShrinks; attempt += 1) {
    const discs = packed(
      radii.map((r) => r * scale),
      room,
      attempt === CLUSTER.mostShrinks,
    );
    if (discs !== undefined) return { discs, scale };
    scale *= CLUSTER.shrink;
  }
  return { discs: radii.map((r) => ({ ...room.middle, r: r * scale })), scale };
}

function packed(radii: readonly number[], room: PackRoom, overlapping: boolean): Disc[] | undefined {
  const across = Math.sqrt(room.stretch);
  const placed: Disc[] = [...(room.taken ?? [])];
  const out: Disc[] = [];
  for (const r of radii) {
    let found: Disc | undefined;
    let fallback: Disc | undefined;
    for (let step = 0; step < CLUSTER.mostTries; step += 1) {
      const angle = step * GOLDEN;
      const reach = CLUSTER.spiralStep * Math.sqrt(step);
      const spot: Disc = { x: room.middle.x + Math.cos(angle) * reach * across, y: room.middle.y + Math.sin(angle) * reach / across, r };
      /* The cheap test first: most steps near the middle are already taken. */
      const free = placed.every((other) => Math.hypot(other.x - spot.x, other.y - spot.y) >= other.r + r + CLUSTER.gap);
      if (!free && !(overlapping && fallback === undefined)) continue;
      if (!discInside(spot, room.contains)) continue;
      fallback ??= spot;
      if (free) {
        found = spot;
        break;
      }
    }
    const spot = found ?? (overlapping ? (fallback ?? { ...room.middle, r }) : undefined);
    if (spot === undefined) return undefined;
    placed.push(spot);
    out.push(spot);
  }
  return out;
}

/**
 * Each piece's spot inside its disc, on a sunflower spiral so neighbours keep
 * an even distance. Pieces are taken in the order their ids hash to, and the
 * spiral is turned by the disc's own key, so two clusters never look stamped.
 */
export function sunflower(ids: readonly string[], disc: Disc, key: string, inner: number = CLUSTER.inner): Map<string, Vec2> {
  const ordered = [...ids].sort((a, b) => stableUnit(a, SALT.order) - stableUnit(b, SALT.order) || a.localeCompare(b));
  const turn = stableUnit(key, SALT.angle) * TAU;
  const spots = new Map<string, Vec2>();
  ordered.forEach((id, index) => {
    const reach = disc.r * (inner + (1 - inner) * Math.sqrt((index + 0.5) / ordered.length));
    const angle = turn + index * GOLDEN;
    spots.set(id, { x: disc.x + Math.cos(angle) * reach, y: disc.y + Math.sin(angle) * reach });
  });
  return spots;
}
