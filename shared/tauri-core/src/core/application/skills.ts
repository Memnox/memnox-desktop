import { SKILLS_METHOD, type DaemonRequest, type DaemonResponse, type SkillDraft, type SkillsHubView } from '@memnox/core/wire';
import { assignmentChanges, skillsSyncedLine } from '../domain/skills-lines';
import { Observed } from './observed';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/** How one press on the Skills Hub ended: done at once, waiting for a signature on the island, or refused. */
export type SkillOutcome = { kind: 'done'; note: string } | { kind: 'proposed'; id: string } | { kind: 'failed'; why: string };

/** What a Continue in the assign dialog came to, counted so one line says it. */
export interface AssignResults {
  readonly proposed: number;
  readonly done: number;
  readonly failed: string[];
}

/**
 * The Skills Hub as the runtime keeps it: skills kept once and written into each agent's own format. It
 * holds no rule: giving a skill to an agent, or accepting a folder that reaches further, waits for a signature.
 */
export class SkillsHub extends Observed {
  private view: SkillsHubView | undefined;
  private failed = false;
  private busyWith: string | undefined;

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
  ) {
    super();
  }

  get hub(): SkillsHubView | undefined {
    return this.view;
  }

  get unreadable(): boolean {
    return this.failed;
  }

  /** The skill a press is still working on, so its controls can say so. */
  get busy(): string | undefined {
    return this.busyWith;
  }

  async refresh(): Promise<void> {
    const response = await this.ask({ method: SKILLS_METHOD.SKILLS_HUB });
    this.failed = response === undefined || !response.ok;
    if (response?.skillsHub !== undefined) this.view = response.skillsHub;
    this.changed();
  }

  enable(name: string): Promise<SkillOutcome> {
    return this.change(name, { method: SKILLS_METHOD.SKILL_ENABLE, skillName: name }, `${name} is handed back to the agents it was given to.`);
  }

  disable(name: string): Promise<SkillOutcome> {
    return this.change(name, { method: SKILLS_METHOD.SKILL_DISABLE, skillName: name }, `${name} was taken out of every agent. Its assignments are kept for later.`);
  }

  accept(name: string): Promise<SkillOutcome> {
    return this.change(name, { method: SKILLS_METHOD.SKILL_ACCEPT, skillName: name }, `${name} is accepted as it is now.`);
  }

  rollback(name: string, version: string): Promise<SkillOutcome> {
    return this.change(name, { method: SKILLS_METHOD.SKILL_ROLLBACK, skillName: name, skillVersion: version }, `${name} is back on ${version}.`);
  }

  assign(name: string, agent: string, on: boolean): Promise<SkillOutcome> {
    const note = on ? `${name} is now given to ${agent}.` : `${agent} no longer has ${name}.`;
    return this.change(name, { method: SKILLS_METHOD.SKILL_ASSIGN, skillName: name, skillAgent: agent, skillOn: on }, note);
  }

  /** Takes away at once and gives one signature each, sending only what differs from the agents it has now. */
  async assignTo(name: string, chosen: ReadonlySet<string>): Promise<AssignResults> {
    const current = this.view?.skills.find((skill) => skill.name === name)?.agents ?? [];
    const { give, take } = assignmentChanges(current, chosen);
    const results = { proposed: 0, done: 0, failed: [] as string[] };
    for (const [agent, on] of [...take.map((each) => [each, false] as const), ...give.map((each) => [each, true] as const)]) {
      const outcome = await this.assign(name, agent, on);
      if (outcome.kind === 'proposed') results.proposed += 1;
      else if (outcome.kind === 'done') results.done += 1;
      else results.failed.push(outcome.why);
    }
    return results;
  }

  importFound(id: string, name: string): Promise<SkillOutcome> {
    return this.change(name, { method: SKILLS_METHOD.SKILL_IMPORT, skillFoundId: id }, `${name} is in the hub now.`);
  }

  put(draft: SkillDraft): Promise<SkillOutcome> {
    return this.change(draft.name, { method: SKILLS_METHOD.SKILL_PUT, skillDraft: draft, skillScope: 'personal' }, `${draft.name} is in the hub now.`);
  }

  sync(): Promise<SkillOutcome> {
    return this.change('sync', { method: SKILLS_METHOD.SKILL_SYNC }, 'Synced.');
  }

  private async change(subject: string, fields: Omit<DaemonRequest, 'id'>, done: string): Promise<SkillOutcome> {
    this.busyWith = subject;
    this.changed();
    const response = await this.ask(fields);
    this.busyWith = undefined;
    if (response?.skillsHub !== undefined) this.view = response.skillsHub;
    this.changed();
    if (response === undefined) return { kind: 'failed', why: 'The runtime is not answering.' };
    if (!response.ok) return { kind: 'failed', why: response.error ?? 'The runtime refused this.' };
    if (response.proposed !== undefined) return { kind: 'proposed', id: response.proposed };
    if (response.skillsSynced !== undefined && fields.method === SKILLS_METHOD.SKILL_SYNC) return { kind: 'done', note: skillsSyncedLine(response.skillsSynced) };
    return { kind: 'done', note: done };
  }

  private async ask(fields: Omit<DaemonRequest, 'id'>): Promise<DaemonResponse | undefined> {
    try {
      // Cast is safe: every caller passes a method the Skills Hub answers and only the fields it reads.
      return await requestOnce(this.link, { id: this.ids.next(), ...fields } as DaemonRequest);
    } catch {
      // A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
      return undefined;
    }
  }
}
