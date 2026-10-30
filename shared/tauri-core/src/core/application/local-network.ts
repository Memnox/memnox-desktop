import { LAN_METHOD, type DaemonRequest, type DaemonResponse, type LanStatus } from '@memnox/core/wire';
import { Observed } from './observed';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/** How a press on the switch ended: done at once, proposed and waiting for a signature, or refused. */
export type LanOutcome = { kind: 'done' } | { kind: 'proposed'; id: string } | { kind: 'failed'; why: string };

/**
 * The local network as the runtime keeps it. It holds no rule: turning it off is done at once, since it
 * only narrows who reaches this computer, and turning it on is a proposal signed on the island.
 */
export class LocalNetwork extends Observed {
  private view: LanStatus | undefined;
  private failed = false;
  private pressing = false;

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
  ) {
    super();
  }

  get status(): LanStatus | undefined {
    return this.view;
  }

  get unreadable(): boolean {
    return this.failed;
  }

  get busy(): boolean {
    return this.pressing;
  }

  async refresh(): Promise<void> {
    const response = await this.ask({ method: LAN_METHOD.LAN_STATUS });
    this.failed = response === undefined || !response.ok;
    if (response?.lan !== undefined) this.view = response.lan;
    this.changed();
  }

  /** Off is immediate; on is only proposed, and holds once signed. */
  async set(on: boolean): Promise<LanOutcome> {
    this.pressing = true;
    this.changed();
    const response = await this.ask({ method: LAN_METHOD.LAN_SET, lanOn: on });
    this.pressing = false;
    if (response?.lan !== undefined) this.view = response.lan;
    this.changed();
    if (response === undefined) return { kind: 'failed', why: 'The runtime is not answering.' };
    if (!response.ok) return { kind: 'failed', why: response.error ?? 'The runtime refused this.' };
    if (response.proposed !== undefined) return { kind: 'proposed', id: response.proposed };
    return { kind: 'done' };
  }

  private async ask(fields: Omit<DaemonRequest, 'id'>): Promise<DaemonResponse | undefined> {
    try {
      // Cast is safe: both callers pass a local network method and only the fields it reads.
      return await requestOnce(this.link, { id: this.ids.next(), ...fields } as DaemonRequest);
    } catch {
      // A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
      return undefined;
    }
  }
}
