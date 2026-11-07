import { describe, expect, it } from "vitest";

import { fitTo, ZOOM } from "../src/core/domain/memory-arms/arms-fit";

const frame = { width: 1000, height: 600, unit: 200 };

describe("Fit", () => {
  it("centres on the marks that exist, not on the middle of the silhouette", () => {
    const camera = fitTo([{ x: 0.4, y: 0.2 }, { x: 0.6, y: 0.4 }], frame);
    expect(camera.x).toBeCloseTo(0.5, 9);
    expect(camera.y).toBeCloseTo(0.3, 9);
  });

  it("zooms in on a small brain and out on a wide one", () => {
    const small = fitTo([{ x: 0, y: 0 }, { x: 0.3, y: 0.2 }], frame);
    const wide = fitTo([{ x: -3, y: -2 }, { x: 3, y: 2 }], frame);
    expect(small.k).toBeGreaterThan(1);
    expect(wide.k).toBeLessThan(1);
  });

  it("stays inside the zoom range and frames nothing at rest", () => {
    expect(fitTo([{ x: 0, y: 0 }], { ...frame, unit: 1e6 }).k).toBe(ZOOM.least);
    expect(fitTo([], frame)).toEqual({ x: 0, y: 0, k: 1 });
    expect(ZOOM.most).toBe(12);
  });
});
