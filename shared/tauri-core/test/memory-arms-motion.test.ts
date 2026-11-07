import { describe, expect, it } from "vitest";

import { alongPath, easeOutBack, heartbeatAt, HEARTBEAT, OPENING, openingOf, springAtRest, springStep, type Spring } from "../src/core/domain/memory-arms/arms-motion";

describe("the ARMS map's motion", () => {
  it("opens each layer in turn from the core out, all within the opening", () => {
    expect(openingOf("skill", 0.5)).toBeGreaterThan(openingOf("app", 0.5));
    expect(openingOf("memory", OPENING.memory[1])).toBe(1);
    for (const layer of ["skill", "memory", "rule", "app"] as const) expect(openingOf(layer, OPENING.total)).toBe(1);
  });

  it("drops a tile past its mark before it settles on it", () => {
    const samples = Array.from({ length: 50 }, (_, at) => easeOutBack(at / 49));
    expect(Math.max(...samples)).toBeGreaterThan(1);
    expect(samples.at(-1)).toBeCloseTo(1, 6);
  });

  it("lands a spring on its target and comes to rest", () => {
    let spring: Spring = { value: 0, velocity: 0 };
    for (let step = 0; step < 240; step += 1) spring = springStep(spring, 2, 1 / 60);
    expect(spring.value).toBeCloseTo(2, 3);
    expect(springAtRest(spring, 2)).toBe(true);
  });

  it("passes through every stop of an arrival's path", () => {
    const stops = [{ x: 0, y: 0 }, { x: 10, y: 0 }, { x: 10, y: 10 }];
    expect(alongPath(stops, 0)).toEqual({ x: 0, y: 0 });
    expect(alongPath(stops, 0.5).x).toBeCloseTo(10, 6);
    expect(alongPath(stops, 1)).toEqual({ x: 10, y: 10 });
  });

  it("beats from the core outward and rests between beats", () => {
    expect(heartbeatAt(0)).toBe(0);
    expect(heartbeatAt(HEARTBEAT.travel * 0.9)!).toBeGreaterThan(heartbeatAt(HEARTBEAT.travel * 0.2)!);
    expect(heartbeatAt(HEARTBEAT.travel + 0.5)).toBeUndefined();
  });
});
