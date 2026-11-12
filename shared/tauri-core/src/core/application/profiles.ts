import { PROFILES_METHOD, type DaemonRequest, type DaemonResponse, type ProfileDraft, type ProfileView } from '@memnox/core/wire';
import { NO_LEVELS, type ProfileTemplate } from '../domain/agent-wire';
import { filled } from '../domain/agent-work-lines';
import { boundLine, copiedLine, profileAppliedLine, profileSavedLine, unboundLine } from '../domain/profile-lines';
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
  private catalog: readonly ProfileTemplate[] | undefined;
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

  /** The job descriptions with no agent behind them, undefined until read. */
  get templates(): readonly ProfileTemplate[] | undefined {
    return this.catalog;
  }

  /** The profile a press is still working on, so its controls can say so. */
  get busy(): string | undefined {
    return this.busyWith;
  }

  async refresh(): Promise<void> {
    const response = await this.ask({ method: PROFILES_METHOD.PROFILES });
    this.failed = response === undefined || !response.ok;
    // A daemon that answered with no list keeps no profile, so a page says so rather than drawing nothing.
    if (response?.ok === true) this.list = (response.profiles ?? []).map(whole);
    this.changed();
  }

  /** Keeps a new profile, or replaces the one of the same name when `editing`; either way it grants nothing. */
  put(draft: ProfileDraft, editing = false): Promise<ProfileOutcome> {
    return this.change(draft.name, { method: PROFILES_METHOD.PROFILE_PUT, profileDraft: draft }, () => profileSavedLine(draft.name, editing));
  }

  remove(name: string): Promise<ProfileOutcome> {
    return this.change(name, { method: PROFILES_METHOD.PROFILE_REMOVE, profileName: name }, () => `${name} is forgotten. What it already gave stays where it was given.`);
  }

  /** Reads the catalog of job descriptions, which ships with the runtime and needs no account. */
  async readTemplates(): Promise<void> {
    const response = await this.ask({ method: PROFILES_METHOD.TEMPLATES });
    if (response?.ok === true) this.catalog = response.templates ?? [];
    this.changed();
  }

  /** Puts an agent found here under a kept profile; its ledger key stays its own, so nothing it did is renamed. */
  bind(profile: string, agent: string): Promise<ProfileOutcome> {
    return this.change(profile, { method: PROFILES_METHOD.PROFILE_BIND, profileName: profile, agentId: agent }, () => boundLine(profile));
  }

  /** Takes the binding off, which puts the agent back on its own default profile. */
  unbind(agent: string, from: string): Promise<ProfileOutcome> {
    return this.change(from, { method: PROFILES_METHOD.PROFILE_UNBIND, agentId: agent }, () => unboundLine);
  }

  /** Keeps a job and binds an agent to it in one press, as Give it a job on an agent's card does. */
  async putAndBind(draft: ProfileDraft, agent: string): Promise<ProfileOutcome> {
    const kept = await this.put(draft);
    if (kept.kind === 'failed') return kept;
    return this.bind(draft.name, agent);
  }

  /** Copies a template's job into a new profile, with only the suggested skills the person took; no rule is applied. */
  fromTemplate(template: string, name: string, skills: readonly string[]): Promise<ProfileOutcome> {
    const named = filled(name);
    return this.change(
      template,
      { method: PROFILES_METHOD.PROFILE_FROM_TEMPLATE, templateId: template, templateSkills: [...skills], ...(named === undefined ? {} : { profileName: named }) },
      () => copiedLine(name),
    );
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
    if (response?.profiles !== undefined) this.list = response.profiles.map(whole);
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

/**
 * A profile with every list it may leave out filled in empty, since a runtime from before jobs sends no connections,
 * responsibilities or levels, and a page reading one must never stop on it. No level is ever raised by filling.
 */
function whole(profile: ProfileView): ProfileView {
  const sent = profile as Partial<ProfileView> & Pick<ProfileView, 'id' | 'name' | 'updatedAt'>;
  return {
    ...profile,
    skills: sent.skills ?? [],
    mcpServers: sent.mcpServers ?? [],
    missing: sent.missing ?? [],
    responsibilities: sent.responsibilities ?? [],
    projects: sent.projects ?? [],
    connections: sent.connections ?? [],
    levels: sent.levels ?? NO_LEVELS,
  };
}
