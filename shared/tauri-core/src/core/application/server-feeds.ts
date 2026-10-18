import { DAEMON_EVENT, DAEMON_METHOD, type DaemonEvent } from '@memnox/core/wire';
import { deliversFrom } from '../domain/machine-events';
import type { PairedServer } from '../domain/paired-machines';
import { OWN_DEVICES } from '../domain/quiet';
import { RESUBSCRIBE_MS, subscriptionEnd } from '../domain/relay/resubscribe';
import type { Diary } from './diary';
import type { DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';
import type { MachineTarget, TargetLink } from './target-link';

/** How long to wait, injected so a test runs a reconnect in no time. */
export type Wait = (ms: number) => Promise<void>;

/**
 * Every paired server listened to, not only the one picked, so none of their held calls is missed. Each event is
 * filtered by where it came from and remembered with its machine, so its answer goes back through the link it came
 * from. Ported from the Mac's `restoreMachine`, `listen(to:through:)` and `arrived(_:from:)`.
 */
export class ServerFeeds {
  private readonly listening = new Map<string, { stop: () => void }>();

  constructor(
    private readonly target: TargetLink,
    /** A link to one server over the relay. */
    private readonly linkFor: (machineId: string) => DaemonLink,
    private readonly ids: RequestIds,
    /** Each event that is delivered, with the server's name for its label. */
    private readonly deliver: (event: DaemonEvent, server: string) => void,
    private readonly wait: Wait,
    private readonly diary?: Diary,
  ) {}

  /** The servers kept now: each one registered and listened to, a forgotten one dropped, and the choice restored. */
  restore(servers: readonly PairedServer[], chosen: string | undefined): void {
    OWN_DEVICES.set(servers.map((server) => server.deviceId));
    for (const [machineId, feed] of this.listening) {
      if (servers.some((server) => server.machineId === machineId)) continue;
      feed.stop();
      this.listening.delete(machineId);
      this.target.unregister(machineId);
    }
    for (const server of servers) {
      const machine: MachineTarget = { kind: 'server', machineId: server.machineId, deviceId: server.deviceId, name: server.machine };
      if (!this.listening.has(server.machineId)) {
        const link = this.linkFor(server.machineId);
        this.target.register(machine, link);
        this.listening.set(server.machineId, this.listen(machine, link));
      }
    }
    const wanted = servers.find((server) => server.machineId === chosen);
    const now = this.target.target;
    if (wanted === undefined) {
      if (now.kind === 'server') this.target.choose({ kind: 'this-computer' });
    } else if (now.kind !== 'server' || now.machineId !== wanted.machineId) {
      this.target.choose({ kind: 'server', machineId: wanted.machineId, deviceId: wanted.deviceId, name: wanted.machine });
    }
  }

  /** Reconnects after the server's daemon restarts or its relay drops, until the server is forgotten. */
  private listen(machine: MachineTarget & { kind: 'server' }, link: DaemonLink): { stop: () => void } {
    let stopped = false;
    let lines: AsyncIterator<unknown> | undefined;
    const run = async () => {
      while (!stopped) {
        let end: unknown;
        try {
          const iterator = link.stream({ id: this.ids.next(), method: DAEMON_METHOD.SUBSCRIBE })[Symbol.asyncIterator]();
          lines = iterator;
          for (;;) {
            const next = await iterator.next();
            if (next.done === true || stopped) break;
            const event = next.value.event;
            if (event !== undefined) this.arrived(event, machine);
          }
        } catch (error) {
          end = error;
        }
        if (stopped) return;
        this.diary?.note(`the feed from ${machine.name} ended, so it opens again`);
        await this.wait(RESUBSCRIBE_MS[subscriptionEnd(end)]);
      }
    };
    void run();
    return {
      stop: () => {
        stopped = true;
        void lines?.return?.();
      },
    };
  }

  private arrived(event: DaemonEvent, machine: MachineTarget & { kind: 'server' }): void {
    const chosen = this.target.target.kind === 'server' && this.target.target.machineId === machine.machineId;
    if (!deliversFrom(event, chosen, false)) return;
    this.target.remember(event.subject, machine);
    this.deliver(event, machine.name);
    if (event.kind === DAEMON_EVENT.SETTLED) this.target.forget(event.subject);
  }
}
