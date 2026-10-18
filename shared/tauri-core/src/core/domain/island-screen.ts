/**
 * Which display the island hangs from, ported from the Mac's `IslandScreen`: the main display (Windows and
 * Linux have no notch, so the notch choice means the primary display), wherever the pointer is, or one
 * display by its id. Rust keeps the choice and places the island; this reads and words it for Settings.
 */

export type IslandScreen = { readonly kind: 'notch' } | { readonly kind: 'pointer' } | { readonly kind: 'display'; readonly id: string };

const NOTCH = 'notch';
const POINTER = 'pointer';
const DISPLAY_PREFIX = 'display:';

/** The saved choice, or the main display when nothing or something unknown was saved. */
export function parseIslandScreen(stored: string | undefined): IslandScreen {
  if (stored === POINTER) return { kind: 'pointer' };
  if (stored !== undefined && stored.startsWith(DISPLAY_PREFIX) && stored.length > DISPLAY_PREFIX.length) return { kind: 'display', id: stored.slice(DISPLAY_PREFIX.length) };
  return { kind: 'notch' };
}

export function storedIslandScreen(choice: IslandScreen): string {
  switch (choice.kind) {
    case 'notch':
      return NOTCH;
    case 'pointer':
      return POINTER;
    case 'display':
      return `${DISPLAY_PREFIX}${choice.id}`;
  }
}

/** The Appearance page's words for the row and its two fixed choices. */
export const ISLAND_SCREEN_LINES = {
  title: 'Island display',
  caption: 'The screen the island hangs from. A display that is unplugged hands it back to the main display.',
  notch: 'The main display',
  pointer: 'Where the pointer is',
} as const;

/** One choice per line in the menu: the two fixed ones, then each display connected now by name. */
export function islandScreenOptions(displays: readonly { readonly id: string; readonly name: string }[]): { value: string; label: string }[] {
  return [
    { value: NOTCH, label: ISLAND_SCREEN_LINES.notch },
    { value: POINTER, label: ISLAND_SCREEN_LINES.pointer },
    ...displays.map((display) => ({ value: storedIslandScreen({ kind: 'display', id: display.id }), label: display.name })),
  ];
}

/** What the menu shows as chosen: a display that is gone shows as the main display, where the island went. */
export function shownIslandScreen(stored: string, displays: readonly { readonly id: string }[]): string {
  const choice = parseIslandScreen(stored);
  if (choice.kind === 'display' && !displays.some((display) => display.id === choice.id)) return NOTCH;
  return storedIslandScreen(choice);
}
