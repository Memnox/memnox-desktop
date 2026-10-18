import { accountWhole, type AccountWhole } from '../domain/account-whole';
import type { DaemonAccount } from './daemon-sign-in';
import { Observed } from './observed';

/**
 * The one sign in the Account page offers, as the Mac's `AccountModel` runs it: the person signs in once in
 * the browser, then this computer's connection to the workspace follows on its own. Signing out signs both
 * out, and the rules already here stay, as the daemon keeps them.
 */
export class Account extends Observed {
  private busyUpdating = false;

  constructor(
    readonly person: DaemonAccount,
    readonly machine: DaemonAccount,
    /** Brings the Memnox under the app up to date, for a daemon from before signing in. */
    private readonly update: () => Promise<void>,
    /** What the console lists this computer as. */
    private readonly computerName: () => string | undefined,
  ) {
    super();
    person.observe(() => this.changed());
    machine.observe(() => this.changed());
  }

  get whole(): AccountWhole {
    return accountWhole(this.person.step, this.machine.step);
  }

  get updating(): boolean {
    return this.busyUpdating;
  }

  get isSignedIn(): boolean {
    return this.whole.kind === 'signed-in';
  }

  async refresh(): Promise<void> {
    await Promise.all([this.person.refresh(), this.machine.refresh()]);
  }

  /** Shows the code and opens the console on it; once approved, this computer's connection is followed. */
  async start(): Promise<void> {
    await this.person.start(this.computerName());
    if (this.person.isSignedIn) await this.machine.follow();
  }

  cancel(): void {
    this.person.cancel();
  }

  async signOut(): Promise<void> {
    await Promise.all([this.person.signOut(), this.machine.signOut()]);
  }

  /** Completes what is still missing: the person's approval when it never came, else only the connection. */
  async finish(): Promise<void> {
    if (this.person.isSignedIn) await this.person.complete(this.computerName());
    else await this.person.start(this.computerName());
    await this.machine.follow();
  }

  /** Updates the daemon, then asks again, so a row that said too old turns into one that works. */
  async bringUpToDate(): Promise<void> {
    if (this.busyUpdating) return;
    this.busyUpdating = true;
    this.changed();
    await this.update();
    this.busyUpdating = false;
    await this.refresh();
    this.changed();
  }
}
