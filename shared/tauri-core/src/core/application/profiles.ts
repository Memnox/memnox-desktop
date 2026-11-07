import { PROFILES_METHOD, type DaemonRequest, type DaemonResponse, type ProfileDraft, type ProfileView } from '@memnox/core/wire';
import { profileAppliedLine, profileSavedLine } from '../domain/profile-lines';
import { Observed } from './observed';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/** How a press on Profiles ended; applying is said in a line, since every piece it raises waits on the island. */
export type ProfileOutcome = { kind: 'done'; note: string } | { kind: 'failed'; why: string };

/**
 * Profiles as the runtime keeps them: named bundles of skills, servers and a rule pack. Keeping one grants
 * nothing; applying one raises the proposals each piece raises on its own, each signed on the island.
 */
export class Profiles extends Observed {
  private list: readonly ProfileView[] | undefined;
  private failed = false;
  private busyWith: string | undefined;

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
    private readonly keyTitle: string,
  ) {
    super();
  }

  get profiles(): readonly ProfileView[] | undefined {
    return this.list;
  }

  get unreadable(): boolean {
    return this.failed;
  }

  /** The profile a press is still working on, so its controls can say so. */
  get busy(): string | undefined {
    return this.busyWith;
  }

  async refresh(): Promise<void> {
    const response = await this.ask({ method: PROFILES_METHOD.PROFILES });
    this.failed = response === undefined || !response.ok;
    if (response?.profiles !== undefined) this.list = response.profiles;
    this.changed();
  }

  /** Keeps a new profile, or replaces the one of the same name when `editing`; either way it grants nothing. */
  put(draft: ProfileDraft, editing = false): Promise<ProfileOutcome> {
    return this.change(draft.name, { method: PROFILES_METHOD.PROFILE_PUT, profileDraft: draft }, () => profileSavedLine(draft.name, editing));
  }

  remove(name: string): Promise<ProfileOutcome> {
    return this.change(name, { method: PROFILES_METHOD.PROFILE_REMOVE, profileName: name }, () => `${name} is forgotten. What it already gave stays where it was given.`);
  }

  /** Proposes the profile's servers, skills and rules for an agent, in a project or its home folder. */
  apply(name: string, agent: string, project: string): Promise<ProfileOutcome> {
    const where = project.trim();
    return this.change(
      name,
      { method: PROFILES_METHOD.PROFILE_APPLY, profileName: name, profileAgent: agent, ...(where === '' ? {} : { profileProject: where }) },
      (response) => (response.profileApplied === undefined ? `${name} is applied.` : profileAppliedLine(response.profileApplied, this.keyTitle)),
    );
  }

  private async change(subject: string, fields: Omit<DaemonRequest, 'id'>, done: (response: DaemonResponse) => string): Promise<ProfileOutcome> {
    this.busyWith = subject;
    this.changed();
    const response = await this.ask(fields);
    this.busyWith = undefined;
    if (response?.profiles !== undefined) this.list = response.profiles;
    this.changed();
    if (response === undefined) return { kind: 'failed', why: 'The runtime is not answering.' };
    if (!response.ok) return { kind: 'failed', why: response.error ?? 'The runtime refused this.' };
    return { kind: 'done', note: done(response) };
  }

  private async ask(fields: Omit<DaemonRequest, 'id'>): Promise<DaemonResponse | undefined> {
    try {
      // Cast is safe: every caller passes a profile method and only the fields it reads.
      return await requestOnce(this.link, { id: this.ids.next(), ...fields } as DaemonRequest);
    } catch {
      // A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
      return undefined;
    }
  }
}
