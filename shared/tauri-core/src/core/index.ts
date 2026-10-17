/** The core every desktop screen draws from: no DOM, no Tauri, only the daemon, the key and the voice through ports. */
export { HeldCalls, type HeldOutcome, type HeldState } from './application/held-calls';
export { RequestIds } from './application/request-ids';
export { ProposalCards } from './application/proposal-cards';
export { NO_KEY_LINE, Signer, type Signing } from './application/signer';
export { ANSWER_WINDOW_MS, Talking, type Timer, type TalkingOptions, type TalkState } from './application/talking';
export { Wakefulness } from './application/wakefulness';
export type { ConfirmKey } from './application/ports/confirm-key';
export { DaemonClosed, requestOnce, type DaemonLink } from './application/ports/daemon-link';
export type { Power } from './application/ports/power';
export type { Speaker } from './application/ports/speaker';
export { consentReason, THIS_COMPUTER } from './domain/call-label';
export { EarlierAnswer } from './domain/earlier-answer';
export type { HeldCard } from './domain/held-card';
export { accountWarning, draftAudience, suggestedScope, type ProposalCard } from './domain/proposal-card';
export { ANOTHER_KEY_LINE, type KeyStatus } from './domain/key-status';
export { OrbMotion, orbFit, type OrbState, type OrbUniforms, type Reaction } from './domain/orb-motion';
export { WaitingCalls, type WaitingEntry } from './domain/waiting-calls';
