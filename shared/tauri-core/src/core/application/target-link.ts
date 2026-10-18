import type { DaemonRequest, DaemonResponse } from '@memnox/core/wire';
import { remoteAllows } from '../domain/remote-reach';
import type { Diary } from './diary';
import type { DaemonLink } from './ports/daemon-link';

/** The machine the voice and the session views talk to: the daemon on this computer, or a server paired over the relay. */
export type MachineTarget =
  | { readonly kind: 'this-computer' }
  /** A server, with the device id this computer paired as there, which its events name when this computer asked. */
  | { readonly kind: 'server'; readonly machineId: string; readonly deviceId: string; readonly name: string };

export const THIS_COMPUTER_TARGET: MachineTarget = { kind: 'this-computer' };

/** Thrown into a request the link would not send, with why. */
export class Refused extends Error {}

/** Far more subjects than ever wait at once, and still a bound on a map nothing else empties. */
const SUBJECTS_KEPT = 1_000;

/**
 * A DaemonLink over whichever machine is chosen, so the conversation never knows which one it talks to. A request
 * about a subject some machine raised goes back to that machine whatever is chosen, so a held call from this
 * computer is answered here while a server is picked, and one from a server goes to that server. A server is
 * sent only what the remote reach allows, and a call the workspace routed is never sent to any daemon.
 * Ported from the Mac's `TargetLink`.
 */
export class TargetLink implements DaemonLink {
  private chosen: MachineTarget = THIS_COMPUTER_TARGET;
  private readonly servers = new Map<string, { target: MachineTarget; link: DaemonLink }>();
  private readonly raised = new Map<string, MachineTarget>();
  private readonly workspace = new Set<string>();
  /** Every stream that followed the choice and has not ended, so a change of machine ends them. */
  private readonly live = new Set<() => void>();

  constructor(
    private readonly local: DaemonLink,
    private readonly diary?: Diary,
  ) {}

  get target(): MachineTarget {
    return this.chosen;
  }

  get isRemote(): boolean {
    return this.chosen.kind === 'server';
  }

  /** A server this computer can reach, kept so its held calls are answered through its own link. */
  register(server: MachineTarget, link: DaemonLink): void {
    if (server.kind === 'server') this.servers.set(server.machineId, { target: server, link });
  }

  /** A server forgotten: nothing is routed to it again, and it stops being the target. */
  unregister(machineId: string): void {
    this.servers.delete(machineId);
    for (const [subject, machine] of this.raised) if (machine.kind === 'server' && machine.machineId === machineId) this.raised.delete(subject);
    if (this.chosen.kind === 'server' && this.chosen.machineId === machineId) this.choose(THIS_COMPUTER_TARGET);
  }

  /** Points at a server, or back at this computer; what was in flight on the old choice ends, answers to other machines carry on. */
  choose(target: MachineTarget): void {
    // A server with no link to reach it is no target at all, so it falls back to this computer.
    this.chosen = target.kind === 'server' && this.servers.has(target.machineId) ? target : THIS_COMPUTER_TARGET;
    const ending = [...this.live];
    this.live.clear();
    for (const end of ending) end();
    this.diary?.note(`talking to ${this.chosen.kind === 'server' ? this.chosen.name : 'this computer'}`);
  }

  /** The machine an event came from, so whatever answers its subject goes back there. */
  remember(subject: string, machine: MachineTarget): void {
    if (this.raised.size >= SUBJECTS_KEPT) this.raised.clear();
    this.raised.set(subject, machine);
  }

  /** A subject settled, so nothing more is routed by it. */
  forget(subject: string): void {
    this.raised.delete(subject);
    this.workspace.delete(subject);
  }

  /** A call the workspace routed to this person: no daemon raised it, so no daemon is ever sent its answer. */
  rememberWorkspace(subject: string): void {
    if (this.workspace.size >= SUBJECTS_KEPT) this.workspace.clear();
    this.workspace.add(subject);
    this.raised.delete(subject);
  }

  belongsToWorkspace(subject: string): boolean {
    return this.workspace.has(subject);
  }

  /** The machine that raised a subject, undefined when none was seen. */
  machineFor(subject: string): MachineTarget | undefined {
    return this.raised.get(subject);
  }

  /** The server's name a subject was raised on, undefined for this computer. */
  serverNameFor(subject: string): string | undefined {
    const machine = this.raised.get(subject);
    return machine?.kind === 'server' ? machine.name : undefined;
  }

  /** Whether an answer to this subject reaches a server, which takes no yes without a signature. */
  reachesAnotherMachine(subject: string): boolean {
    return (this.raised.get(subject) ?? this.chosen).kind === 'server';
  }

  stream(request: DaemonRequest): AsyncIterable<DaemonResponse> {
    const subject = request.subject;
    if (subject !== undefined && this.workspace.has(subject)) {
      return refused(`${subject} reached you through your team's workspace, so it is answered there and never through a machine's daemon`);
    }
    const { target, link, followsChoice } = this.route(request);
    if (target.kind === 'server' && !remoteAllows(request)) {
      return refused(`${request.method} belongs to this computer's own daemon, so it is not sent to a server`);
    }
    return followsChoice ? this.endedOnChange(link.stream(request)) : link.stream(request);
  }

  /** The machine that raised the request's subject when one did and is still reachable, else the one chosen. */
  private route(request: DaemonRequest): { target: MachineTarget; link: DaemonLink; followsChoice: boolean } {
    const machine = request.subject === undefined ? undefined : this.raised.get(request.subject);
    if (machine?.kind === 'this-computer') return { target: machine, link: this.local, followsChoice: false };
    if (machine?.kind === 'server') {
      const server = this.servers.get(machine.machineId);
      if (server !== undefined) return { target: server.target, link: server.link, followsChoice: false };
    }
    const server = this.chosen.kind === 'server' ? this.servers.get(this.chosen.machineId) : undefined;
    return server === undefined ? { target: THIS_COMPUTER_TARGET, link: this.local, followsChoice: true } : { target: server.target, link: server.link, followsChoice: true };
  }

  /** The stream until it ends or the choice changes, whichever comes first. */
  private async *endedOnChange(upstream: AsyncIterable<DaemonResponse>): AsyncIterable<DaemonResponse> {
    const lines = upstream[Symbol.asyncIterator]();
    let end: () => void = () => undefined;
    const changed = new Promise<'changed'>((resolve) => {
      end = () => resolve('changed');
    });
    this.live.add(end);
    try {
      for (;;) {
        const next = await Promise.race([lines.next(), changed]);
        if (next === 'changed' || next.done === true) return;
        yield next.value;
      }
    } finally {
      this.live.delete(end);
      // Not awaited, since a stream waiting on its next line would hold the change up until that line came.
      void lines.return?.();
    }
  }
}

function refused(why: string): AsyncIterable<DaemonResponse> {
  return {
    [Symbol.asyncIterator]: () => ({
      next: () => Promise.reject(new Refused(why)),
    }),
  };
}
