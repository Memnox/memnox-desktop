import type { DaemonRequest } from '@memnox/core/wire';
import { Observed } from './observed';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/**
 * Which daemon methods this computer's runtime answers, asked once each. A runtime older than the
 * window refuses a method it does not know, and the tab that needs it stays hidden rather than broken.
 */
export class DaemonSupport extends Observed {
  private readonly known = new Map<string, boolean>();
  private readonly asking = new Set<string>();

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
  ) {
    super();
  }

  /** True or false once asked; undefined before, which also starts the asking. */
  supports(method: string): boolean | undefined {
    const answer = this.known.get(method);
    if (answer === undefined) void this.probe(method);
    return answer;
  }

  /** Asks again, after the runtime was updated or restarted. */
  forget(): void {
    this.known.clear();
    this.changed();
  }

  private async probe(method: string): Promise<void> {
    if (this.asking.has(method)) return;
    this.asking.add(method);
    let answered = false;
    try {
      // Cast is checked by the daemon itself: an unknown method comes back refused, which is the answer sought.
      const request = { id: this.ids.next(), method } as DaemonRequest;
      const response = await requestOnce(this.link, request);
      answered = response.ok;
    } catch {
      // No daemon at all reads as not supported, and the next forget asks again.
      answered = false;
    }
    this.asking.delete(method);
    this.known.set(method, answered);
    this.changed();
  }
}
