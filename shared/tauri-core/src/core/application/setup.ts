import { DAEMON_METHOD, type DaemonRequest, type DaemonResponse } from '@memnox/core/wire';
import { isAtLeast, MINIMUM_RUNTIME, whyNotReady, type RuntimeState } from '../domain/runtime-state';
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
const NOT_INSTALLED = 'Memnox needs Node.js to install. Install it from nodejs.org, then press Check again.';
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
    const state = pong === undefined ? { kind: 'unreachable' as const } : stateOf(pong);
    this.update({ runtime: state });
    return state;
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
    if (state.kind === 'too-old') {
      this.update({ doing: 'Updating Memnox' });
      await this.runtime.run('update');
      state = await this.settle();
      // The daemon restarts itself on its new code; one that never ran as a service is started now.
      if (state.kind === 'unreachable') {
        await this.runtime.run('start');
        state = await this.settle();
      }
    }
    return this.done(state);
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
    this.update({ doing: 'Updating Memnox' });
    await this.runtime.run('update');
    let state = await this.settle();
    if (state.kind === 'unreachable') {
      await this.runtime.run('start');
      state = await this.settle();
    }
    return this.done(state);
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

  private done(state: RuntimeState, failed = whyNotReady(state)): RuntimeState {
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
