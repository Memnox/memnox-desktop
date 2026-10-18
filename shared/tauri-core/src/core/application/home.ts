import { DAEMON_METHOD, type DaemonRequest, type DaemonResponse, type HomeReady, type HomeView, type SessionCard } from '@memnox/core/wire';
import { Observed } from './observed';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';
import type { Timer } from './talking';

/** The counts the overview falls back to when the daemon has no home to give, as the Mac's menu counts them. */
export interface OverviewNumbers {
  readonly needYou: number;
  readonly working: number;
  readonly agents: number;
  readonly repositories: number;
}

/** A session state the daemon writes for one at work, as the island reads it. */
const WORKING = 'working';
/** Long enough for a burst of events to pass, so one read follows it rather than one per event, as the Mac's `settleSeconds`. */
export const HOME_SETTLE_MS = 1_500;

/** The fallback counts from what waits and the sessions lately. */
export function overviewNumbers(waiting: number, sessions: readonly SessionCard[]): OverviewNumbers {
  const live = sessions.filter((session) => session.state === WORKING || session.thinking);
  return {
    needYou: waiting,
    working: live.length,
    agents: new Set(sessions.map((session) => session.agent)).size,
    repositories: new Set(sessions.flatMap((session) => (session.repository === undefined ? [] : [session.repository]))).size,
  };
}

/**
 * The home the overview opens on, ported from the Mac's `HomeModel`: the daemon's five blocks read at once,
 * and what the ready and not covered buttons do. Read when the window comes forward, never on a timer.
 */
export class Home extends Observed {
  private read: HomeView | undefined;
  private numbersRead: OverviewNumbers = { needYou: 0, working: 0, agents: 0, repositories: 0 };
  private away = false;
  private handing = false;
  private handNote: string | undefined;
  private protectingNow = false;
  private protectWhy: string | undefined;
  /** Set while a read is due after a burst, so more events in the burst ask for nothing more. */
  private soon = false;

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
    private readonly protectAgents: () => Promise<string | undefined>,
    /** The read after a burst waits on this; without one it reads at once. */
    private readonly timer: Timer = (_, fire) => {
      fire();
      return () => undefined;
    },
  ) {
    super();
  }

  /** Undefined until the first read, and kept through a failed one so a daemon restarting does not blank the page. */
  get home(): HomeView | undefined {
    return this.read;
  }

  /** Set once a read came back empty: a daemon away, or one older than the home. */
  get unavailable(): boolean {
    return this.away;
  }

  get numbers(): OverviewNumbers {
    return this.numbersRead;
  }

  get handingOver(): boolean {
    return this.handing;
  }

  get handOverNote(): string | undefined {
    return this.handNote;
  }

  get protecting(): boolean {
    return this.protectingNow;
  }

  get protectFailed(): string | undefined {
    return this.protectWhy;
  }

  async refresh(): Promise<void> {
    const response = await this.ask({ id: this.ids.next(), method: DAEMON_METHOD.HOME });
    const home = response?.ok === true ? response.home : undefined;
    if (home !== undefined) this.read = home;
    this.away = home === undefined;
    if (this.away) await this.readNumbers();
    this.changed();
  }

  /** Something on the stream changed what the home counts: read once the burst has passed. */
  refreshSoon(): void {
    if (this.soon) return;
    this.soon = true;
    this.timer(HOME_SETTLE_MS, () => {
      this.soon = false;
      void this.refresh();
    });
  }

  /** Asks the daemon to propose the ready action as a rule; the proposal comes up on the island's rule card. */
  async handOver(ready: HomeReady, keyName: string): Promise<void> {
    if (this.handing) return;
    this.handing = true;
    this.handNote = undefined;
    this.changed();
    const response = await this.ask({ id: this.ids.next(), method: DAEMON_METHOD.HAND_OVER, action: ready.action });
    this.handing = false;
    if (response === undefined) this.handNote = 'Memnox did not answer. Check that it is running, then try again.';
    else if (response.ok && response.proposed !== undefined) this.handNote = `Pick where it holds on the island, then confirm with ${keyName}.`;
    else this.handNote = response.reason ?? response.error ?? 'Memnox would not propose that rule.';
    await this.refresh();
  }

  /** One press: every agent found here goes under Memnox through the runtime's own setup. */
  async protect(): Promise<void> {
    if (this.protectingNow) return;
    this.protectingNow = true;
    this.protectWhy = undefined;
    this.changed();
    this.protectWhy = await this.protectAgents();
    this.protectingNow = false;
    await this.refresh();
  }

  private async readNumbers(): Promise<void> {
    const [waiting, sessions] = await Promise.all([
      this.ask({ id: this.ids.next(), method: DAEMON_METHOD.WAITING }),
      this.ask({ id: this.ids.next(), method: DAEMON_METHOD.SESSIONS_LIST }),
    ]);
    this.numbersRead = overviewNumbers(waiting?.waiting?.length ?? 0, sessions?.sessions ?? []);
  }

  private ask(request: DaemonRequest): Promise<DaemonResponse | undefined> {
    return requestOnce(this.link, request).catch(() => undefined);
  }
}
