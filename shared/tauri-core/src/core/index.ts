/** The core every desktop screen draws from: no DOM, no Tauri, only the daemon and the key through ports. */
export { HeldCalls, NO_KEY_LINE, type HeldOutcome, type HeldState } from './application/held-calls';
export { RequestIds } from './application/request-ids';
export type { ConfirmKey } from './application/ports/confirm-key';
export type { Power } from './application/ports/power';
export { Wakefulness } from './application/wakefulness';
export { DaemonClosed, requestOnce, type DaemonLink } from './application/ports/daemon-link';
export { consentReason, THIS_COMPUTER } from './domain/call-label';
export { EarlierAnswer } from './domain/earlier-answer';
export type { HeldCard } from './domain/held-card';
export { ANOTHER_KEY_LINE, type KeyStatus } from './domain/key-status';
export { WaitingCalls, type WaitingEntry } from './domain/waiting-calls';
