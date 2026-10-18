/** How Settings, the first run and the cards look, as the Mac's `Appearance`; the island stays dark in every look. */
export type Look = 'light' | 'dark' | 'system';

/** In the order the picker offers them. */
export const LOOKS: readonly Look[] = ['light', 'dark', 'system'];

export const LOOK_NAMES: Record<Look, string> = { light: 'Light', dark: 'Dark', system: 'System' };

export function isLook(text: string): text is Look {
  return (LOOKS as readonly string[]).includes(text);
}

/** The theme a window draws in: the look itself, or the computer's when the look is System. */
export function themeFor(look: Look, systemDark: boolean): 'light' | 'dark' {
  if (look === 'system') return systemDark ? 'dark' : 'light';
  return look;
}

/** The line under the picker, saying why the island ignores it. */
export const ISLAND_STAYS_DARK = 'The island stays dark in every look, because it hangs from the top of the screen like the notch it stands in for.';
