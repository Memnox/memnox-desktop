import { PROJECTS_METHOD, type DaemonRequest, type DaemonResponse, type ProjectDraft, type ProjectView } from '@memnox/core/wire';
import { appliedLine, upToDate } from '../domain/project-lines';
import { Observed } from './observed';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/**
 * How one press on a project ended: done at once, done with the rest waiting for a signature on the island, nothing to
 * do because every agent already had it, or refused, as the Mac's `ProjectOutcome`.
 */
export type ProjectOutcome =
  | { kind: 'done'; note: string }
  | { kind: 'proposed'; id: string; note: string }
  | { kind: 'up-to-date'; note: string }
  | { kind: 'failed'; why: string };

/**
 * The projects as the runtime keeps them: one repository, the agents seen in it, and what each agent opened
 * there is given. It holds no rule: instructions go at once, and what widens an agent waits on a signature.
 */
export class Projects extends Observed {
  private view: readonly ProjectView[] | undefined;
  private failed = false;
  private busyWith: string | undefined;

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
  ) {
    super();
  }

  get projects(): readonly ProjectView[] | undefined {
    return this.view;
  }

  get unreadable(): boolean {
    return this.failed;
  }

  /** The project or folder a press is still working on, so its controls can say so. */
  get busy(): string | undefined {
    return this.busyWith;
  }

  async refresh(): Promise<void> {
    const response = await this.ask({ method: PROJECTS_METHOD.PROJECTS });
    this.failed = response === undefined || !response.ok;
    if (response?.projects !== undefined) this.view = response.projects.projects;
    this.changed();
  }

  /** Takes a folder in as a project and applies it at once. */
  open(path: string): Promise<ProjectOutcome> {
    return this.change(path, { method: PROJECTS_METHOD.PROJECT_OPEN, projectPath: path.trim() }, 'Opened. Its agents have its instructions.');
  }

  /** Writes the manifest a found project shows now, applying nothing until asked. */
  put(path: string, draft: ProjectDraft): Promise<ProjectOutcome> {
    return this.change(path, { method: PROJECTS_METHOD.PROJECT_PUT, projectPath: path, projectDraft: draft }, `Saved ${draft.name} as a project in .memnox/project.toml. Commit it so every clone has it.`);
  }

  apply(id: string): Promise<ProjectOutcome> {
    return this.change(id, { method: PROJECTS_METHOD.PROJECT_APPLY, projectId: id }, 'Applied.');
  }

  private async change(subject: string, fields: Omit<DaemonRequest, 'id'>, done: string): Promise<ProjectOutcome> {
    this.busyWith = subject;
    this.changed();
    const response = await this.ask(fields);
    this.busyWith = undefined;
    if (response?.projects !== undefined) this.view = response.projects.projects;
    this.changed();
    if (response === undefined) return { kind: 'failed', why: 'The runtime is not answering.' };
    if (!response.ok) return { kind: 'failed', why: response.error ?? 'The runtime refused this.' };
    const note = response.projectApplied === undefined ? done : appliedLine(response.projectApplied);
    if (response.proposed !== undefined) return { kind: 'proposed', id: response.proposed, note };
    if (response.projectApplied !== undefined && upToDate(response.projectApplied)) return { kind: 'up-to-date', note };
    return { kind: 'done', note };
  }

  private async ask(fields: Omit<DaemonRequest, 'id'>): Promise<DaemonResponse | undefined> {
    try {
      // Cast is safe: every caller passes a projects method and only the fields it reads.
      return await requestOnce(this.link, { id: this.ids.next(), ...fields } as DaemonRequest);
    } catch {
      // A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
      return undefined;
    }
  }
}
