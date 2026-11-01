import { SALT, stableUnit } from "./arms-hash";
import type { ArmsItem, ArmsLayer, ArmsSector } from "./arms-model";
import type { Vec2 } from "./arms-shape";

/**
 * The timeline's places, as arithmetic a test can read: a lane per layer,
 * dated things across by when, and the undated in a row of their own beneath
 * them, spread evenly from one side to the other rather than stacked in one
 * column. A layer with nothing dated gives its whole lane to that row.
 */

export const TIMELINE = { left: -1.3, right: 1.42, axis: -1.02 } as const;

const LANE: Record<ArmsLayer, { from: number; to: number }> = {
  app: { from: 0.74, to: 0.94 },
  rule: { from: 0.44, to: 0.64 },
  memory: { from: -0.56, to: 0.34 },
  skill: { from: -0.9, to: -0.66 },
};
/** The share of a lane its undated row takes when the lane holds dated things too. */
const UNDATED_SHARE = 0.32;
/** The least distance between two undated things along a row, in brain units. */
const UNDATED_GAP = 0.045;
/** How far a dated thing may stray across its lane, as a share of its sub lane, so a day's things do not stack. */
const DATED_SPREAD = 0.8;

export type UndatedRow = { layer: ArmsLayer; y: number };
export type TimelineFrame = { places: Map<string, Vec2>; first?: number; last?: number; undated: UndatedRow[] };

export function timelineFrame(items: readonly ArmsItem[], sectors: readonly ArmsSector[]): TimelineFrame {
  const dated = items.map((item) => item.time).filter((time): time is number => time !== undefined);
  const first = dated.length === 0 ? undefined : Math.min(...dated);
  const last = dated.length === 0 ? undefined : Math.max(...dated);
  const width = TIMELINE.right - TIMELINE.left;
  const sectorAt = new Map(sectors.map((sector, index) => [sector.key, index]));
  const lanes = Math.max(1, sectors.length);
  const places = new Map<string, Vec2>();
  const undated: UndatedRow[] = [];

  for (const layer of Object.keys(LANE) as ArmsLayer[]) {
    const mine = items.filter((item) => item.layer === layer);
    const loose = mine.filter((item) => item.time === undefined || first === undefined || last === undefined);
    const looseSet = new Set(loose);
    const timed = mine.filter((item) => !looseSet.has(item));
    const lane = LANE[layer];
    const split = timed.length === 0 ? lane.from : loose.length === 0 ? lane.to : lane.to - (lane.to - lane.from) * UNDATED_SHARE;
    const datedBand = { from: split, to: lane.to };
    const looseBand = { from: lane.from, to: timed.length === 0 ? lane.to : split };

    for (const item of timed) {
      const sector = item.sector === undefined ? undefined : sectorAt.get(item.sector);
      const share = layer === "memory" && sector !== undefined ? (sector + 0.5) / lanes : 0.5;
      const height = datedBand.to - datedBand.from;
      const jitter = (stableUnit(item.id, SALT.ring) - 0.5) * (layer === "memory" ? height / lanes : height) * DATED_SPREAD;
      const along = last === first ? 0.5 : (item.time! - first!) / (last! - first!);
      places.set(item.id, { x: TIMELINE.left + along * width, y: datedBand.from + height * share + jitter });
    }

    if (loose.length === 0) continue;
    /* Grouped by colour, then by name, so an undated row reads as clusters and not as noise. */
    const ordered = [...loose].sort(
      (a, b) => (sectorAt.get(a.sector ?? "") ?? -1) - (sectorAt.get(b.sector ?? "") ?? -1) || a.label.localeCompare(b.label) || a.id.localeCompare(b.id),
    );
    const perRow = Math.max(1, Math.floor(width / UNDATED_GAP));
    const rows = Math.ceil(ordered.length / perRow);
    const rowHeight = (looseBand.to - looseBand.from) / rows;
    ordered.forEach((item, index) => {
      const row = Math.floor(index / perRow);
      const inRow = Math.min(perRow, ordered.length - row * perRow);
      const column = index - row * perRow;
      places.set(item.id, {
        x: TIMELINE.left + ((column + 0.5) / inRow) * width,
        y: looseBand.to - rowHeight * (row + 0.5),
      });
    });
    undated.push({ layer, y: looseBand.to - rowHeight * 0.5 });
  }
  return { places, undated, ...(first === undefined ? {} : { first }), ...(last === undefined ? {} : { last }) };
}
