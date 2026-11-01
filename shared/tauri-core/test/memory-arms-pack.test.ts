import { describe, expect, it } from "vitest";

import { stableUnit } from "../src/core/domain/memory-arms/arms-hash";
import { clusterRadius, packDiscs, sunflower, type Vec2 } from "../src/core/domain/memory-arms/arms-pack";

const circleRoom = (radius: number) => ({
  contains: (point: Vec2) => Math.hypot(point.x, point.y) <= radius,
  area: Math.PI * radius * radius,
  middle: { x: 0, y: 0 },
  stretch: 1,
});

describe("the brain's packing", () => {
  it("draws the same fraction for an id as the Mac's FNV 1a does", () => {
    /* Each value was read off a 64 bit FNV 1a with the salt folded into its basis, as SurfaceOrbit.unit runs it. */
    expect(stableUnit("memory:f1", 71)).toBe(685992 / 2 ** 20);
    expect(stableUnit("slack", 51)).toBe(1011230 / 2 ** 20);
    expect(stableUnit("é note", 3)).toBe(217346 / 2 ** 20);
    expect(stableUnit("", 0)).toBe(140069 / 2 ** 20);
  });

  it("sizes a cluster by the square root of what it holds", () => {
    expect(clusterRadius(100) - clusterRadius(0)).toBeCloseTo((clusterRadius(25) - clusterRadius(0)) * 2, 9);
  });

  it("packs discs inside the room with none over another or over the taken", () => {
    const radii = [0.4, 0.3, 0.25, 0.2, 0.2, 0.1, 0.1, 0.08];
    const taken = [{ x: 0, y: 0, r: 0.2 }];
    const { discs } = packDiscs(radii, { ...circleRoom(1.4), taken });
    expect(discs).toHaveLength(radii.length);
    const all = [...taken, ...discs];
    for (const a of all) {
      expect(Math.hypot(a.x, a.y) + a.r).toBeLessThanOrEqual(1.4 + 1e-9);
      for (const b of all) if (a !== b) expect(Math.hypot(a.x - b.x, a.y - b.y)).toBeGreaterThanOrEqual(a.r + b.r);
    }
  });

  it("draws everything smaller rather than leave a cluster off when the room is tight", () => {
    const { scale, discs } = packDiscs([0.5, 0.5, 0.5, 0.5], circleRoom(0.8));
    expect(scale).toBeLessThan(1);
    expect(discs.every((disc) => Math.hypot(disc.x, disc.y) + disc.r <= 0.8 + 1e-9)).toBe(true);
  });

  it("packs the same radii the same way every time", () => {
    expect(packDiscs([0.3, 0.2, 0.1], circleRoom(1))).toEqual(packDiscs([0.3, 0.2, 0.1], circleRoom(1)));
  });

  it("spaces pieces in their disc evenly, none on another, the middle left for the hub", () => {
    const ids = Array.from({ length: 80 }, (_, at) => `piece${at}`);
    const disc = { x: 0.3, y: -0.1, r: 0.5 };
    const spots = [...sunflower(ids, disc, "slack").values()];
    expect(spots).toHaveLength(80);
    let closest = Number.POSITIVE_INFINITY;
    for (const a of spots) {
      const reach = Math.hypot(a.x - disc.x, a.y - disc.y);
      expect(reach).toBeLessThanOrEqual(disc.r + 1e-9);
      expect(reach).toBeGreaterThanOrEqual(disc.r * 0.3 - 1e-9);
      for (const b of spots) if (a !== b) closest = Math.min(closest, Math.hypot(a.x - b.x, a.y - b.y));
    }
    expect(closest).toBeGreaterThan(0.02);
  });
});
