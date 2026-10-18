import { DAEMON_METHOD, type DaemonMethod, type DaemonResponse, type MachineStanding, type PersonSignInCode, type PersonStanding } from '@memnox/core/wire';
import { AccountWholeLines, type DaemonAccountStep } from '../domain/account-whole';
import { Observed, type Sleep } from './observed';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/** Which of the daemon's two sign ins is driven; both answer in the same shape, so only the methods differ. */
export type SignInSide = 'person' | 'machine';

const SIDES: Record<SignInSide, { ask: DaemonMethod; begin: DaemonMethod; end: DaemonMethod; unnamed: string }> = {
  person: { ask: DAEMON_METHOD.PERSON, begin: DAEMON_METHOD.PERSON_SIGN_IN, end: DAEMON_METHOD.PERSON_SIGN_OUT, unnamed: 'you' },
  machine: { ask: DAEMON_METHOD.MACHINE, begin: DAEMON_METHOD.MACHINE_SIGN_IN, end: DAEMON_METHOD.MACHINE_SIGN_OUT, unnamed: 'your workspace' },
};

type Standing = PersonStanding | MachineStanding;

/** How the daemon answered a request to sign in. */
export type SignInStart =
  | { kind: 'started'; code: PersonSignInCode }
  | { kind: 'signed-in'; name: string }
  | { kind: 'refused'; why: string }
  | { kind: 'too-old' }
  | { kind: 'unreachable' };

/** How watching a code ended. */
export type SignInWatch = { kind: 'signed-in'; name: string } | { kind: 'failed'; why: string } | { kind: 'expired' };

/** What a daemon says about a method it does not have, the same prefix setup reads. */
const UNKNOWN_METHOD = 'no method';
/** How often the daemon is asked whether the code was approved, close to the cloud's own five seconds. */
export const SIGN_IN_POLL_MS = 3_000;
const REFUSED = 'Memnox would not start the sign in.';
const STOPPED = 'Memnox stopped waiting on that code. Start again for a new one.';

/**
 * Signs the daemon in and out, ported from the Mac's `DaemonSignIn`: the daemon runs the code flow and keeps
 * the credential, and this only carries the person's wish and shows them the code.
 */
export class DaemonSignIn {
  constructor(
    private readonly link: DaemonLink,
    private readonly side: SignInSide,
    private readonly ids: RequestIds,
    private readonly sleep: Sleep,
    private readonly now: () => number = Date.now,
  ) {}

  /** Where it stands, undefined when nothing answered or the daemon does not know the question. */
  async standing(): Promise<Standing | undefined> {
    const response = await this.ask(SIDES[this.side].ask);
    return response === undefined ? undefined : this.standingOf(response);
  }

  /** Whether the daemon knows this sign in at all; undefined when nothing answered, which is not too old. */
  async isKnown(): Promise<boolean | undefined> {
    const response = await this.ask(SIDES[this.side].ask);
    return response === undefined ? undefined : !unknownMethod(response);
  }

  async begin(name?: string): Promise<SignInStart> {
    const request = { id: this.ids.next(), method: SIDES[this.side].begin, ...(name !== undefined && name !== '' ? { name } : {}) };
    const response = await requestOnce(this.link, request).catch(() => undefined);
    if (response === undefined) return { kind: 'unreachable' };
    if (unknownMethod(response)) return { kind: 'too-old' };
    const standing = this.standingOf(response);
    if (response.ok && standing !== undefined) {
      if (standing.code !== undefined) return { kind: 'started', code: standing.code };
      if (standing.signedIn) return { kind: 'signed-in', name: standing.name ?? SIDES[this.side].unnamed };
    }
    return { kind: 'refused', why: refusal(response) };
  }

  /** Asks every few seconds until the code was approved, the daemon gave up, or the code ran out. */
  async watch(code: PersonSignInCode, cancelled: () => boolean = () => false): Promise<SignInWatch> {
    while (this.now() < code.expiresAt) {
      await this.sleep(SIGN_IN_POLL_MS);
      if (cancelled()) return { kind: 'failed', why: 'Signing in was stopped.' };
      // A dropped request is asked again on the next interval, since the daemon is still polling.
      const standing = await this.standing();
      if (standing === undefined) continue;
      if (standing.signedIn) return { kind: 'signed-in', name: standing.name ?? SIDES[this.side].unnamed };
      if (standing.failed !== undefined && standing.failed !== '') return { kind: 'failed', why: standing.failed };
      if (standing.code === undefined) return { kind: 'failed', why: STOPPED };
    }
    return { kind: 'expired' };
  }

