import type { ActivityRow, PolicyRuleView, ProgressView } from '@memnox/core/wire';

/** The three effects, each explained once, in the words the console uses. */
export const EFFECT_WORDS = {
  allow: { title: 'Allow', says: 'Goes ahead on its own' },
  ask: { title: 'Ask', says: 'Waits for a person to say yes' },
  deny: { title: 'Deny', says: 'Refused, and told what to do instead' },
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
