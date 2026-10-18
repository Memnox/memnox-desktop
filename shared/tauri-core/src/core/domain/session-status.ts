/**
 * What a session shows a person at a glance, ported from the Mac's `SessionStatus` and `StatusTint`,
 * decided once so the island, the side panel, the switcher and the live window all agree.
 */

export type SessionStatus = 'paused' | 'needs-you' | 'thinking' | 'working' | 'waiting-on-you' | 'ended' | 'quiet';

/** The states the daemon's session list writes, as the runtime names them. */
const STATE = { working: 'working', open: 'open', ended: 'ended', paused: 'paused' } as const;

export interface StatusFacts {
  readonly state: string | undefined;
  readonly thinking: boolean;
  /** Why the breaker paused it, present only on a session read up close. */
  readonly paused?: string | undefined;
  readonly waitingOnYou?: number;
}

/** The first that holds wins, because a pause or a question for the person matters more than activity. */
export function sessionStatus({ state, thinking, paused, waitingOnYou = 0 }: StatusFacts): SessionStatus {
  if (paused !== undefined || state === STATE.paused) return 'paused';
  if (waitingOnYou > 0) return 'needs-you';
  if (thinking) return 'thinking';
  switch (state) {
    case STATE.working:
      return 'working';
    case STATE.open:
      return 'waiting-on-you';
    case STATE.ended:
      return 'ended';
    default:
      return 'quiet';
  }
}

/** The words on the session's badge. */
export function statusLabel(status: SessionStatus): string {
  switch (status) {
    case 'paused':
      return 'Paused';
    case 'needs-you':
      return 'Needs you';
    case 'thinking':
      return 'Thinking';
    case 'working':
      return 'Working';
    case 'waiting-on-you':
      return 'Waiting on you';
    case 'ended':
      return 'Ended';
    case 'quiet':
      return 'Quiet';
  }
}

/** Whether the agent is busy right now, which is what makes a card glow and a logo sit beside the notch. */
export function isActive(status: SessionStatus): boolean {
  return status === 'working' || status === 'thinking';
}

/** The status colour, dark values as the island draws them: red paused, amber waiting, green busy, grey otherwise. */
export function statusTint(status: SessionStatus): string {
  switch (status) {
    case 'paused':
      return '#FF453A';
    case 'needs-you':
    case 'waiting-on-you':
      return '#FF9F0A';
    case 'thinking':
    case 'working':
      return '#30D158';
    case 'ended':
    case 'quiet':
      return '#9E9E9F';
  }
}