  async signOut(): Promise<boolean> {
    const response = await this.ask(SIDES[this.side].end);
    return response?.ok === true;
  }

  get unnamed(): string {
    return SIDES[this.side].unnamed;
  }

  private standingOf(response: DaemonResponse): Standing | undefined {
    return this.side === 'person' ? response.person : response.machine;
  }

  private ask(method: DaemonMethod): Promise<DaemonResponse | undefined> {
    return requestOnce(this.link, { id: this.ids.next(), method }).catch(() => undefined);
  }
}

function unknownMethod(response: DaemonResponse): boolean {
  return !response.ok && (response.error ?? '').startsWith(UNKNOWN_METHOD);
}

function refusal(response: DaemonResponse): string {
  for (const words of [response.reason, response.error]) if (words !== undefined && words !== '') return words;
  return REFUSED;
}

/** About half a minute, which a machine's own approval and its first poll take well within. */
const FOLLOW_TRIES = 10;
const FOLLOW_MS = 3_000;

/**
 * One of the daemon's sign ins as a row draws it, ported from the Mac's `DaemonAccountModel`. Each start
 * carries its own attempt, so a code cancelled or replaced reports nothing when its watch finally ends.
 */
export class DaemonAccount extends Observed {
  private current: DaemonAccountStep = { kind: 'unknown' };
  private attempt = 0;

  constructor(
    private readonly signIn: DaemonSignIn,
    private readonly sleep: Sleep,
    private readonly openPage: (url: string) => void,
  ) {
    super();
  }

  get step(): DaemonAccountStep {
    return this.current;
  }

  get isSignedIn(): boolean {
    return this.current.kind === 'signed-in';
  }

  /** Reads where the daemon stands, which is cheap, so the page is right whenever it opens. */
  async refresh(): Promise<void> {
    if (this.current.kind === 'showing-code' || this.current.kind === 'starting') return;
    const standing = await this.signIn.standing();
    if (standing === undefined) {
      const known = await this.signIn.isKnown();
      this.set(known === undefined ? { kind: 'failed', why: AccountWholeLines.unreachable } : known ? { kind: 'signed-out' } : { kind: 'too-old' });
      return;
    }
    if (standing.signedIn) this.set({ kind: 'signed-in', name: standing.name ?? this.signIn.unnamed });
    else if (standing.failed !== undefined && standing.failed !== '') this.set({ kind: 'failed', why: standing.failed });
    else this.set({ kind: 'signed-out' });
  }

  /** Asks for a code, opens the console on it, and waits for the person to approve it there. */
  async start(name?: string): Promise<void> {
    const attempt = this.next();
    this.set({ kind: 'starting' });
    const start = await this.signIn.begin(name);
    if (attempt !== this.attempt) return;
    switch (start.kind) {
      case 'started': {
        this.set({ kind: 'showing-code', code: start.code.userCode });
        if (start.code.page !== undefined) this.openPage(start.code.page);
        const watched = await this.signIn.watch(start.code, () => attempt !== this.attempt);
        if (attempt !== this.attempt) return;
        if (watched.kind === 'signed-in') this.set({ kind: 'signed-in', name: watched.name });
        else this.set({ kind: 'failed', why: watched.kind === 'failed' ? watched.why : AccountWholeLines.expired });
        return;
      }
      case 'signed-in':
        return this.set({ kind: 'signed-in', name: start.name });
      case 'refused':
        return this.set({ kind: 'failed', why: start.why });
      case 'too-old':
        return this.set({ kind: 'too-old' });
      case 'unreachable':
        return this.set({ kind: 'failed', why: AccountWholeLines.unreachable });
    }
  }

  /** Asks a daemon already signed in to complete what it carries, which connects this computer with no browser. */
  async complete(name?: string): Promise<void> {
    await this.signIn.begin(name);
    await this.refresh();
  }

  /** Reads again every few seconds until signed in, since the daemon connects this computer on its own. */
  async follow(): Promise<void> {
    for (let tries = 0; tries < FOLLOW_TRIES; tries += 1) {
      await this.refresh();
      if (this.isSignedIn) return;
      await this.sleep(FOLLOW_MS);
    }
  }

  cancel(): void {
    this.next();
    this.set({ kind: 'signed-out' });
  }

  async signOut(): Promise<void> {
    this.next();
    const out = await this.signIn.signOut();
    this.set(out ? { kind: 'signed-out' } : { kind: 'failed', why: AccountWholeLines.unreachable });
  }

  private next(): number {
    this.attempt += 1;
    return this.attempt;
  }

  private set(step: DaemonAccountStep): void {
    this.current = step;
    this.changed();
  }
}
