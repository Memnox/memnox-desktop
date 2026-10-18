import { Channel, invoke } from '@tauri-apps/api/core';
import { encode, type DaemonRequest, type DaemonResponse } from '@memnox/core/wire';
import type { DaemonLink } from '../../core/application/ports/daemon-link';
import type { Paired, Pairer } from '../../core/application/ports/pairer';
import type { PairedServer } from '../../core/domain/paired-machines';
import { isLastLine } from '../../core/domain/relay/stream-end';
import type { PairingFailure } from '../../core/domain/server-pairing-lines';

/**
 * One paired server's daemon over the Rust relay link: the request goes as the runtime encodes it, each line comes
 * back through a channel, and the stream ends on the line its method ends with, which Rust is told so it stops routing.
 * A renewal on schedule ends it with `renewed`, so a listener opens again at once.
 */
export class TauriRelayLink implements DaemonLink {
  constructor(private readonly machineId: string) {}

  async *stream(request: DaemonRequest): AsyncIterable<DaemonResponse> {
    const stream = crypto.randomUUID();
    const queue: DaemonResponse[] = [];
    let wake: (() => void) | undefined;
    let ended = false;
    let failure: unknown;
    const lines = new Channel<string>();
    lines.onmessage = (line) => {
      queue.push(JSON.parse(line) as DaemonResponse);
      wake?.();
    };
    invoke('relay_stream', { machineId: this.machineId, request: encode(request).trimEnd(), stream, lines })
      .catch((error: unknown) => {
        failure = error;
      })
      .finally(() => {
        ended = true;
        wake?.();
      });
    try {
      for (;;) {
        const next = queue.shift();
        if (next !== undefined) {
          yield next;
          if (isLastLine(next, request.method)) return;
          continue;
        }
        if (ended) break;
        await new Promise<void>((resolve) => {
          wake = resolve;
        });
        wake = undefined;
      }
      if (failure !== undefined) throw new Error(String(failure));
    } finally {
      // Done with it, early or not, so the link stops routing to a channel nobody reads.
      if (!ended) void invoke('relay_done', { machineId: this.machineId, stream }).catch(() => undefined);
    }
  }
}

/** The pairing and the servers kept, through `relay.rs`; the keys and tokens stay there. */
export const tauriPairer: Pairer = {
  async pair(link, name, code): Promise<Paired> {
    const digits = new Channel<string>();
    digits.onmessage = code;
    try {
      const server = await invoke<PairedServer>('relay_pair', { link, name, code: digits });
      return { kind: 'paired', server };
    } catch (error) {
      const why = typeof error === 'object' && error !== null && 'kind' in error ? (error as PairingFailure) : ({ kind: 'broken', why: String(error) } as const);
      return { kind: 'failed', why };
    }
  },
  servers: () => invoke<PairedServer[]>('relay_servers'),
  forget: (machineId) => invoke<void>('relay_forget', { machineId }),
};
