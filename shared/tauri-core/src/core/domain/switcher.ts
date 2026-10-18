/**
 * The switcher's shelf, ported from the Mac's `Switcher.swift`: the sessions as cards standing in a row
 * in 3D, turned like records on a shelf, which turn past until the one asked for faces the person.
 * Pure numbers, so the shelf is tested without a window and the window only draws them.
 */

export const SHELF = {
  turnDegrees: 52,
  /** SwiftUI's perspective 0.55, as a CSS perspective distance for a 240 wide card. */
  perspectivePx: 440,
  chosenScale: 1.18,
  /** Cards further than this stop shrinking and dimming, so the far end of the row stays legible. */
  farthestStep: 3,
  shrinkPerStep: 0.1,
  spacing: 150,
  /** Extra room each side of the front card, so the turned ones clear it. */
  sideGap: 70,
  chosenLift: -20,
  /** Past this a card is off the shelf and hidden. */
  hiddenBeyond: 3.4,
  chosenBrightness: 0.06,
  dimPerStep: 0.08,
  /** A card counts as the one in front while the turn is within half a place of it. */
  frontReach: 0.5,
} as const;

/** How long each beat of the switcher takes, in milliseconds. */
export const SWITCHER_TIMING = {
  fadeIn: 300,
  /** Lets the row fade in before it starts to turn. */
  settleBeforeTurn: 280,
  /** A beat per card, quick enough that several pass in about a second. */
  perStep: 160,
  /** Added to the turn so even a one card turn eases rather than snaps. */
  turnBase: 350,
  hold: 450,
  chosenHold: 380,
  exit: 250,
} as const;

export interface ShelfPlace {
  readonly rotateY: number;
  readonly scale: number;
  readonly x: number;
  readonly y: number;
  readonly hidden: boolean;
  /** Added to brightness: positive lifts the chosen card, negative dims the far ones. */
  readonly brightness: number;
  readonly z: number;
  readonly front: boolean;
}

/** Where a card stands for its offset from the one in front, fractional while the row turns. */
export function shelfPlace(offset: number, chosen: boolean): ShelfPlace {
  const side = Math.max(-1, Math.min(1, offset));
  const distance = Math.abs(offset);
  const front = distance < SHELF.frontReach;
  const isChosen = chosen && front;
  const steps = Math.min(distance, SHELF.farthestStep);
  return {
    rotateY: -side * SHELF.turnDegrees,
    scale: isChosen ? SHELF.chosenScale : 1 - steps * SHELF.shrinkPerStep,
    x: offset * SHELF.spacing + side * SHELF.sideGap,
    y: isChosen ? SHELF.chosenLift : 0,
    hidden: distance > SHELF.hiddenBeyond,
    brightness: isChosen ? SHELF.chosenBrightness : -steps * SHELF.dimPerStep,
    z: -distance,
    front,
  };
}

/** Starts across the row from the one asked for, so the turn has somewhere to travel. */
export function shelfStart(target: number, count: number): number {
  return target < count / 2 ? count - 1 : 0;
}

/** How long the turn from one place to another takes. */
export function turnMs(from: number, to: number): number {
  return SWITCHER_TIMING.perStep * Math.abs(to - from) + SWITCHER_TIMING.turnBase;
}
