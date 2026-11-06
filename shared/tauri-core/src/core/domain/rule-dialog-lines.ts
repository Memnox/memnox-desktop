import type { PolicyRuleView } from '@memnox/core/wire';
import { ACTION_CLASSES } from './rule-toml';
import { sourceWords, type Effect } from './studio-lines';

/**
 * The words of the propose dialog and the rule's details, the same the Mac says in RuleDialogParts.swift,
 * RuleBuilderSheet.swift, PoliciesDestination.swift and RuleDetailLines.swift, so a test pins one wording for
 * both. Only the key named and "this computer" for "this Mac" differ, since that is the platform.
 */

/** The words every rule dialog shares. */
export const RULE_DIALOG = {
  proposeDescription: (keyTitle: string) => `It is proposed on this computer and holds once you sign it with ${keyTitle} on the island.`,
  propose: 'Propose',
  proposing: 'Proposing',
  cancel: 'Cancel',
  whenTried: 'When an agent tries it',
  recommended: 'Suggested',
  preview: 'The rule',
  optional: '(optional)',
} as const;

/** The propose dialog's fields in the Mac's order, each with its placeholder and the line under it. */
export const RULE_BUILDER = {
  title: 'Propose a rule',
  action: 'Which action',
  actionPlaceholder: 'vercel.deploy-prod',
  knownActions: 'Actions your rules already name',
  knownHelp: 'Pick an action a rule already names',
  tryOne: 'Try one:',
  agent: 'Only for one agent',
  anyAgent: 'Any agent',
  targets: 'Only where it touches',
  targetsPlaceholder: '!api.stripe.com, !s3.amazonaws.com',
  targetsHint: 'Hosts, paths or repositories, comma separated. Start one with ! to leave it out, so !api.stripe.com is an approved destination.',
  carries: 'Only when it carries',
  carriesPlaceholder: 'secret, financial',
  carriesHint: 'What the action carries, as the runtime classifies it. Pick a word below, or type a name your team gave its own patterns.',
  carriesChips: 'Data it carries',
  classes: 'Only when it is',
  classesPlaceholder: 'destructive',
  classesHint: `What the action does: ${ACTION_CLASSES.join(', ')}. A send needs none, since the data it carries and where it goes already narrow it.`,
  branch: 'Only on the branch',
  branchPlaceholder: 'main',
  folder: 'Only in the folder',
  folderPlaceholder: '~/code/app',
  instead: 'What the agent may do instead',
  insteadHint: 'A refused agent that is told what it may do still finishes the task. Both halves, or neither.',
  insteadAction: 'The action it may take, such as http.request',
  insteadActionLabel: 'The action it may take instead',
  insteadNote: 'What the agent reads, such as: send it to an approved destination',
  insteadNoteLabel: 'What the agent reads instead',
  why: 'Why, in your words',
  whyPlaceholder: 'What an agent reads when this rule decides',
  readBack: (sentence: string) => `This rule would say: ${sentence}`,
} as const;

/** The console's examples, each an action string the runtime names, a press away. */
export const RULE_EXAMPLES: readonly { action: string; title: string }[] = [
  { action: 'git.push-force', title: 'Force push' },
  { action: 'gh.pr-merge', title: 'Merge a pull request' },
  { action: 'vercel.deploy-prod', title: 'Deploy to production' },
  { action: 'filesystem.delete', title: 'Delete files' },
  { action: 'mcp.stripe.*', title: 'Any Stripe tool' },
];

/** The words of one rule's details. */
export const RULE_DETAIL = {
  why: 'Why',
  name: 'Name',
  from: 'From',
  file: 'File',
  until: 'Until',
  agents: 'Agents',
  remove: 'Remove',
  proposeRemoving: 'Propose removing it',
  removeNote: 'Removing a rule that asks or refuses lets agents do more, so it waits for your signature.',
  elsewhere: 'This rule is not one set on this computer, so it is changed where it came from.',
  asWritten: 'Show the rule as written',
} as const;

/** "a, b and c", every name said, as the Mac's PlainRules says whom a rule is only for. */
function oneOf(names: readonly string[]): string {
  if (names.length <= 1) return names.join('');
  return `${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}`;
}

/** The line under a rule's title, as the Mac's PlainRule.caption: whom it is only for, where it names agents, then why. */
export function ruleCaption(agents: readonly string[] | undefined, why: string, agentName: (kind: string) => string): string {
  if (agents === undefined || agents.length === 0) return why;
  return `Only for ${oneOf(agents.map(agentName))}. ${why}`;
}

