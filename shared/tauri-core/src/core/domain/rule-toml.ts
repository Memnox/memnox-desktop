import type { PolicyRuleView } from '@memnox/core/wire';

/**
 * Rules written out in the runtime's own table shape, ported from the Mac's `RuleToml.swift` so both desktops hand
 * the daemon the same text. This only writes words; the daemon reads them and decides.
 */

/** One `[policies.match.arguments]` line: an argument's name and the values it matches. */
export interface RuleArgument {
  readonly name: string;
  readonly values: readonly string[];
}

/** What a refused agent is told it may do instead, which only a deny carries. */
export interface RuleAlternative {
  readonly action: string;
  readonly note: string;
}

/** A rule's `[policies.match]` table: the actions, then every list that narrows them, absent where it narrows nothing. */
export interface RuleMatchTable {
  readonly actions: readonly string[];
  readonly agents?: readonly string[];
  readonly targets?: readonly string[];
  readonly environments?: readonly string[];
  readonly classes?: readonly string[];
  readonly capabilities?: readonly string[];
  readonly dataClassifications?: readonly string[];
  readonly workingDirectories?: readonly string[];
  readonly branches?: readonly string[];
  readonly arguments?: readonly RuleArgument[];
}

/** One rule as `memnox.policies.toml` holds it, so a preview is what somebody would find in their own file. */
export interface RuleTable {
  readonly name: string;
  readonly description?: string;
  readonly match: RuleMatchTable;
  readonly effect: string;
  readonly reason?: string;
  readonly alternative?: RuleAlternative;
}

/** The file a person keeps this machine's rules in, named over every preview so the shape is recognisable. */
export const RULES_FILE = 'memnox.policies.toml';
/** The line every rules document starts with, which the runtime refuses a document without. */
export const RULES_HEADER = 'version = 1';

/** What a rule's `dataClassifications` can name, the runtime's own vocabulary in its order. */
export const DATA_CLASSIFICATIONS = [
  'sensitive',
  'secret',
  'financial',
  'health',
  'government-id',
  'personal-data',
  'customer-record',
  'confidential',
  'source-code',
  'bulk-records',
] as const;

/** The classes the runtime compares a call's class with, the only ones a rule may name. */
export const ACTION_CLASSES = ['read', 'write', 'destructive', 'communication', 'unknown'] as const;

/** Stands in the preview until somebody names an action. */
export const ACTION_PLACEHOLDER = '<action>';
/** A rule's name before an action gives it words. */
const FALLBACK_NAME = 'rule';

/** The narrowing lists in the order the runtime writes them, each under its own key. */
const LIST_KEYS = ['agents', 'targets', 'environments', 'classes', 'capabilities', 'dataClassifications', 'workingDirectories', 'branches'] as const;

/** A TOML basic string, escaped the way JSON escapes, which TOML reads the same. */
export function tomlQuoted(text: string): string {
  let escaped = '';
  for (const character of text) {
    if (character === '\\') escaped += '\\\\';
    else if (character === '"') escaped += '\\"';
    else if (character === '\n') escaped += '\\n';
    else if (character === '\t') escaped += '\\t';
    else escaped += character;
  }
  return `"${escaped}"`;
}

function list(values: readonly string[]): string {
  return `[ ${values.map(tomlQuoted).join(', ')} ]`;
}

/** The rule as TOML, tables in the runtime's order with a blank line between them. */
export function ruleText(table: RuleTable): string {
  const lines = ['[[policies]]', `name = ${tomlQuoted(table.name)}`];
  if (table.description !== undefined) lines.push(`description = ${tomlQuoted(table.description)}`);
  lines.push('', '[policies.match]', `actions = ${list(table.match.actions)}`);
  for (const key of LIST_KEYS) {
    const values = table.match[key];
    if (values !== undefined) lines.push(`${key} = ${list(values)}`);
  }
  const args = table.match.arguments ?? [];
  if (args.length > 0) lines.push('', '[policies.match.arguments]', ...args.map((each) => `${each.name} = ${list(each.values)}`));
  lines.push('', '[policies.decision]', `effect = ${tomlQuoted(table.effect)}`);
  if (table.reason !== undefined) lines.push(`reason = ${tomlQuoted(table.reason)}`);
  if (table.alternative !== undefined) {
    lines.push('', '[policies.decision.alternative]', `action = ${tomlQuoted(table.alternative.action)}`, `note = ${tomlQuoted(table.alternative.note)}`);
  }
  return lines.join('\n');
}

/** Several rules as one document the runtime imports, each still proposed and signed on its own. */
export function ruleDocument(tables: readonly string[], header: string = RULES_HEADER): string {
  return [header, ...tables].join('\n\n');
}

/** A rule in force written back out, from the fields the runtime reports for it. */
export function tableOfRule(rule: PolicyRuleView): RuleTable {
  const { match } = rule;
  return {
    name: rule.name,
    match: {
      actions: match.actions,
      ...(match.agents === undefined ? {} : { agents: match.agents }),
      ...(match.targets === undefined ? {} : { targets: match.targets }),
      ...(match.classes === undefined ? {} : { classes: match.classes }),
      ...(match.workingDirectories === undefined ? {} : { workingDirectories: match.workingDirectories }),
      ...(match.branches === undefined ? {} : { branches: match.branches }),
    },
    effect: rule.effect,
    ...(rule.reason === undefined ? {} : { reason: rule.reason }),
  };
}

/** The fields of a rule being written in the propose dialog that its table reads. */
export interface RuleDraftFields {
  readonly effect: string;
  readonly action: string;
  readonly reason?: string;
  readonly agents?: readonly string[];
  readonly targets?: readonly string[];
  readonly classes?: readonly string[];
  readonly workingDirectories?: readonly string[];
  readonly branches?: readonly string[];
}

/** A rule being written in the propose dialog, with the data it carries that a draft alone cannot say. */
export function tableOfDraft(draft: RuleDraftFields, dataClassifications?: readonly string[]): RuleTable {
  const action = draft.action === '' ? ACTION_PLACEHOLDER : draft.action;
  const lists = { agents: draft.agents, targets: draft.targets, classes: draft.classes, dataClassifications, workingDirectories: draft.workingDirectories, branches: draft.branches };
  const match: Record<string, readonly string[]> = { actions: [action] };
  for (const [key, values] of Object.entries(lists)) if (values !== undefined) match[key] = values;
  return {
    name: ruleName(draft.effect, draft.action),
    match: match as unknown as RuleMatchTable,
    effect: draft.effect,
    ...(draft.reason === undefined ? {} : { reason: draft.reason }),
  };
}

/** A rule's name as the runtime keys it: the action's words lowercased and joined by hyphens, then the effect. */
export function ruleName(effect: string, action: string): string {
  const words = action
    .toLowerCase()
    .split(/[^\p{L}\p{N}]+/u)
    .filter((word) => word !== '')
    .join('-');
  return `${words === '' ? FALLBACK_NAME : words}-${effect}`;
}

/** A comma separated field as the list it names, undefined when it names nothing. */
export function fieldWords(text: string): string[] | undefined {
  const words = text
    .split(',')
    .map((each) => each.trim())
    .filter((each) => each !== '');
  return words.length === 0 ? undefined : words;
}

/** The field with one word added or taken away, so a chip and typing edit the same text. */
export function toggledWord(word: string, text: string): string {
  const chosen = fieldWords(text) ?? [];
  const next = chosen.includes(word) ? chosen.filter((each) => each !== word) : [...chosen, word];
  return next.join(', ');
}
