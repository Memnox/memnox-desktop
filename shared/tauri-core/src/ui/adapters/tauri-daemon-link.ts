import { Channel, invoke } from '@tauri-apps/api/core';
import { encode, type DaemonRequest, type DaemonResponse } from '@memnox/core/wire';
import type { DaemonLink } from '../../core';

/** The daemon over the Rust link: the request goes as the runtime encodes it, and each line comes back through a channel. */
export class TauriDaemonLink implements DaemonLink {
  async *stream(request: DaemonRequest): AsyncIterable<DaemonResponse> {
    const queue: DaemonResponse[] = [];
    let wake: (() => void) | undefined;
    let ended = false;
    let failure: unknown;
    const lines = new Channel<string>();
    lines.onmessage = (line) => {
      queue.push(JSON.parse(line) as DaemonResponse);
      wake?.();
    };
    invoke('daemon_stream', { request: encode(request).trimEnd(), lines })
      .catch((error: unknown) => {
        failure = error;
      })
      .finally(() => {
        ended = true;
        wake?.();
      });
    while (true) {
      const next = queue.shift();
      if (next !== undefined) {
        yield next;
        continue;
      }
      if (ended) break;
      await new Promise<void>((resolve) => {
        wake = resolve;
      });
      wake = undefined;
    }
    if (failure !== undefined) throw new Error(String(failure));
  }
}
