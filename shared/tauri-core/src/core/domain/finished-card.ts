import { DAEMON_EVENT, type DaemonEvent } from '@memnox/core/wire';

/** The notice word for a long turn that ended and handed back to the person, as the runtime's `NOTICE_KIND` names it. */
const FINISHED = 'finished';

/** A session that just finished, as the island shows it for a moment: who, and what they did. */
export interface FinishedCard {
  readonly agent: string;
  readonly who: string;
  readonly summary: string;
  readonly sessionId: string | undefined;
}

/** The card for a finished NOTICE, undefined for any other event. Ported from the Mac's `FinishedCard`. */
export function finishedCard(event: DaemonEvent): FinishedCard | undefined {
  if (event.kind !== DAEMON_EVENT.NOTICE || event.notice !== FINISHED) return undefined;
  return { agent: event.agent, who: event.agentName ?? event.agent, summary: event.summary, sessionId: event.sessionId };
}