/** What the details say under the rule as written: where it came from, its name, its file and when it ends. */
export function ruleFacts(rule: Pick<PolicyRuleView, 'name' | 'source' | 'decidedBy' | 'file' | 'until'>, moment: (iso: string) => string): [string, string][] {
  const facts: [string, string][] = [
    [RULE_DETAIL.name, rule.name],
    [RULE_DETAIL.from, sourceWords(rule)],
  ];
  if (rule.file !== undefined) facts.push([RULE_DETAIL.file, rule.file]);
  if (rule.until !== undefined) facts.push([RULE_DETAIL.until, moment(rule.until)]);
  return facts;
}

/** Actions the runtime ships with, in the words the work is actually described in. */
const NAMED: Readonly<Record<string, string>> = {
  'code.modify': 'Change code',
  'code.read': 'Read code',
  'data.export': 'Export data',
  'database.delete': 'Delete database records',
  'database.migrate': 'Run a database migration',
  'database.read': 'Read from the database',
  'database.truncate': 'Empty a database table',
  'deploy.service': 'Deploy a service',
  'filesystem.delete': 'Delete a file',
  'filesystem.read': 'Read a file',
  'filesystem.write': 'Write a file',
  'git.commit': 'Commit code',
  'llm.spend': 'Spend on AI usage',
  'mcp.delete_repository': 'Delete a repository',
  'mcp.merge_pull_request': 'Merge a pull request',
  'mcp.search_issues': 'Search issues',
  'shell.execute': 'Run a shell command',
  'test.run': 'Run tests',
  'ticket.read': 'Read a support ticket',
  'ticket.reply': 'Reply to a support ticket',
};

/** Namespaces that say how a thing was called, not what was done. */
const NAMESPACES = new Set(['mcp', 'api', 'rpc', 'tool', 'fn']);
/** Last segments that are the verb, so the phrase can be turned around. */
const VERBS = new Set(['create', 'commit', 'delete', 'deploy', 'execute', 'export', 'import', 'merge', 'migrate', 'modify', 'read', 'reply', 'run', 'search', 'spend', 'truncate', 'update', 'write']);
const UNKNOWN_VERB = '.unknown';
const FALLBACK = 'Automated action';

/** A machine action name as a person would say it, as the Mac's RuleDetailLines.phrase says it. */
export function actionPhrase(action: string): string {
  const named = NAMED[action];
  if (named !== undefined) return named;
  if (action.endsWith(UNKNOWN_VERB) && !action.includes('/')) return `A ${action.slice(0, -UNKNOWN_VERB.length)} command Memnox does not recognise`;
  // A path or an address is never shown, whatever else it might contain.
  if (action === '' || /[/:@]/.test(action)) return FALLBACK;
  let words = action.split(/[^\p{L}\p{N}]+/u).filter((word) => word !== '');
  if (words.length > 1 && NAMESPACES.has(words[0]!.toLowerCase())) words = words.slice(1);
  const last = words[words.length - 1]?.toLowerCase();
  if (words.length > 1 && last !== undefined && VERBS.has(last)) words = [last, ...words.slice(0, -1)];
  const joined = words.join(' ');
  if (joined === '') return FALLBACK;
  return joined.charAt(0).toUpperCase() + joined.slice(1);
}

/** What the effect does to the agent, as the end of a sentence about it. */
const THEN: Record<Effect, string> = {
  allow: 'goes ahead on its own',
  ask: 'waits for a person to say yes',
  deny: 'is refused and told what to do instead',
};

/** The rule as one sentence: who, what, where, and what happens then, as the Mac's details say it. */
export function ruleDetailSentence(rule: { agents?: readonly string[]; actions: readonly string[]; targets?: readonly string[]; effect: Effect }, agentName: (kind: string) => string): string {
  const who = rule.agents === undefined || rule.agents.length === 0 ? 'any agent' : rule.agents.map(agentName).join(', ');
  const what = rule.actions.map(actionPhrase).join(', ').toLowerCase();
  const on = rule.targets === undefined || rule.targets.length === 0 ? '' : ` on ${rule.targets.join(', ')}`;
  return `When ${who} tries to ${what}${on}, it ${THEN[rule.effect]}.`;
}
