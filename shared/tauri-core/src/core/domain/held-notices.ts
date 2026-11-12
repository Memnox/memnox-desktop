/**
 * The system notification for a held call, ported to the Mac's `HeldNotices`: one per call, identical holds folded
 * into the first, none for the call the island is already showing, and a click opens Governance on Approvals. It
 * says what waits and never answers it, since a yes is signed on the card and nowhere else.
 */

/** Whether the person wants them, kept with the app's other switches; on unless turned off. */
export const NOTICES_KEY = 'memnox.notices.held';
/** Set once the system was asked, so it is asked once, from Settings or the first held call, and never at launch. */
export const NOTICES_ASKED_KEY = 'memnox.notices.asked';

export const NOTICES_TITLE = 'Tell me when a call waits';
export const NOTICES_DETAIL = 'A system notification for each call held for you that the island is not already showing. Pressing it opens Approvals.';
export const NOTICES_DENIED = 'Notifications are turned off for Memnox in the system settings, so none can be shown.';

/** Where a click on one lands. */
export const NOTICE_OPENS = { destination: 'needs-you', tab: 'decide-now' } as const;

export interface NoticeCall {
  readonly subject: string;
  /** Who waits, such as "Claude Code" or "Claude Code on build-box". */
  readonly label: string;
  /** The exact command or call, as its card shows it. */
  readonly what: string;
}

export interface HeldNotice {
  /** The call it is for, so a later one can be told apart. */
  readonly subject: string;
  readonly title: string;
  readonly body: string;
}

export function noticeOf(call: NoticeCall): HeldNotice {
  return { subject: call.subject, title: `${call.label} is waiting on you`, body: call.what };
}

/** Two calls are the same hold when the same agent waits on the same thing. */
function sameHold(call: NoticeCall): string {
  return `${call.label}\u0000${call.what}`;
}

/**
 * Which calls still need a notification. It remembers every call it has met, so a call told again on a reconnect
 * is not said twice, and forgets one once it stops waiting, so the same hold raised later is said again.
 */
export class HeldNotices {
  private met = new Set<string>();
  /** The holds a notification or the island has already put in front of the person, while any call of them waits. */
  private said = new Set<string>();

  /** The notifications to post for the calls waiting now, oldest first, given the one the island shows, if it is showing one. */
  next(waiting: readonly NoticeCall[], onIsland: string | undefined): readonly HeldNotice[] {
    const waitingNow = new Set(waiting.map((call) => call.subject));
    this.met = new Set([...this.met].filter((subject) => waitingNow.has(subject)));
    const holdsNow = new Set(waiting.map(sameHold));
    this.said = new Set([...this.said].filter((hold) => holdsNow.has(hold)));
    const posted: HeldNotice[] = [];
    for (const call of waiting) {
      if (this.met.has(call.subject)) continue;
      this.met.add(call.subject);
      const hold = sameHold(call);
      if (this.said.has(hold)) continue;
      this.said.add(hold);
      if (call.subject !== onIsland) posted.push(noticeOf(call));
    }
    return posted;
  }
}
