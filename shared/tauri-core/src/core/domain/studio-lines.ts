import type { ActivityRow, DecisionView, PolicyRuleView, ProgressView } from '@memnox/core/wire';
import { isAbsoluteFolder } from './launch-lines';

/** The three effects, each explained once, in the words the console uses: a rule's title, and a decision's past tense. */
export const EFFECT_WORDS = {
  allow: { title: 'Allow', verdict: 'Allowed', says: 'Goes ahead on its own' },
  ask: { title: 'Ask', verdict: 'Asked', says: 'Waits for a person to say yes' },
  deny: { title: 'Deny', verdict: 'Denied', says: 'Refused, and told what to do instead' },
} as const;

export type Effect = keyof typeof EFFECT_WORDS;

export function isEffect(value: string): value is Effect {
  return value === 'allow' || value === 'ask' || value === 'deny';
}

/** Green goes ahead, amber waits, red is refused. */
export function effectTone(effect: string): 'good' | 'attention' | 'bad' | 'quiet' {
  if (effect === 'allow') return 'good';
  if (effect === 'ask') return 'attention';
  if (effect === 'deny') return 'bad';
  return 'quiet';
}

/** Where a rule came from, said as a person would. */
export function sourceWords(rule: Pick<PolicyRuleView, 'source' | 'decidedBy' | 'file'>): string {
  switch (rule.source) {
    case 'person':
      return rule.decidedBy === undefined ? 'Set on this computer' : `Set by ${rule.decidedBy}`;
    case 'file':
      return rule.file === undefined ? 'From a rule file' : `From ${rule.file}`;
    case 'workspace':
      return 'From your team';
    case 'default':
      return 'Built in';
    case 'autopilot':
      return 'Earned by the autopilot';
    case 'allowance':
      return 'Allowed for a while';
    case 'freeze':
      return 'A freeze';
    default:
      return rule.source;
  }
}

/** Rules counted per effect, for the tabs. */
export function countsByEffect(rules: readonly Pick<PolicyRuleView, 'effect'>[]): Record<Effect, number> {
  const counts: Record<Effect, number> = { allow: 0, ask: 0, deny: 0 };
  for (const rule of rules) if (isEffect(rule.effect)) counts[rule.effect] += 1;
  return counts;
}

/** "Asked you 12 times this week, 31 last week." Counts, never a score. */
export function weekLine(progress: Pick<ProgressView, 'thisWeek' | 'lastWeek'>): string {
  const now = progress.thisWeek.asked;
  const then = progress.lastWeek.asked;
  const times = (count: number) => (count === 1 ? '1 time' : `${count} times`);
  return `Asked you ${times(now)} this week, ${times(then)} last week.`;
}

export function autopilotLine(count: number): string {
  if (count === 0) return 'The autopilot answered nothing for you this week.';
  return count === 1 ? 'The autopilot answered 1 ask for you this week.' : `The autopilot answered ${count} asks for you this week.`;
}

export function almostLine(item: { action: string; approvals: number; needed: number }): string {
  const more = item.needed - item.approvals;
  return more === 1 ? `1 more yes to ${item.action} and it is ready to let go` : `${more} more yeses to ${item.action} and it is ready to let go`;
}

/** What one activity row did, in a line. */
export function activityLine(row: Pick<ActivityRow, 'operation' | 'target'>): string {
  return row.target === undefined ? row.operation : `${row.operation} ${row.target}`;
}

export function answeredWords(row: Pick<ActivityRow, 'answeredBy' | 'answeredHow'>): string | undefined {
  if (row.answeredBy === undefined) return undefined;
  if (row.answeredHow === 'signed') return `${row.answeredBy}, signed`;
  if (row.answeredHow === 'within-session') return `${row.answeredBy}, inside its session`;
  return row.answeredBy;
}

/** The lines of an exported rule file, read back as a count so a person knows what they are saving. */
export function exportedCount(toml: string): number {
  return toml.split('\n').filter((line) => line.trim() === '[[policies]]').length;
}

export const NOTHING_TO_EXPORT = 'No rule set on this computer to export yet.';

/** Said once a pack was written to the file the person picked. */
export function packSavedLine(count: number): string {
  return count === 1 ? 'Saved 1 rule as TOML, ready to share.' : `Saved ${count} rules as TOML, ready to share.`;
}

/** Said once a pack was copied, where no save dialog is to be had. */
export function packCopiedLine(count: number): string {
  return `Copied ${count} rules as TOML, ready to save or share.`;
}

/** What a rule being built will do, read back before it is proposed; the runtime words the one it keeps. */
export function draftSentence(draft: { effect: string; action: string; agents?: readonly string[]; targets?: readonly string[]; branches?: readonly string[]; workingDirectories?: readonly string[] }, agentName: (kind: string) => string): string {
  const who = draft.agents === undefined || draft.agents.length === 0 ? 'any agent' : draft.agents.map(agentName).join(' or ');
  const what = draft.action.trim() === '' ? 'this action' : draft.action.trim();
  const on = [
    ...(draft.targets ?? []).map((target) => `on ${target}`),
    ...(draft.branches ?? []).map((branch) => `on the ${branch} branch`),
    ...(draft.workingDirectories ?? []).map((folder) => `in ${folder}`),
  ].join(' ');
  const tail = on === '' ? '' : ` ${on}`;
  if (draft.effect === 'allow') return `Let ${who} run ${what}${tail} without asking.`;
  if (draft.effect === 'deny') return `Never let ${who} run ${what}${tail}.`;
  return `Ask you before ${who} runs ${what}${tail}.`;
}

/** The switches most people want first, each only a rule proposed with these fields. */
export const ALWAYS_ASK = [
  { id: 'push-main', title: 'Pushing to main', draft: { effect: 'ask', action: 'git.push', branches: ['main'], reason: 'you chose to be asked before anything reaches main' } },
  { id: 'delete-files', title: 'Deleting files', draft: { effect: 'ask', action: 'filesystem.delete', reason: 'you chose to be asked before files are deleted' } },
  { id: 'mcp-writes', title: 'MCP tools that change something', draft: { effect: 'ask', action: 'mcp.*', classes: ['write', 'destructive', 'communication'], reason: 'you chose to be asked before a tool changes something outside this computer' } },
] as const;

/** Whether a rule already in force asks about this switch's action, so the switch shows on. */
export function switchOn(rules: readonly Pick<PolicyRuleView, 'effect' | 'match'>[], action: string, branches?: readonly string[]): boolean {
  return rules.some((rule) => rule.effect !== 'allow' && rule.match.actions.includes(action) && (branches === undefined || branches.every((branch) => rule.match.branches?.includes(branch) === true)));
}

/** The local files a decision names that a press may open: the file the agent touched, and the rule's own file, each by a whole path. */
export function decisionFiles(view: { row: Pick<ActivityRow, 'kind' | 'target'>; rule?: Pick<NonNullable<DecisionView['rule']>, 'file'> }): { title: string; path: string }[] {
  const files: { title: string; path: string }[] = [];
  const { target } = view.row;
  if (view.row.kind === 'file' && target !== undefined && isAbsoluteFolder(target)) files.push({ title: 'Open the file', path: target.trim() });
  const ruleFile = view.rule === undefined ? undefined : view.rule.file;
  if (ruleFile !== undefined && isAbsoluteFolder(ruleFile)) files.push({ title: 'Open the rule file', path: ruleFile.trim() });
  return files;
}
