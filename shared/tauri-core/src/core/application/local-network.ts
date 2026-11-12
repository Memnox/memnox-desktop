import { LAN_METHOD, type DaemonRequest, type DaemonResponse, type LanStatus } from '@memnox/core/wire';
import { Observed } from './observed';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/**
 * The local network as the runtime keeps it, read so Phones can say when pairing needs no account. Turning it on or off
 * is the runtime's, from the terminal, since this computer no longer keeps a page for it, as the Mac's `LocalNetwork`.
 */
export class LocalNetwork extends Observed {
  private view: LanStatus | undefined;
  private failed = false;

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

  async refresh(): Promise<void> {
    const response = await this.ask({ method: LAN_METHOD.LAN_STATUS });
    this.failed = response === undefined || !response.ok;
    if (response?.lan !== undefined) this.view = response.lan;
    this.changed();
  }

  private async ask(fields: Omit<DaemonRequest, 'id'>): Promise<DaemonResponse | undefined> {
    try {
      // Cast is safe: the one caller passes a local network method and only the fields it reads.
      return await requestOnce(this.link, { id: this.ids.next(), ...fields } as DaemonRequest);
    } catch {
      // A runtime that went away is said by `unreadable`, never thrown at the page.
      return undefined;
    }
  }
}
