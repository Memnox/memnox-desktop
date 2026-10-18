import { DISPLAY, type DaemonEvent } from '@memnox/core/wire';
import type { Platform } from './platform';
import { caption, toolWord } from './spoken';

/** The longest caption the island shows, which fits its width in one line at the caption size, as the Mac's `captionLimit`. */
export const CAPTION_LIMIT = 40;

/** What the island says while the brain looks something up, so a long lookup never looks stuck. */
export function readingCaption(tool: string | undefined): string {
  return `reading ${toolWord(tool)}`;
}

/** What each system asks a yes to be signed with, where the Mac says Touch ID. */
const KEY_ASKS: Record<Platform, string> = {
  windows: 'Windows Hello',
  linux: 'Your password',
  other: 'Touch ID',
};

/** The caption while the key's prompt is up: "Windows Hello to allow the deploy once", cut to one line. */
export function keyCaption(platform: Platform, reason: string): string {
  return caption(`${KEY_ASKS[platform]} to ${reason}`, CAPTION_LIMIT);
}

/** What the Mac's island says while it carries out each kind of display, for the ones that take a moment. */
const DOING: Partial<Record<string, (event: DaemonEvent) => string>> = {
  [DISPLAY.TYPE]: () => 'typing it in',
  [DISPLAY.PREFILL]: () => 'typing it in',
  [DISPLAY.LAUNCH]: () => 'starting it',
  [DISPLAY.APP]: (event) => caption(`opening ${event.title ?? event.agent}`, CAPTION_LIMIT),
  [DISPLAY.CLOSE]: () => 'closing it',
  [DISPLAY.INTERRUPT]: () => 'stopping it',
  [DISPLAY.PRESS]: () => 'answering it',
};

/** The caption while a display is carried out, or undefined for one that shows at once and needs none. */
export function displayCaption(event: DaemonEvent): string | undefined {
  return event.display === undefined ? undefined : DOING[event.display]?.(event);
}
