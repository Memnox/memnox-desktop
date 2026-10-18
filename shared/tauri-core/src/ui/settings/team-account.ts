import { Observed } from '../../core/application/observed';
import type { WorkspaceSignIn } from '../../core/application/workspace-sign-in';
import { codePage } from '../../core/domain/workspace-wire';

/** Where signing this app in as the person stands, from the code they approve in the console to signed in. Ported from the Mac's `AccountStep`. */
export type TeamStep =
  | { kind: 'signed-out' }
  /** Asking Memnox Cloud for a code. */
  | { kind: 'starting' }
  /** The code is up and the console page open, waiting for the person to approve it there. */
  | { kind: 'showing-code'; code: string }
  | { kind: 'signed-in'; name: string; workspaces: number }
  | { kind: 'failed'; why: string };

/**
 * Signs this app in to the person's Memnox Cloud workspace and out again, so the calls their workspace routes to
 * them reach the island and every yes is signed here. Ported from the Mac's `AccountModel`, without riding the
 * daemon's own sign in on the same code, which the Account page still runs on its own.
 */
export class TeamAccount extends Observed {
  private current: TeamStep = { kind: 'signed-out' };
  private attempt = 0;

  constructor(
    private readonly signIn: WorkspaceSignIn,
    private readonly name: () => string,
    private readonly openPage: (url: string) => void,
    /** Told whenever the person signs in or out, so the island starts or stops reading the inbox. */
    private readonly signedInOrOut: () => void,
  ) {
    super();
  }

  get step(): TeamStep {
    return this.current;
  }

  async load(): Promise<void> {
    if (this.current.kind === 'starting' || this.current.kind === 'showing-code') return;
    const credential = await this.signIn.current();
    this.set(credential === undefined ? { kind: 'signed-out' } : { kind: 'signed-in', name: credential.name, workspaces: credential.workspaces.length });
  }

  /** Shows the code and opens the console on it, then waits for the person to approve this computer there. */
  async start(): Promise<void> {
    const attempt = ++this.attempt;
    this.set({ kind: 'starting' });
    const outcome = await this.signIn.signIn(this.name(), (code) => {
      if (attempt !== this.attempt) return;
      this.set({ kind: 'showing-code', code: code.userCode });
      const page = codePage(code);
      if (page !== undefined) this.openPage(page);
    });
    if (attempt !== this.attempt) return;
    if (outcome.kind === 'signed-in') {
      this.set({ kind: 'signed-in', name: outcome.credential.name, workspaces: outcome.credential.workspaces.length });
      this.signedInOrOut();
    } else {
      this.set({ kind: 'failed', why: outcome.why });
    }
  }

  cancel(): void {
    this.attempt += 1;
    this.signIn.cancel();
    this.set({ kind: 'signed-out' });
  }

  async signOut(): Promise<void> {
    this.attempt += 1;
    await this.signIn.signOut();
    this.set({ kind: 'signed-out' });
    this.signedInOrOut();
  }

  private set(step: TeamStep): void {
    this.current = step;
    this.changed();
  }
}
