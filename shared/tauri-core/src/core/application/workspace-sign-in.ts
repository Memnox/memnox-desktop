import { WorkspaceLines } from '../domain/workspace-lines';
import type { PersonCode, PersonToken, WorkspaceCredential } from '../domain/workspace-wire';
import type { Diary } from './diary';
import type { Sleep } from './observed';
import type { ConfirmKey } from './ports/confirm-key';
import type { PersonCredentialStore, WorkspaceInbox } from './ports/workspace-inbox';

/** How signing in as the person ended. */
export type SignInOutcome = { kind: 'signed-in'; credential: WorkspaceCredential } | { kind: 'stopped'; why: string };

/** The cloud asks for five seconds; never faster than one, whatever a misconfigured answer says. */
const SHORTEST_INTERVAL_MS = 1_000;

/**
 * Signs the person in to their Memnox Cloud workspace with a code they approve in the console, then registers this
 * computer's confirm key so every yes it gives can be verified. The console decides; this carries the code, keeps the
 * credential and names the key. Ported from the Mac's `WorkspaceSignIn`.
 */
export class WorkspaceSignIn {
  private stopped = false;

  constructor(
    private readonly inbox: WorkspaceInbox,
    private readonly store: PersonCredentialStore,
    private readonly key: ConfirmKey,
    private readonly sleep: Sleep,
    private readonly now: () => number = Date.now,
    private readonly diary?: Diary,
  ) {}

  /** The person signed in on this computer, undefined when nobody is. */
  current(): Promise<WorkspaceCredential | undefined> {
    return this.store.load().catch(() => undefined);
  }

  /** Stops a sign in waiting on the console. */
  cancel(): void {
    this.stopped = true;
  }

  /** Runs the code flow; `shown` hears the code the moment there is one, for the person to approve in the console. */
  async signIn(name: string, shown: (code: PersonCode) => void): Promise<SignInOutcome> {
    this.stopped = false;
    // A computer with no key could sign in and then never say yes, which reads as a broken button later.
    const point = await this.key.publicPoint().catch(() => undefined);
    if (point === undefined || point === '') return { kind: 'stopped', why: WorkspaceLines.noKey };
    let code: PersonCode;
    try {
      code = await this.inbox.startSignIn(name);
    } catch (error) {
      this.diary?.note(`could not start a team sign in: ${String(error)}`);
      return { kind: 'stopped', why: WorkspaceLines.unreachable };
    }
    shown(code);
    const approval = await this.approval(code);
    return approval.kind === 'granted' ? this.finish(approval.token, name, point) : approval;
  }

  /** Asks every interval until the console answers or the code runs out. */
  private async approval(code: PersonCode): Promise<{ kind: 'granted'; token: PersonToken } | { kind: 'stopped'; why: string }> {
    const interval = Math.max(code.intervalSeconds * 1_000, SHORTEST_INTERVAL_MS);
    while (this.now() < code.expiresAt) {
      await this.sleep(interval);
      if (this.stopped) return { kind: 'stopped', why: WorkspaceLines.cancelled };
      try {
        const redeemed = await this.inbox.redeem(code.deviceCode);
        if (redeemed.kind === 'granted') return redeemed;
        if (redeemed.kind === 'stopped') return { kind: 'stopped', why: WorkspaceLines.refused(redeemed.word) };
      } catch (error) {
        // A dropped request is asked again on the next interval, since the code is still good.
        this.diary?.note(`asking about the team sign in failed: ${String(error)}`);
      }
    }
    return { kind: 'stopped', why: WorkspaceLines.expired };
  }

  /** Finds the workspaces to poll, registers the key and keeps the credential; one kept without a device could never say yes. */
  private async finish(token: PersonToken, name: string, point: string): Promise<SignInOutcome> {
    let workspaces: string[];
    let deviceId: string;
    try {
      const reached = await this.inbox.workspaces(token.token);
      // Only the organisation that granted the token, since that is the one the person approved this computer for.
      const inOrg = reached.filter((each) => each.orgId === undefined || each.orgId === token.orgId).map((each) => each.id);
      workspaces = inOrg.length === 0 ? reached.map((each) => each.id) : inOrg;
      if (workspaces.length === 0) return { kind: 'stopped', why: WorkspaceLines.noWorkspace };
      deviceId = (await this.inbox.registerDevice(name, point, token.token)).id;
    } catch (error) {
      this.diary?.note(`could not finish the team sign in: ${String(error)}`);
      return { kind: 'stopped', why: WorkspaceLines.unreachable };
    }
    const credential: WorkspaceCredential = { token: token.token, tokenId: token.tokenId, personId: token.personId, name: token.name, orgId: token.orgId, workspaces, deviceId };
    try {
      await this.store.save(credential);
    } catch (error) {
      this.diary?.note(`could not keep the team credential: ${String(error)}`);
      // Removing the device revokes the credential too, so nothing is left signed in that this computer forgot.
      await this.inbox.removeDevice(deviceId, token.token).catch(() => undefined);
      return { kind: 'stopped', why: WorkspaceLines.notKept };
    }
    this.diary?.note(`signed in to the team, ${workspaces.length} workspaces, device ${deviceId}`);
    return { kind: 'signed-in', credential };
  }

  /** Removes this computer from the workspace, which revokes its credential, then forgets it here whatever the cloud said. */
  async signOut(): Promise<void> {
    const credential = await this.current();
    if (credential === undefined) return;
    await this.inbox.removeDevice(credential.deviceId, credential.token).catch((error: unknown) => this.diary?.note(`removing this computer from the team did not go through: ${String(error)}`));
    await this.store.delete().catch(() => undefined);
    this.diary?.note('signed out of the team');
  }
}
