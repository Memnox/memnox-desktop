import { HOLD_ANSWER } from '@memnox/core/wire';
import { trimmed } from './call-label';

/**
 * What a held card says for a moment when its call was settled somewhere else, built only from what
 * was reported, so it never claims who or how where nothing said. Ported from the Mac's `SettledLine`.
 */

/** Nothing says who or how, and it may have run out rather than been answered, so it claims neither. */
export const SETTLED_UNKNOWN = 'No longer waiting';

const VERBS: Record<string, string> = {
  [HOLD_ANSWER.ONCE]: 'allowed once',
  [HOLD_ANSWER.SESSION]: 'allowed for the session',
  [HOLD_ANSWER.DENY]: 'denied',
};

/** The console and chat are places rather than devices, so they are said as places. */
const PLACES: Record<string, string> = {
  console: 'in the console',
  slack: 'in Slack',
};

const capitalised = (text: string): string => text.charAt(0).toUpperCase() + text.slice(1);

export function settledLine(answer: string | undefined, by?: string, on?: string): string {
  const person = trimmed(by);
  const device = trimmed(on);
  const word = trimmed(answer);
  const verb = word === undefined ? undefined : VERBS[word];
  if (person === undefined && device === undefined) return verb === undefined ? SETTLED_UNKNOWN : capitalised(`${verb} elsewhere`);
  let line = verb ?? 'answered';
  // "Ana's iPhone" already says whose, so "by Ana" beside it would say it twice.
  if (person !== undefined && !(device?.startsWith(`${person}'s `) ?? false)) line += ` by ${person}`;
  if (device !== undefined) line += ` ${PLACES[device.toLowerCase()] ?? `on ${device}`}`;
  return capitalised(line);
}
