/**
 * Where the detail card stands beside the picked mark, as arithmetic a test
 * can read: to its right where there is room, else its left, else below or
 * above it, and always inside the canvas, with the pointer's place along the
 * card's edge so it still points at the mark when the card is pushed in.
 */

export type CardSide = "right" | "left" | "below" | "above";
export type Anchor = {
  left: number;
  top: number;
  side: CardSide;
  /** Where the pointer sits, from the card's top left corner, on the edge facing the mark. */
  pointer: { x: number; y: number };
  /** Whether the mark is on the canvas at all; off it, the card has nothing to point at. */
  visible: boolean;
};

type Size = { width: number; height: number };

/** The air between the mark's rim and the card, and between the card and the canvas edge. */
export const ANCHOR = { gap: 14, margin: 10, pointerInset: 16 } as const;

function clamp(value: number, least: number, most: number): number {
  return most < least ? least : Math.min(most, Math.max(least, value));
}

export function anchorCard(mark: { x: number; y: number; r: number }, card: Size, frame: Size): Anchor {
  const { gap, margin, pointerInset } = ANCHOR;
  const visible = mark.x >= 0 && mark.y >= 0 && mark.x <= frame.width && mark.y <= frame.height;
  const sideTop = clamp(mark.y - card.height / 2, margin, frame.height - card.height - margin);
  const sideLeft = clamp(mark.x - card.width / 2, margin, frame.width - card.width - margin);
  const along = (at: number, start: number, length: number) => clamp(at - start, pointerInset, length - pointerInset);

  const right = mark.x + mark.r + gap;
  const left = mark.x - mark.r - gap - card.width;
  const below = mark.y + mark.r + gap;
  const above = mark.y - mark.r - gap - card.height;
  const tries: { side: CardSide; fits: boolean; anchor: () => Omit<Anchor, "visible"> }[] = [
    { side: "right", fits: right + card.width <= frame.width - margin, anchor: () => ({ left: right, top: sideTop, side: "right", pointer: { x: 0, y: along(mark.y, sideTop, card.height) } }) },
    { side: "left", fits: left >= margin, anchor: () => ({ left, top: sideTop, side: "left", pointer: { x: card.width, y: along(mark.y, sideTop, card.height) } }) },
    { side: "below", fits: below + card.height <= frame.height - margin, anchor: () => ({ left: sideLeft, top: below, side: "below", pointer: { x: along(mark.x, sideLeft, card.width), y: 0 } }) },
    { side: "above", fits: above >= margin, anchor: () => ({ left: sideLeft, top: above, side: "above", pointer: { x: along(mark.x, sideLeft, card.width), y: card.height } }) },
  ];
  const chosen = tries.find((each) => each.fits);
  if (chosen !== undefined) return { ...chosen.anchor(), visible };
  /* Nowhere fits whole: the side with more room, pushed inside the canvas. */
  const roomy = frame.width - mark.x >= mark.x ? tries[0]! : tries[1]!;
  const fallback = roomy.anchor();
  const pushed = clamp(fallback.left, margin, frame.width - card.width - margin);
  return { ...fallback, left: pushed, visible };
}
