import { DAEMON_METHOD, type DaemonRequest, type DaemonResponse } from '@memnox/core/wire';
import { whyNotReadyFrom, type RuntimeSource } from '../domain/runtime-source';
import { isAtLeast, MINIMUM_RUNTIME, type RuntimeState } from '../domain/runtime-state';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { Runtime } from './ports/runtime';
import type { RequestIds } from './request-ids';

/** What the setup row shows: what it is doing now, the daemon's state, and why it is still not ready. */
export interface SetupState {
  readonly runtime: RuntimeState | undefined;
  readonly doing: string | undefined;
  readonly failed: string | undefined;
}

/** Long enough for a daemon on a cold computer to load its rules and answer, asked once a second. */
const SETTLE_ATTEMPTS = 30;
const SETTLE_MS = 1_000;
const UNKNOWN_METHOD = 'no method';
const NOT_INSTALLED = 'Memnox would not install, nor fetch the Node.js it runs on. Check you are online, or install Node.js from nodejs.org, then press Check again.';
const NOT_PROTECTED = 'Memnox could not put your agents under it. Press the button again in a moment.';

/**
 * Puts the Memnox runtime under the app with no terminal, ported from the Mac's `RuntimeInstaller`: finds
 * `memnox` or installs it, wires the computer the first time, starts the service, and brings one too old
 * up to date. The person only ever grants permissions; everything else happens here.
 */
export class Setup {
  private current: SetupState = { runtime: undefined, doing: undefined, failed: undefined };
  private readonly listeners = new Set<() => void>();
  private running: Promise<RuntimeState> | undefined;
  private source: RuntimeSource = { kind: 'npm' };

  constructor(
    private readonly link: DaemonLink,
    private readonly runtime: Runtime,
    private readonly ids: RequestIds,
    private readonly sleep: (ms: number) => Promise<void>,
  ) {}

  get state(): SetupState {
    return this.current;
  }

  observe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** Where the daemon stands: answering, and as new as the oldest runtime this app works with. */
  async check(): Promise<RuntimeState> {
    const pong = await this.ask(DAEMON_METHOD.PING);
    let state: RuntimeState = pong === undefined ? { kind: 'unreachable' } : stateOf(pong);
    // A runtime built from a checkout keeps its version while it gains methods, so the newest ones this app
    // needs are asked for too, as the Mac's `daemonVoice` does; only a plain unknown method counts.
    if (state.kind === 'ready' && (await this.lacks(DAEMON_METHOD.WAITING) || await this.lacks(DAEMON_METHOD.MACHINE))) state = { kind: 'too-old' };
    this.update({ runtime: state });
    return state;
  }

  /** Whether the daemon answered that it has no such method, which only an older Memnox does. */
  private async lacks(method: DaemonRequest['method']): Promise<boolean> {
    const response = await this.ask(method);
    return response !== undefined && !response.ok && (response.error ?? '').startsWith(UNKNOWN_METHOD);
  }

  /** The daemon ready for this app, or as close as it could get; one run at a time, shared by every caller. */
  ensure(): Promise<RuntimeState> {
    this.running ??= this.bringUp().finally(() => {
      this.running = undefined;
      this.update({ doing: undefined });
    });
    return this.running;
  }

  private async bringUp(): Promise<RuntimeState> {
    this.source = (await this.runtime.source?.().catch(() => undefined)) ?? { kind: 'npm' };
    let state = await this.check();
    if (state.kind === 'ready') return this.done(state);
    if (!(await this.runtime.found())) {
      this.update({ doing: 'Installing Memnox' });
      if (!(await this.runtime.install())) return this.done(state, NOT_INSTALLED);
    }
    if (state.kind === 'unreachable') {
      const wired = await this.runtime.wired();
      // The first time it wires every agent in observe, which records and enforces nothing until the person says.
      this.update({ doing: wired ? 'Starting the Memnox service' : 'Setting Memnox up on this computer' });
      await this.runtime.run(wired ? 'start' : 'setup');
      state = await this.settle();
    }
    if (state.kind === 'too-old') state = await this.updateAndSettle();
    return this.done(state);
  }

  /**
   * A daemon older than the app: a local checkout is restarted on the code its build just made, and a release
   * updates from npm, so neither ever swaps a local checkout for the published one.
   */
  private async updateAndSettle(): Promise<RuntimeState> {
    this.update({ doing: 'Updating Memnox' });
    if (this.source.kind === 'local') {
      await this.runtime.run('start');
      return this.settle();
    }
    await this.runtime.run('update');
    const state = await this.settle();
    // The daemon restarts itself on its new code; one that never ran as a service is started now.
    if (state.kind !== 'unreachable') return state;
    await this.runtime.run('start');
    return this.settle();
  }

  /** Brings a daemon too old for something the person asked for up to date, as the Account page's Update does. */
  bringUpToDate(): Promise<RuntimeState> {
    this.running ??= this.updateNow().finally(() => {
      this.running = undefined;
      this.update({ doing: undefined });
    });
    return this.running;
  }

  private async updateNow(): Promise<RuntimeState> {
    this.source = (await this.runtime.source?.().catch(() => undefined)) ?? this.source;
    return this.done(await this.updateAndSettle());
  }

  /** Puts the agents found here under Memnox, as the first run does; undefined when it went through, else why. */
  async protectAgents(): Promise<string | undefined> {
    if (this.running !== undefined) return 'Memnox is still starting up. Try again in a moment.';
    this.update({ doing: 'Putting your agents under Memnox' });
    const went = (await this.runtime.found()) && (await this.runtime.run('setup'));
    this.update({ doing: undefined });
    return went ? undefined : NOT_PROTECTED;
  }

  /** Asks again for a while, since a daemon just started takes a moment to answer. */
  private async settle(): Promise<RuntimeState> {
    let state: RuntimeState = { kind: 'unreachable' };
    for (let attempt = 0; attempt < SETTLE_ATTEMPTS; attempt += 1) {
      state = await this.check();
      if (state.kind === 'ready') return state;
      await this.sleep(SETTLE_MS);
    }
    return state;
  }

  private done(state: RuntimeState, failed = whyNotReadyFrom(state, this.source)): RuntimeState {
    this.update({ runtime: state, failed });
    return state;
  }

  private async ask(method: DaemonRequest['method']): Promise<DaemonResponse | undefined> {
    return requestOnce(this.link, { id: this.ids.next(), method }).catch(() => undefined);
  }

  private update(change: Partial<SetupState>): void {
    this.current = { ...this.current, ...change };
    for (const listener of this.listeners) listener();
  }
}

/** A ping read as the daemon's state: a refusal in its own words, or too old by version. */
function stateOf(pong: DaemonResponse): RuntimeState {
  if (!pong.ok && pong.error !== undefined && !pong.error.startsWith(UNKNOWN_METHOD)) return { kind: 'refused', why: pong.error };
  return isAtLeast(pong.version, MINIMUM_RUNTIME) ? { kind: 'ready' } : { kind: 'too-old' };
}
