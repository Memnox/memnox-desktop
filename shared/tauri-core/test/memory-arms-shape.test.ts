import { describe, expect, it } from "vitest";

import { LAYER_AT, OUTLINE_AREA, OUTLINE_LENGTH, arcShareOf, arcSpaced, brainPoint, layerOfPoint, outlineAt, project, shellPoint, thetaAtArcShare } from "../src/core/domain/memory-arms/arms-shape";

describe("the ARMS brain outline", () => {
  it("is wider than it is tall, as a brain is from the side", () => {
    const across = outlineAt(0).x - outlineAt(Math.PI).x;
    const down = outlineAt(Math.PI / 2).y - outlineAt(-Math.PI / 2).y;
    expect(across).toBeGreaterThan(down);
  });

  it("is not a circle or an ellipse, since the lobes lift it unevenly", () => {
    const reach = [0.35, 1.45, -1.25].map((theta) => Math.hypot(outlineAt(theta).x / 1.22, outlineAt(theta).y / 0.86));
    expect(Math.max(...reach) - Math.min(...reach)).toBeGreaterThan(0.15);
  });

  it("closes on itself", () => {
    const start = outlineAt(0);
    const end = outlineAt(Math.PI * 2);
    expect(end.x).toBeCloseTo(start.x, 6);
    expect(end.y).toBeCloseTo(start.y, 6);
  });

  it("nests every layer inside the next, from the core out", () => {
    const theta = 1;
    const reach = (f: number) => Math.hypot(brainPoint(theta, f).x, brainPoint(theta, f).y);
    expect(reach(LAYER_AT.core)).toBeLessThan(reach(LAYER_AT.rules));
    expect(reach(LAYER_AT.rules)).toBeLessThan(reach(LAYER_AT.apps));
  });

  it("reads a flat point back to the angle and layer it was placed at", () => {
    const back = layerOfPoint(brainPoint(2.2, 0.6));
    expect(back.theta).toBeCloseTo(2.2, 2);
    expect(back.f).toBeCloseTo(0.6, 2);
  });

  it("keeps a shell point on the outline when it is not turned", () => {
    const flat = brainPoint(1.1, 0.7);
    const shell = shellPoint(1.1, 0.7, 0);
    expect(shell).toEqual({ x: flat.x, y: flat.y, z: 0 });
  });

  it("draws the near side larger than the far side", () => {
    const near = project({ x: 0, y: 0, z: 1 }, 0, 0);
    const far = project({ x: 0, y: 0, z: -1 }, 0, 0);
    expect(near.scale).toBeGreaterThan(far.scale);
    expect(near.depth).toBeGreaterThan(far.depth);
  });
});

describe("the outline by distance", () => {
  it("reads a share of its length back to the angle it came from", () => {
    for (const theta of [0.3, 1.7, 3.9, 5.5]) expect(thetaAtArcShare(arcShareOf(theta))).toBeCloseTo(theta, 3);
  });

  it("spaces a ring evenly by distance rather than by angle", () => {
    const angles = arcSpaced(8, Math.PI / 2);
    const shares = angles.map((theta, at) => (((arcShareOf(angles[(at + 1) % angles.length]!) - arcShareOf(theta)) % 1) + 1) % 1);
    for (const share of shares) expect(share).toBeCloseTo(1 / 8, 4);
    const turns = angles.map((theta, at) => (((angles[(at + 1) % angles.length]! - theta) % (Math.PI * 2)) + Math.PI * 2) % (Math.PI * 2));
    expect(Math.max(...turns) - Math.min(...turns)).toBeGreaterThan(0.05);
    expect(arcShareOf(angles[0]!)).toBeCloseTo(arcShareOf(Math.PI / 2), 6);
  });

  it("measures an area near the ellipse it is lifted from", () => {
    expect(OUTLINE_AREA).toBeGreaterThan(Math.PI * 1.22 * 0.86 * 0.9);
    expect(OUTLINE_LENGTH).toBeGreaterThan(6);
  });
});
