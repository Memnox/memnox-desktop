import type { ProfileView } from '@memnox/core/wire';
import type { AgentWork } from '../domain/agent-wire';
import { answeredLine } from '../domain/agent-work-lines';
import { cloudProfileView, cloudWorkAll, WorkspaceAgentsLines } from '../domain/workspace-agents';
import type { WorkOutcome } from './agent-work';
import type { Diary } from './diary';
import { Observed } from './observed';
import { WorkspaceInboxError, type PersonCredentialStore, type WorkspaceAgentsReader } from './ports/workspace-inbox';

/** One workspace's agents as last read. */
export interface RemoteAgents {
  readonly workspace: string;
  readonly profiles: readonly ProfileView[];
  readonly work: readonly AgentWork[];
}

/**
 * The agents a workspace reaches that no daemon here does: hosted, inside an app, or built elsewhere. Read only while
 * the person is signed in; with no account this holds nothing and asks nothing, so the local list is all there is.
 * Mirrors the Mac's `WorkspaceAgents`.
 */
export class WorkspaceAgents extends Observed {
  private kept: readonly RemoteAgents[] = [];
  private signed = false;
  private busyWith: string | undefined;

  constructor(
    private readonly reader: WorkspaceAgentsReader,
    private readonly store: PersonCredentialStore,
    private readonly diary?: Diary,
  ) {
    super();
  }

  /** Whether the last read found the person signed in. */
  get signedIn(): boolean {
    return this.signed;
  }

  get remote(): readonly RemoteAgents[] {
    return this.kept;
  }

  get busy(): string | undefined {
    return this.busyWith;
  }

  /** Every workspace's jobs and the person's work; a workspace that did not answer keeps what it showed. */
  async refresh(): Promise<void> {
    const credential = await this.store.load().catch(() => undefined);
    if (credential === undefined) {
      // No account sends nothing at all.
      this.signed = false;
      this.kept = [];
      this.changed();
      return;
    }
    this.signed = true;
    const fresh: RemoteAgents[] = [];
    for (const workspace of credential.workspaces) {
      try {
        const profiles = await this.reader.agentProfiles(workspace, credential.token);
        const mine = await this.reader.myAgentWork(workspace, credential.token);
        fresh.push({ workspace, profiles: profiles.map((each) => cloudProfileView(each, credential.personId)), work: cloudWorkAll(mine) });
      } catch (error) {
        if (error instanceof WorkspaceInboxError && error.failure.kind === 'signed-out') {
          this.signed = false;
          this.kept = [];
          this.changed();
          return;
        }
        this.diary?.note(`reading the workspace's agents for ${workspace} failed: ${String(error)}`);
        const before = this.kept.find((each) => each.workspace === workspace);
        if (before !== undefined) fresh.push(before);
      }
    }
    this.kept = fresh;
    this.changed();
  }

  /** The person's answer to a handoff, unsigned since it only moves who carries the work; the workspace decides. */
  async answer(handoff: string, workspace: string, word: 'accept' | 'decline'): Promise<WorkOutcome> {
    const credential = await this.store.load().catch(() => undefined);
    if (credential === undefined) return { kind: 'failed', why: WorkspaceAgentsLines.signIn };
    this.busyWith = handoff;
    this.changed();
    try {
      await this.reader.answerHandoff(handoff, workspace, word === 'accept', credential.token);
    } catch (error) {
      const failure = error instanceof WorkspaceInboxError ? error.failure : undefined;
      const why = failure !== undefined && 'words' in failure ? failure.words : String(error);
      return { kind: 'failed', why: failure !== undefined && failure.kind !== 'refused' && failure.kind !== 'unreachable' ? why : WorkspaceAgentsLines.notTaken(why) };
    } finally {
      this.busyWith = undefined;
      this.changed();
    }
    await this.refresh();
    return { kind: 'done', note: answeredLine(word) };
  }
}
