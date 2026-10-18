import { DAEMON_EVENT, DISPLAY, type DaemonEvent, type ToolSignIn } from '@memnox/core/wire';
import { driveGrant, phoneVoice, type DriveGrant } from '../domain/driving';
import { isSignInNotice, SIGN_IN_NOTICE, signInFinished } from '../domain/sign-in-notice';
import { SIGNED_IN_FOR_MS } from '../domain/tool-brand';
import type { Timer } from './talking';

/** A sign in that finished, as its pill under the island shows it. */
export interface SignedInPill {
  readonly toolkit: string;
  readonly who: string | undefined;
  /** Nothing ties the account to the person yet, so the pill offers Not me. */
  readonly unverified: boolean;
  /** What the person asked before they signed in, asked again so it carries on. */
  readonly resume: string | undefined;
}

/** What hangs under the island in every mode, so it is seen whatever the island is doing. */
export interface NoticesState {
  /** Tools the person asked for and has not signed in to, one tap each. */
  readonly signIns: readonly ToolSignIn[];
  readonly signedIn: SignedInPill | undefined;
  readonly driving: DriveGrant | undefined;
  readonly phoneVoice: { readonly deviceId: string; readonly name: string } | undefined;
}

/**
 * The pills under the island, ported from the Mac's `IslandPanel`: the sign in row, the signed in
 * pill for a few seconds, a phone driving this computer for the length of its grant, and a phone
 * holding the voice. It reads the live feed and holds no policy.
 */
export class IslandNotices {
  private current: NoticesState = { signIns: [], signedIn: undefined, driving: undefined, phoneVoice: undefined };
  private readonly listeners = new Set<() => void>();
  private stopSignedIn: (() => void) | undefined;
  private stopDriving: (() => void) | undefined;

  constructor(
    private readonly timer: Timer,
    private readonly now: () => number = Date.now,
  ) {}

  get state(): NoticesState {
    return this.current;
  }

  observe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** One event of the live feed; anything that is not about these pills is left alone. */
  handle(event: DaemonEvent): void {
    if (event.kind === DAEMON_EVENT.SHOW && event.display === DISPLAY.SIGN_IN) this.update({ signIns: event.signIn ?? [] });
    if (event.kind !== DAEMON_EVENT.NOTICE) return;
    if (event.drivenBy !== undefined) this.drive(event);
    if (event.voiceOn !== undefined) this.update({ phoneVoice: phoneVoice(event.voiceOn) });
    // A stalled sign in hangs the same pill, with no account to name, as the Mac shows `signInStalled`.
    if (isSignInNotice(event) && event.signedIn !== undefined && (event.notice === SIGN_IN_NOTICE.STALLED || signInFinished(event.signedIn))) this.signedIn(event);
  }

  /** A tool's sign in was opened, or Not me was pressed, so its icon or its pill goes. */
  signingIn(toolkit: string): void {
    this.update({ signIns: this.current.signIns.filter((each) => each.toolkit !== toolkit) });
  }

  dismissSignedIn(): void {
    this.stopSignedIn?.();
    this.update({ signedIn: undefined });
  }

  private signedIn(event: DaemonEvent): void {
    const notice = event.signedIn;
    if (notice === undefined) return;
    const pill: SignedInPill = {
      toolkit: notice.toolkit,
      who: notice.account?.handle ?? notice.account?.name,
      unverified: notice.account?.check !== 'matched',
      resume: notice.resume,
    };
    this.stopSignedIn?.();
    this.update({ signIns: this.current.signIns.filter((each) => each.toolkit !== notice.toolkit), signedIn: pill });
    this.stopSignedIn = this.timer(pill.unverified ? SIGNED_IN_FOR_MS.unverified : SIGNED_IN_FOR_MS.verified, () => {
      if (this.current.signedIn === pill) this.update({ signedIn: undefined });
    });
  }

  /** The state stays up for the whole grant and goes at its time. */
  private drive(event: DaemonEvent): void {
    this.stopDriving?.();
    const grant = event.drivenBy === undefined ? undefined : driveGrant(event.drivenBy, this.now());
    this.update({ driving: grant });
    if (grant === undefined) return;
    this.stopDriving = this.timer(Math.max(0, grant.until - this.now()), () => {
      if (this.current.driving === grant) this.update({ driving: undefined });
    });
  }

  private update(change: Partial<NoticesState>): void {
    this.current = { ...this.current, ...change };
    for (const listener of this.listeners) listener();
  }
}
