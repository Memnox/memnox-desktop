import { DAEMON_METHOD, type DaemonRequest, type DaemonResponse } from '@memnox/core/wire';
import type { AgentWork, Tracker } from '../domain/agent-wire';
import { answeredLine, filled, startedLine } from '../domain/agent-work-lines';
import { Observed } from './observed';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/** How a press on agent work ended, said in a line above the page. */
export type WorkOutcome = { kind: 'done'; note: string } | { kind: 'failed'; why: string };

/**
 * Agent work as the daemon keeps it: issues in a tracker a person pointed a profile's agent at. Starting, stopping,
 * closing and answering a handoff are unsigned steers, since each only points or stops an agent; the daemon decides.
 * Mirrors the Mac's `AgentWorkDesk`.
 */
export class AgentWorkDesk extends Observed {
  private list: readonly AgentWork[] | undefined;
  private failed = false;
  private busyWith: string | undefined;

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
  ) {
    super();
  }

  get work(): readonly AgentWork[] | undefined {
    return this.list;
  }

  get unreadable(): boolean {
    return this.failed;
  }

  get busy(): string | undefined {
    return this.busyWith;
  }

  async refresh(): Promise<void> {
    const response = await this.ask({ method: DAEMON_METHOD.WORK });
    this.failed = response === undefined || !response.ok;
    if (response?.agentWork !== undefined) this.list = response.agentWork;
    this.changed();
  }

  /** A work event's piece of work, put in place of the one it replaces and moved to the top, with no read. */
  heard(changed: AgentWork): void {
    if (this.list === undefined) return;
    this.list = [changed, ...this.list.filter((each) => each.id !== changed.id)];
    this.changed();
  }

  start(profile: string, target: string, extra: { tracker?: Tracker; title?: string; project?: string } = {}): Promise<WorkOutcome> {
    const title = filled(extra.title);
    const project = filled(extra.project);
    return this.change(
      target,
      {
        method: DAEMON_METHOD.WORK_START,
        workProfile: profile,
        workTarget: target.trim(),
        ...(extra.tracker === undefined ? {} : { workTracker: extra.tracker }),
        ...(title === undefined ? {} : { workTitle: title }),
        ...(project === undefined ? {} : { workProject: project }),
      },
      () => startedLine(target),
    );
  }

  stop(id: string): Promise<WorkOutcome> {
    return this.change(id, { method: DAEMON_METHOD.WORK_STOP, workId: id }, () => 'Stopped. The agent is told to put it down.');
  }

  /** Closes it as done, which is the person's word once they checked what the agent claimed. */
  close(id: string): Promise<WorkOutcome> {
    return this.change(id, { method: DAEMON_METHOD.WORK_CLOSE, workId: id }, () => 'Closed as done.');
  }

  answer(handoff: string, word: 'accept' | 'decline'): Promise<WorkOutcome> {
    return this.change(handoff, { method: DAEMON_METHOD.HANDOFF_ANSWER, handoffId: handoff, handoffAnswer: word }, () => answeredLine(word));
  }

  private async change(subject: string, fields: Omit<DaemonRequest, 'id'>, done: (response: DaemonResponse) => string): Promise<WorkOutcome> {
    this.busyWith = subject;
    this.changed();
    const response = await this.ask(fields);
    this.busyWith = undefined;
    if (response?.agentWork !== undefined) this.list = response.agentWork;
    this.changed();
    if (response === undefined) return { kind: 'failed', why: 'The runtime is not answering.' };
    if (!response.ok) return { kind: 'failed', why: response.error ?? 'The runtime refused this.' };
    return { kind: 'done', note: done(response) };
  }

  private async ask(fields: Omit<DaemonRequest, 'id'>): Promise<DaemonResponse | undefined> {
    try {
      // Cast is safe: every caller passes a work method and only the fields it reads.
      return await requestOnce(this.link, { id: this.ids.next(), ...fields } as DaemonRequest);
    } catch {
      // A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
      return undefined;
    }
  }
}
