import { islandButtonClass } from './kit';
import { PRESSABLE } from './kit/press';

/**
 * The few shared looks the Settings panel still reads by name, now drawn as the Mac's island draws
 * them: `primary` and `quiet` are the IslandButton pill, `icon` a bare glyph that presses. New screens
 * use the kit directly.
 */
const BUTTON = {
  primary: islandButtonClass('primary'),
  quiet: islandButtonClass('secondary'),
  icon: `${PRESSABLE} inline-flex items-center justify-center text-white disabled:opacity-40`,
  /** A 24 circle of white 10%, as the Mac's round close and copy buttons are. */
  round: `${PRESSABLE} grid size-6 place-items-center rounded-full bg-white/10 text-white/[0.92]`,
} as const;

export function button(kind: keyof typeof BUTTON): string {
  return BUTTON[kind];
}

/** A failure said on a card: 11 red, beside a TriangleAlert. */
export const note = 'flex items-start gap-1.5 text-caption text-red';

/** A call settled elsewhere: 13 green, beside a filled check. */
export const settledNote = 'flex items-center gap-1.5 text-body text-green';
