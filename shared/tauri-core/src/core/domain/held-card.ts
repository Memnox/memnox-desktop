import type { DaemonEvent } from '@memnox/core/wire';
import { callLabel, THIS_COMPUTER } from './call-label';

/** A held call as the island draws it: whose it is, what it wants, why it was held. */
export interface HeldCard {
  readonly subject: string;
  /** "codex on this computer". */
  readonly label: string;
  /** What it wants to do as a phrase, or the daemon's summary when it gave none. */
  readonly what: string;
  readonly why: string | undefined;
  readonly task: string | undefined;
  readonly place: string | undefined;
  /** The daemon placed the call inside its session's repository, so a yes goes without the key. */
  readonly withinSession: boolean;
  readonly expiresAt: string | undefined;
}

/** The card for a HELD event; every event this app shows waits on this computer, so that is its machine. */
export function heldCard(event: DaemonEvent): HeldCard {
  return {
    subject: event.subject,
    label: callLabel(event.agentName ?? event.agent, THIS_COMPUTER),
    what: event.what ?? event.summary,
    why: event.why,
    task: event.task,
    place: event.place,
    withinSession: event.withinSession === true,
    expiresAt: event.expiresAt,
  };
}
