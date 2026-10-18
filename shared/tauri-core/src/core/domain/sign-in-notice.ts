import type { DaemonEvent } from '@memnox/core/wire';

/**
 * The sign in notices as the Mac's `SignedInNotice` reads them: one that finished reached an account and
 * carries on what was asked, and one that stalled reached none, which a company's approval screen is the
 * usual cause of. The words are the runtime's `NOTICE_KIND`, which the wire does not export.
 */
export const SIGN_IN_NOTICE = { SIGNED_IN: 'signed-in', STALLED: 'sign-in-stalled' } as const;

/** What a sign in notice carries: the tool, the account it reached, and what to carry on with. */
export type SignedInNotice = NonNullable<DaemonEvent['signedIn']>;
/** The account the brain says a sign in is for, as the Mac's `AccountClaim`, which the Not me flow reads. */
export type AccountClaim = NonNullable<DaemonEvent['claim']>;

/** A finished sign in can carry on what was asked for this long, as the Mac's `resumeWindow`. */
export const RESUME_WITHIN_MS = 60_000;

/** A sign in notice, finished or stalled, that hangs a pill under the island. */
export function isSignInNotice(event: DaemonEvent): boolean {
  return event.notice === SIGN_IN_NOTICE.SIGNED_IN || event.notice === SIGN_IN_NOTICE.STALLED;
}

/** Finished, as opposed to a sign in that never did, which reached no account. */
export function signInFinished(notice: SignedInNotice): boolean {
  return notice.account !== undefined;
}

/**
 * The person spoke after the sign in finished, or it is too old to pick up where it left off, so what they
 * asked before it is not asked again on top of something newer, as the Mac's `movedOn(since:)`.
 */
export function movedOn(at: string, lastHeard: number | undefined, now: number): boolean {
  const moment = Date.parse(at);
  if (Number.isNaN(moment)) return true;
  if (lastHeard !== undefined && lastHeard > moment) return true;
  return now - moment > RESUME_WITHIN_MS;
}
