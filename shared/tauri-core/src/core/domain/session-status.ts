/**
 * What a session shows a person at a glance, ported from the Mac's `SessionStatus` and `StatusTint`, decided once so
 * the island, the side panel, Sessions and the live window all agree, in the five statuses every Memnox surface uses
 * (`shared/ux/contract.json`).
 */

export type SessionStatus = 'needs-you' | 'stopped' | 'working' | 'finished' | 'idle';

/** What needs a person first, then what Memnox stopped, then the rest. */
export const SESSION_STATUS_ORDER: readonly SessionStatus[] = ['needs-you', 'stopped', 'working', 'finished', 'idle'];

/** Why a session needs its person or was stopped, worded as what the person will do about it. */
export type SessionReason = 'approval' | 'question' | 'plan' | 'paused' | 'breaker' | 'budget' | 'interrupted';

export const SESSION_REASON_LABEL: Readonly<Record<SessionReason, string>> = {
  approval: 'Needs approval',
  question: 'Has a question',
  plan: 'Plan to review',
  paused: 'Paused',
  breaker: 'Paused by the breaker',
  budget: 'Stopped by a budget',
  interrupted: 'Interrupted, resumable',
};

/** The states the daemon's session list writes, as the runtime names them. */
const STATE = { working: 'working', open: 'open', paused: 'paused' } as const;

export interface StatusFacts {
  readonly state: string | undefined;
  readonly thinking: boolean;
  /** Why the breaker paused it, present only on a session read up close. */
  readonly paused?: string | undefined;
  readonly waitingOnYou?: number;
}

/** The first that holds wins, because a pause or a question for the person matters more than activity. */
export function sessionStatus({ state, thinking, paused, waitingOnYou = 0 }: StatusFacts): SessionStatus {
  if (paused !== undefined || state === STATE.paused) return 'stopped';
  if (waitingOnYou > 0) return 'needs-you';
  if (thinking || state === STATE.working) return 'working';
  // Its turn is over and it handed back, which is news the person has not read yet.
  return state === STATE.open ? 'finished' : 'idle';
}

const STATUS_LABEL: Readonly<Record<SessionStatus, string>> = {
  'needs-you': 'Needs you',
  stopped: 'Stopped',
  working: 'Working',
  finished: 'Finished',
  idle: 'Idle',
};

/** The words on the session's badge. */
export function statusLabel(status: SessionStatus): string {
  return STATUS_LABEL[status];
}

/** Whether the agent is busy right now, which is what makes a card glow and a logo sit beside the notch. */
export function isActive(status: SessionStatus): boolean {
  return status === 'working';
}

const STATUS_TINT: Readonly<Record<SessionStatus, string>> = {
  stopped: '#FF453A',
  'needs-you': '#FF9F0A',
  finished: '#FF9F0A',
  working: '#30D158',
  idle: '#9E9E9F',
};

/** The status colour, dark values as the island draws them: red stopped, amber waiting, green busy, grey otherwise. */
export function statusTint(status: SessionStatus): string {
  return STATUS_TINT[status];
}
