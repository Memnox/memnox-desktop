import { DAEMON_EVENT, type DaemonEvent } from '@memnox/core/wire';
import { quietHere } from './quiet';

/**
 * Which events are said out loud and which keep the microphone open afterwards, ported from the Mac's
 * `Announcing.swift`. Notice kinds are the runtime's own words for them.
 */

/** Said whatever the Speak up setting, because the person asked for it or somebody waits on them. */
const ALWAYS_SAID = new Set(['watched', 'question', 'asking', 'collision', 'gone', 'signed-in', 'sign-in-stalled']);
/** Keeps the microphone open once said, because only the person can answer it. */
const AWAITS_ANSWER = new Set(['question', 'asking', 'collision']);

/** A drive grant, a phone's turn or the voice moving to a phone: put on the island at once and never said. */
export function isShownOnly(event: DaemonEvent): boolean {
  return event.drivenBy !== undefined || event.phoneTurn !== undefined || event.voiceOn !== undefined;
}

/** Whether to say this out loud: everything but a notice is, and a notice only when it must be or they asked for news. */
export function isSaid(event: DaemonEvent, speakUp: boolean, phoneHolds = false): boolean {
  if (quietHere(event, phoneHolds) || isShownOnly(event)) return false;
  if (event.kind !== DAEMON_EVENT.NOTICE) return true;
  return speakUp || ALWAYS_SAID.has(event.notice ?? '');
}

/** Whether the conversation stays open once this is said, because it waits on the person rather than only telling them. */
export function awaitsAnswer(event: DaemonEvent, phoneHolds = false): boolean {
  if (quietHere(event, phoneHolds) || isShownOnly(event)) return false;
  return event.kind === DAEMON_EVENT.HELD || (event.kind === DAEMON_EVENT.NOTICE && AWAITS_ANSWER.has(event.notice ?? ''));
}
