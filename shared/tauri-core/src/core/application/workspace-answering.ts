import { confirmationMessage, HOLD_ANSWER, type HoldAnswer, type TeamCallBrief } from '@memnox/core/wire';
import { EarlierAnswer } from '../domain/earlier-answer';
import { WorkspaceLines } from '../domain/workspace-lines';
import { callBrief, callExpiry, callSettledLine, isSettled, type WorkspaceHeldCall } from '../domain/workspace-wire';
import type { Diary } from './diary';
import type { HeldOutcome } from './held-calls';
import type { ConfirmKey } from './ports/confirm-key';
import { WorkspaceInboxError, type PersonCredentialStore, type WorkspaceInbox } from './ports/workspace-inbox';

/** What a poll of the inbox changed: calls that started waiting on the person, and calls that stopped. */
export interface InboxChange {
  readonly arrived: readonly WorkspaceHeldCall[];
  /** The ids of calls answered, run out or withdrawn since the last poll. */
  readonly gone: readonly string[];
  /** The workspace refused the credential, so the person has to sign in again. */
  readonly signedOut: boolean;
  /** Of the calls gone, those the workspace said were answered by somebody else, with who and where, by id. */
  readonly answeredElsewhere: ReadonlyMap<string, string>;
}

/** Far more than are ever answered between two polls, and still a bound on a set nothing else empties. */
const ANSWERED_KEPT = 200;

const byAsked = (a: WorkspaceHeldCall, b: WorkspaceHeldCall): number => (a.askedAt === b.askedAt ? (a.id < b.id ? -1 : 1) : a.askedAt < b.askedAt ? -1 : 1);

/**
 * The held calls teammates' agents raised that the workspace routed to this person, and the answers to them. A yes
 * goes only with a signature by the confirm key over exactly that call and that answer; a deny goes unsigned, since
 * saying no can do no harm. Every answer goes through the workspace and never through any daemon link.
 * Ported from the Mac's `WorkspaceAnswering`.
 */
export class WorkspaceAnswering {
  /** Every call shown and not yet settled, with the workspace that holds it, by id. */
  private open = new Map<string, { workspace: string; call: WorkspaceHeldCall }>();
  /** Calls answered here, so one the inbox still lists for a moment is not shown again. */
  private readonly answeredHere = new Set<string>();

  constructor(
    private readonly inbox: WorkspaceInbox,
    private readonly store: PersonCredentialStore,
    private readonly key: ConfirmKey,
    private readonly now: () => number = Date.now,
    private readonly diary?: Diary,
  ) {}

  /** Whether a subject is one of the workspace's calls, so its answer goes here rather than to a machine. */
  owns(subject: string): boolean {
    return this.open.has(subject);
  }

  call(subject: string): WorkspaceHeldCall | undefined {
    return this.open.get(subject)?.call;
  }

  /** Every call still waiting on the person, oldest first, as an ask names them to the voice; empty once signed out. */
  briefs(): TeamCallBrief[] {
    return [...this.open.values()].map((entry) => entry.call).sort(byAsked).map(callBrief);
  }

  /** Reads every workspace's inbox once. A workspace that did not answer keeps what it showed, so a dropped poll never makes a call flicker. */
  async refresh(): Promise<InboxChange> {
    const credential = await this.store.load().catch(() => undefined);
    if (credential === undefined) return { arrived: [], gone: this.forgetAll(), signedOut: false, answeredElsewhere: new Map() };
    const moment = this.now();
    const fresh = new Map<string, { workspace: string; call: WorkspaceHeldCall }>();
    const answered = new Set<string>();
    const settled = new Map<string, string>();
    for (const workspace of credential.workspaces) {
      try {
        const calls = await this.inbox.held(workspace, credential.token);
        answered.add(workspace);
        for (const call of calls) {
          if (isSettled(call)) settled.set(call.id, callSettledLine(call));
          // A yes already counted toward a quorum is this person's part done, so it stops asking them.
          else if (!call.approvedByYou && (callExpiry(call) ?? Infinity) > moment) fresh.set(call.id, { workspace, call });
        }
      } catch (error) {
        if (error instanceof WorkspaceInboxError && error.failure.kind === 'signed-out') {
          return { arrived: [], gone: this.forgetAll(), signedOut: true, answeredElsewhere: new Map() };
        }
        this.diary?.note(`reading the team inbox for ${workspace} failed: ${String(error)}`);
      }
    }
    return this.merge(fresh, answered, settled);
  }

  /** Puts a poll in place of what was open, and says what came and went and who answered what went. */
  private merge(polled: Map<string, { workspace: string; call: WorkspaceHeldCall }>, answered: Set<string>, settled: Map<string, string>): InboxChange {
    const fresh = new Map([...polled].filter(([id]) => !this.answeredHere.has(id)));
    for (const [id, entry] of this.open) if (!answered.has(entry.workspace)) fresh.set(id, entry);
    const gone = [...this.open.keys()].filter((id) => !fresh.has(id)).sort();
    // Only calls this computer was showing, since one answered here is gone from the open list already.
    const answeredElsewhere = new Map([...settled].filter(([id]) => gone.includes(id)));
    const arrived = [...fresh.values()].map((entry) => entry.call).filter((call) => !this.open.has(call.id)).sort(byAsked);
    this.open = fresh;
    return { arrived, gone, signedOut: false, answeredElsewhere };
  }

  /** Every call forgotten, for a sign out; returns the ids that were showing. */
  forgetAll(): string[] {
    const ids = [...this.open.keys()].sort();
    this.open.clear();
    return ids;
  }

  /**
   * One answer: the confirm key over exactly this call and answer for a yes, nothing for a deny. `signed` is a
   * signature over that same message already taken, so a yes the voice heard asks once rather than twice.
   */
  async answer(subject: string, answer: HoldAnswer, reason: string, signed?: string): Promise<HeldOutcome> {
    const entry = this.open.get(subject);
    if (entry === undefined) return { kind: 'failed', why: WorkspaceLines.gone };
    const credential = await this.store.load().catch(() => undefined);
    if (credential === undefined) return { kind: 'failed', why: WorkspaceLines.signedOut };
    let signature: string | undefined;
    if (answer !== HOLD_ANSWER.DENY) {
      signature = signed ?? (await this.key.sign(confirmationMessage(subject, answer), reason).catch(() => undefined));
      if (signature === undefined) return { kind: 'cancelled' };
    }
    try {
      const reply = await this.inbox.answer(subject, entry.workspace, answer, credential.deviceId, signature, credential.token);
      this.settle(subject);
      this.diary?.note(`answered the team's ${subject} ${answer}: ${reply.status}`);
      return { kind: 'answered' };
    } catch (error) {
      const failure = error instanceof WorkspaceInboxError ? error.failure : undefined;
      switch (failure?.kind) {
        case 'settled':
        case 'not-found':
          // Somebody else's answer, or the machine stopped waiting; the workspace no longer says which.
          this.settle(subject);
          return { kind: 'answered-elsewhere', earlier: EarlierAnswer.unknown() };
        case 'not-reached':
          return { kind: 'failed', why: WorkspaceLines.notReached };
        case 'signed-out':
          return { kind: 'failed', why: WorkspaceLines.signedOut };
        default:
          this.diary?.note(`answering the team's ${subject} failed: ${String(error)}`);
          return { kind: 'failed', why: WorkspaceLines.unreachable };
      }
    }
  }

  private settle(subject: string): void {
    this.open.delete(subject);
    if (this.answeredHere.size >= ANSWERED_KEPT) this.answeredHere.clear();
    this.answeredHere.add(subject);
  }
}
