import {
  ACTIVITY_METHOD,
  AGENTS_METHOD,
  POLICY_METHOD,
  type ActivityFilter,
  type ActivityRow,
  type AgentView,
  type DaemonRequest,
  type DaemonResponse,
  type DecisionView,
  type PolicyRulesView,
  type ProgressView,
  type RulePackView,
  type RuleVerdictView,
} from '@memnox/core/wire';
import { launchedLine } from '../domain/launch-lines';
import { profileAppliedLine } from '../domain/profile-lines';
import { Observed } from './observed';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/** A rule as the builder fills it: the effect, what it is about, and why; the runtime names and scopes it. */
export type RuleDraftInput = NonNullable<DaemonRequest['ruleDraft']>;
export type RuleTestInput = NonNullable<DaemonRequest['ruleTest']>;

/** How one press ended: done at once, waiting for a signature on the island, or refused with the runtime's words. */
export type StudioOutcome = { kind: 'done'; note: string } | { kind: 'proposed'; id: string } | { kind: 'failed'; why: string };

/** One request and its answer, or undefined when the runtime did not answer at all. */
async function ask(link: DaemonLink, ids: RequestIds, fields: Omit<DaemonRequest, 'id'>): Promise<DaemonResponse | undefined> {
  try {
    // Cast is safe: each caller passes a method the runtime answers and only the fields it reads.
    return await requestOnce(link, { id: ids.next(), ...fields } as DaemonRequest);
  } catch {
    // No runtime is said by the outcome, never thrown at a page.
    return undefined;
  }
}

function outcomeOf(response: DaemonResponse | undefined, done: string): StudioOutcome {
  if (response === undefined) return { kind: 'failed', why: 'The runtime is not answering.' };
  if (!response.ok) return { kind: 'failed', why: response.error ?? 'The runtime refused this.' };
  if (response.proposed !== undefined) return { kind: 'proposed', id: response.proposed };
  return { kind: 'done', note: done };
}

/**
 * The rules in force and what could be let go next. It writes no rule: a rule the person builds is proposed,
 * and goes in force only when they sign it on the island.
 */
export class Studio extends Observed {
  private rulesView: PolicyRulesView | undefined;
  private progressView: ProgressView | undefined;
  private packList: RulePackView[] | undefined;
  private failedRead = false;
  private working: string | undefined;

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
  ) {
    super();
  }

  get rules(): PolicyRulesView | undefined {
    return this.rulesView;
  }

  get progress(): ProgressView | undefined {
    return this.progressView;
  }

  /** The packs Memnox ships, once read. */
  get packs(): readonly RulePackView[] | undefined {
    return this.packList;
  }

  get unreadable(): boolean {
    return this.failedRead;
  }

  get busy(): string | undefined {
    return this.working;
  }

  async readPacks(): Promise<void> {
    const response = await ask(this.link, this.ids, { method: POLICY_METHOD.RULE_PACKS });
    this.packList = response?.rulePacks ?? (response?.ok === true ? [] : undefined);
    this.changed();
  }

  async refresh(): Promise<void> {
    const [rules, progress] = await Promise.all([
      ask(this.link, this.ids, { method: POLICY_METHOD.POLICY_RULES }),
      ask(this.link, this.ids, { method: POLICY_METHOD.PROGRESS }),
    ]);
    this.failedRead = rules === undefined || !rules.ok;
    if (rules?.policyRules !== undefined) this.rulesView = rules.policyRules;
    if (progress?.progress !== undefined) this.progressView = progress.progress;
    this.changed();
  }

  propose(draft: RuleDraftInput): Promise<StudioOutcome> {
    return this.change('propose', { method: POLICY_METHOD.RULE_PROPOSE, ruleDraft: draft }, 'Proposed.');
  }

  remove(name: string): Promise<StudioOutcome> {
    return this.change(name, { method: POLICY_METHOD.RULE_REMOVE, ruleName: name }, `${name} is no longer in force.`);
  }

  revoke(grantId: string): Promise<StudioOutcome> {
    return this.change(grantId, { method: POLICY_METHOD.AUTOPILOT_REVOKE, grantId }, 'Taken back. Your agents ask about it again.');
  }

  async importPack(toml: string): Promise<StudioOutcome> {
    const response = await this.send('pack', { method: POLICY_METHOD.RULE_PACK_IMPORT, rulePack: toml });
    if (response?.ok === true && response.packProposed !== undefined) {
      const count = response.packProposed.length;
      return { kind: 'done', note: count === 1 ? '1 rule waits for your signature on the island.' : `${count} rules wait for your signature on the island.` };
    }
    return outcomeOf(response, 'Nothing in that file was a rule.');
  }

  async test(input: RuleTestInput): Promise<RuleVerdictView | string> {
    const response = await ask(this.link, this.ids, { method: POLICY_METHOD.RULE_TEST, ruleTest: input });
    if (response?.ruleVerdict !== undefined) return response.ruleVerdict;
    return response?.error ?? 'The runtime is not answering.';
  }

  async exportToml(): Promise<string | undefined> {
    const response = await ask(this.link, this.ids, { method: POLICY_METHOD.RULES_EXPORT });
    return response?.rulesToml;
  }

  private async change(subject: string, fields: Omit<DaemonRequest, 'id'>, done: string): Promise<StudioOutcome> {
    const response = await this.send(subject, fields);
    if (response?.policyRules !== undefined) this.rulesView = response.policyRules;
    this.changed();
    return outcomeOf(response, done);
  }

  private async send(subject: string, fields: Omit<DaemonRequest, 'id'>): Promise<DaemonResponse | undefined> {
    this.working = subject;
    this.changed();
    const response = await ask(this.link, this.ids, fields);
    this.working = undefined;
    this.changed();
    return response;
  }
}

