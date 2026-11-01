import { describe, expect, it } from "vitest";

import { ANCHOR, anchorCard } from "../src/core/domain/memory-arms/arms-anchor";

const card = { width: 320, height: 200 };
const frame = { width: 1200, height: 800 };

describe("the detail card's anchor", () => {
  it("stands to the right of a mark with room there, its pointer level with the mark", () => {
    const anchor = anchorCard({ x: 300, y: 400, r: 10 }, card, frame);
    expect(anchor.side).toBe("right");
    expect(anchor.left).toBe(300 + 10 + ANCHOR.gap);
    expect(anchor.top + anchor.pointer.y).toBe(400);
    expect(anchor.pointer.x).toBe(0);
  });

  it("flips to the left near the right edge", () => {
    const anchor = anchorCard({ x: 1100, y: 400, r: 10 }, card, frame);
    expect(anchor.side).toBe("left");
    expect(anchor.left + card.width).toBe(1100 - 10 - ANCHOR.gap);
    expect(anchor.pointer.x).toBe(card.width);
  });

  it("goes below or above when neither side has room", () => {
    const narrow = { width: 500, height: 800 };
    expect(anchorCard({ x: 250, y: 100, r: 10 }, card, narrow).side).toBe("below");
    expect(anchorCard({ x: 250, y: 700, r: 10 }, card, narrow).side).toBe("above");
  });

  it("stays inside the canvas when the mark is near a corner, and still points at it", () => {
    const anchor = anchorCard({ x: 200, y: 20, r: 8 }, card, frame);
    expect(anchor.top).toBe(ANCHOR.margin);
    expect(anchor.pointer.y).toBeGreaterThanOrEqual(ANCHOR.pointerInset);
    expect(anchor.top + card.height).toBeLessThanOrEqual(frame.height);
  });

  it("says when the mark has left the canvas", () => {
    expect(anchorCard({ x: -50, y: 400, r: 8 }, card, frame).visible).toBe(false);
    expect(anchorCard({ x: 50, y: 400, r: 8 }, card, frame).visible).toBe(true);
  });

  it("pushes a card that fits nowhere inside the canvas on its roomier side", () => {
    const tiny = { width: 360, height: 220 };
    const anchor = anchorCard({ x: 100, y: 110, r: 10 }, card, tiny);
    expect(anchor.left).toBeGreaterThanOrEqual(ANCHOR.margin);
    expect(anchor.left + card.width).toBeLessThanOrEqual(tiny.width - ANCHOR.margin);
  });
});
