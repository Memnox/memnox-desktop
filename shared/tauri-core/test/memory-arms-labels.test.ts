import { describe, expect, it } from "vitest";

import { clipped, placeLabels } from "../src/core/domain/memory-arms/arms-labels";

const box = (id: string, left: number, weight: number, always = false) => ({ id, left, top: 0, width: 50, height: 12, weight, ...(always ? { always } : {}) });

describe("the brain's names", () => {
  it("keeps the heavier of two names that would overlap", () => {
    expect([...placeLabels([box("piece", 10, 1), box("hub", 0, 100)])]).toEqual(["hub"]);
  });

  it("places names that do not touch side by side", () => {
    expect(placeLabels([box("a", 0, 1), box("b", 80, 1)]).size).toBe(2);
  });

  it("always shows the hovered name, over a heavier one", () => {
    const shown = placeLabels([box("hub", 0, 100), box("hovered", 10, 1, true)]);
    expect(shown.has("hovered")).toBe(true);
    expect(shown.has("hub")).toBe(false);
  });

  it("cuts a long name with an ellipsis", () => {
    expect(clipped("short", 10)).toBe("short");
    expect(clipped("a much longer name than fits", 10)).toBe("a much lo…");
  });
});
