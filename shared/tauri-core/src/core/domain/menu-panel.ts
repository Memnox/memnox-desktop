/**
 * The tray panel, ported from the Mac's menu bar `MenuView`: its rows in order, the listening badge, the
 * connected strip, and where the panel sits beside the tray icon. Windows puts the tray at the bottom of
 * the screen and most Linux desktops at the top, so the panel opens away from the edge the icon is on.
 */

/** What a press on a panel row asks for; the island carries each out, and Quit ends the app. */
export type MenuAction = 'talk' | 'rule' | 'copy' | 'mute' | 'settings' | 'tools' | 'quit';

export const MENU_ACTIONS: readonly MenuAction[] = ['talk', 'rule', 'copy', 'mute', 'settings', 'tools', 'quit'];

export function isMenuAction(value: unknown): value is MenuAction {
  return typeof value === 'string' && (MENU_ACTIONS as readonly string[]).includes(value);
}

/** One row of the rows card. */
export interface MenuRow {
  readonly action: MenuAction;
  readonly title: string;
  /** The SF Symbol the Mac draws, which the kit maps to its lucide twin. */
  readonly symbol: string;
  /** Keycaps at the end of the row, such as the talk key. */
  readonly keys?: readonly string[];
  readonly tooltip?: string;
  /** Drawn quieter, as Quit is. */
  readonly quiet?: boolean;
  /** Keeps the panel open after the press, as mute does, so the change is seen. */
  readonly staysOpen?: boolean;
  /** A divider goes above this row. */
  readonly dividerAbove?: boolean;
}

/** The rows in the Mac's order, with the talk key as this computer spells it. */
export function menuRows(muted: boolean, talkKeys: readonly string[]): MenuRow[] {
  return [
    { action: 'talk', title: 'Talk to Memnox', symbol: 'waveform', keys: talkKeys, tooltip: `Talk to Memnox with ${talkKeys.join(' ')}` },
    { action: 'rule', title: 'Say a rule', symbol: 'shield.lefthalf.filled' },
    { action: 'copy', title: 'Copy what happened', symbol: 'doc.on.clipboard' },
    muted
      ? { action: 'mute', title: 'Unmute voice', symbol: 'speaker.wave.2', staysOpen: true }
      : { action: 'mute', title: 'Mute voice', symbol: 'speaker.slash', staysOpen: true },
    { action: 'settings', title: 'Settings', symbol: 'gearshape', dividerAbove: true },
    { action: 'quit', title: 'Quit Memnox', symbol: 'power', quiet: true },
  ];
}

/** The badge in the header: whether the voice wakes by name, else the key that starts a talk. */
export function listeningBadge(wakesByName: boolean, talkKeys: readonly string[]): { text: string; tooltip: string; lit: boolean } {
  const keys = talkKeys.join(' ');
  if (wakesByName) return { text: 'Say “Memnox”', tooltip: 'Memnox wakes when you say its name', lit: true };
  // The Mac's key is one short glyph; Control Alt Space is long, so it stands alone and the tooltip says the rest.
  return { text: keys.length <= BADGE_ROOM ? `${keys} to talk` : keys, tooltip: `Press ${keys} to talk`, lit: false };
}

/** The longest key name the badge still follows with "to talk", so it fits beside the title in 300. */
const BADGE_ROOM = 9;

/** One chip of the connected strip: an agent the voice can use, or an app the person connected. */
export interface ToolChip {
  readonly id: string;
  readonly kind: 'agent' | 'app';
  /** The agent kind or the toolkit slug, which picks the mark. */
  readonly key: string;
  readonly name: string;
  /** Works now, rather than needing the person. */
  readonly ready: boolean;
}

/** A chip's tooltip, its name or what it needs. */
export function chipTooltip(chip: ToolChip): string {
  return chip.ready ? chip.name : `${chip.name} needs you`;
}

/** What the strip says instead of chips: still reading, a reason the list could not be had, or nothing yet. */
export function stripNote(reading: boolean, failed: string | undefined, chips: readonly ToolChip[]): string | undefined {
  if (chips.length > 0) return undefined;
  if (reading) return 'Reading your tools';
  if (failed !== undefined) return failed;
  return 'No tools connected yet';
}

/** Each section rises 6 into place a beat after the one before it, every time the panel opens. */
export const MENU_SETTLE = { stepMs: 40, lift: 6, durationMs: 320 } as const;

/** The panel's own size and the room it keeps from the icon and the screen's edges. */
export const MENU_PANEL = { width: 300, gap: 6, inset: 8, fadeMs: 160 } as const;

export interface Rect {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

/**
 * Where the panel goes: centred on the icon, 6 away from it on the side away from the screen's nearer
 * edge, and clamped 8 inside the screen's work area, as the Mac clamps it inside the visible frame.
 */
export function menuPanelPlace(icon: Rect, screen: Rect, size: { width: number; height: number }): { x: number; y: number } {
  const below = icon.y + icon.height / 2 < screen.y + screen.height / 2;
  const x = icon.x + icon.width / 2 - size.width / 2;
  const y = below ? icon.y + icon.height + MENU_PANEL.gap : icon.y - MENU_PANEL.gap - size.height;
  const clamp = (value: number, low: number, high: number) => Math.min(Math.max(value, low), Math.max(low, high));
  return {
    x: clamp(x, screen.x + MENU_PANEL.inset, screen.x + screen.width - MENU_PANEL.inset - size.width),
    y: clamp(y, screen.y + MENU_PANEL.inset, screen.y + screen.height - MENU_PANEL.inset - size.height),
  };
}