/** What the agents did, newest first, a page at a time, and why any one of it was decided as it was. */
export class Activity extends Observed {
  private rowsRead: ActivityRow[] = [];
  private cursor: string | undefined;
  private filterNow: ActivityFilter = {};
  private failedRead = false;
  private reading = false;
  private opened: DecisionView | undefined;

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
  ) {
    super();
  }

  get rows(): readonly ActivityRow[] {
    return this.rowsRead;
  }

  get filter(): ActivityFilter {
    return this.filterNow;
  }

  get more(): boolean {
    return this.cursor !== undefined;
  }

  get loading(): boolean {
    return this.reading;
  }

  get unreadable(): boolean {
    return this.failedRead;
  }

  get decision(): DecisionView | undefined {
    return this.opened;
  }

  /** Reads from the newest again under this filter. */
  async show(filter: ActivityFilter): Promise<void> {
    this.filterNow = filter;
    this.rowsRead = [];
    this.cursor = undefined;
    await this.page();
  }

  async readOn(): Promise<void> {
    if (this.cursor !== undefined) await this.page();
  }

  async open(id: string): Promise<void> {
    const response = await ask(this.link, this.ids, { method: ACTIVITY_METHOD.DECISION, decisionId: id });
    this.opened = response?.decision;
    this.changed();
  }

  close(): void {
    this.opened = undefined;
    this.changed();
  }

  /** The signed record of what the filter holds, as `memnox verify` checks it. */
  async exportBundle(): Promise<string | undefined> {
    const response = await ask(this.link, this.ids, { method: ACTIVITY_METHOD.ACTIVITY_EXPORT, activityFilter: this.filterNow });
    return response?.activityBundle;
  }

  private async page(): Promise<void> {
    this.reading = true;
    this.changed();
    const response = await ask(this.link, this.ids, {
      method: ACTIVITY_METHOD.ACTIVITY,
      activityFilter: this.filterNow,
      ...(this.cursor === undefined ? {} : { activityCursor: this.cursor }),
    });
    this.reading = false;
    this.failedRead = response === undefined || !response.ok;
    const page = response?.activity;
    if (page !== undefined) {
      this.rowsRead = [...this.rowsRead, ...page.rows];
      this.cursor = page.nextCursor;
    }
    this.changed();
  }
}

/** The agents on this computer as the runtime sees them, and pausing or resuming one. */
export class Agents extends Observed {
  private view: AgentView[] | undefined;
  private failedRead = false;
  private working: string | undefined;

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
  ) {
    super();
  }

  get agents(): readonly AgentView[] | undefined {
    return this.view;
  }

  get unreadable(): boolean {
    return this.failedRead;
  }

  get busy(): string | undefined {
    return this.working;
  }

  async refresh(): Promise<void> {
    const response = await ask(this.link, this.ids, { method: AGENTS_METHOD.AGENTS });
    this.failedRead = response === undefined || !response.ok;
    if (response?.agentsView !== undefined) this.view = response.agentsView;
    this.changed();
  }

  pause(kind: string): Promise<StudioOutcome> {
    return this.change(kind, { method: AGENTS_METHOD.AGENT_PAUSE, agentKind: kind }, 'Paused. Nothing it tries runs until you resume it.');
  }

  resume(kind: string): Promise<StudioOutcome> {
    return this.change(kind, { method: AGENTS_METHOD.AGENT_RESUME, agentKind: kind }, 'Resumed.');
  }

  stopSession(sessionId: string): Promise<StudioOutcome> {
    return this.change(sessionId, { method: AGENTS_METHOD.SESSION_STOP, sessionId }, 'Stopped. The session waits until you let it carry on.');
  }

  /**
   * Opens the agent in a new terminal in the folder; the runtime types its launch line, and nothing is widened.
   * A profile named here is applied first, and what it raises waits on the island like any apply.
   */
  async launch(kind: string, folder: string, profile?: { name: string; keyTitle: string }): Promise<StudioOutcome> {
    this.working = `launch/${kind}`;
    this.changed();
    const response = await ask(this.link, this.ids, { method: AGENTS_METHOD.AGENT_LAUNCH, agentKind: kind, workingDirectory: folder.trim(), ...(profile === undefined ? {} : { profileName: profile.name }) });
    this.working = undefined;
    this.changed();
    const launched = response?.agentLaunched;
    const name = this.view?.find((agent) => agent.kind === kind)?.name ?? kind;
    const opened = launched === undefined ? `Opened ${name}.` : launchedLine(launched, name);
    // A launch with a profile is said whole in one line, rather than as the first of its proposals.
    if (response?.ok === true && response.profileApplied !== undefined && profile !== undefined) return { kind: 'done', note: `${opened} ${profileAppliedLine(response.profileApplied, profile.keyTitle)}` };
    return outcomeOf(response, opened);
  }

  private async change(subject: string, fields: Omit<DaemonRequest, 'id'>, done: string): Promise<StudioOutcome> {
    this.working = subject;
    this.changed();
    const response = await ask(this.link, this.ids, fields);
    this.working = undefined;
    if (response?.agentsView !== undefined) this.view = response.agentsView;
    this.changed();
    return outcomeOf(response, done);
  }
}
