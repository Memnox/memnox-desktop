import type { PolicyRuleView } from '@memnox/core/wire';
import { agentLabel } from './mcp-hub-lines';
import { actionPhrase } from './rule-dialog-lines';
import { EFFECT_WORDS, isEffect } from './studio-lines';

/**
 * The Mac's PlainRules, line for line: a rule's match in plain words, as the console's `plainRule` says it. The
 * action names and glob patterns are how a rule is written, not what it means to the person deciding whether it is
 * right. Nothing here decides anything.
 */

/** The kind of protection a rule is, recognised from how it is written. */
export type RuleFamily =
  | 'secrets'
  | 'destructiveGit'
  | 'deletes'
  | 'mcpTools'
  | 'webRequests'
  | 'cloudTools'
  | 'databaseWrites'
  /** Every action but the local ones a coding agent works with all day. */
  | 'outsideCodingTools'
  | 'everything'
  | 'other';

/** A rule as a person reads it in a list: a short title, the agents it is only for, and one line saying why. */
export interface PlainRule {
  readonly title: string;
  readonly why: string | undefined;
  readonly family: RuleFamily;
  /** The agents the rule is for, said apart from the title; undefined for every agent. */
  readonly only: string | undefined;
}

/** Rules that read the same and do the same, shown once with how many stand behind the row. */
export interface PlainRuleGroup<R extends RuleShape = PolicyRuleView> {
  readonly plain: PlainRule;
  readonly effect: string;
  /** Never empty, since a group is made from the rule that opened it. */
  readonly rules: readonly R[];
}

type RuleShape = Pick<PolicyRuleView, 'effect' | 'match' | 'reason'>;
type Match = PolicyRuleView['match'];

const EXCLUDE = '!';
const NAMES_SHOWN = 3;

/** The family titles, word for word what the Mac says. */
const TITLES: Readonly<Record<RuleFamily, string | undefined>> = {
  secrets: 'Reading secrets and credentials',
  destructiveGit: 'Force-pushing and hard resets',
  deletes: 'Deleting files',
  mcpTools: 'MCP tools that change something',
  webRequests: 'Web requests that change something',
  cloudTools: 'Cloud, deploy and publish commands',
  databaseWrites: 'Database changes',
  outsideCodingTools: 'Anything outside the usual coding tools',
  everything: 'Every action',
  other: undefined,
};

/** Why each family exists, said where the rule carries no reason of its own. */
const WHYS: Readonly<Record<RuleFamily, string | undefined>> = {
  secrets: 'Almost no task needs the key itself, and a leaked one is hard to take back.',
  destructiveGit: 'It rewrites history somebody else may already have pulled.',
  deletes: 'Sometimes it really is the build folder, so a person should look first.',
  mcpTools: 'Other people see what these calls change, while a tool that only reads is how an agent finds its way.',
  webRequests: 'A request that posts or deletes changes somebody else’s system.',
  cloudTools: 'A deploy, a merge or a delete lands on somebody else’s system.',
  databaseWrites: 'A statement with no WHERE, a TRUNCATE or a DROP takes every row at once.',
  outsideCodingTools: 'Files, the shell, git and tests stay with the agent, and this covers the rest.',
  everything: undefined,
  other: undefined,
};

/** Single actions in the console's own words, so a rule of one reads as the web says it. */
const ACTION_WORDS: Readonly<Record<string, string>> = {
  'filesystem.read': 'Reading files',
  'filesystem.write': 'Changing files',
  'shell.*': 'Shell commands',
  'shell.execute': 'Shell commands',
  'git.push': 'Pushing',
  'git.tag': 'Tagging a release',
  'git.commit': 'Committing',
  'git.merge': 'Merging',
  'test.run': 'Running tests',
  'code.modify': 'Changing code',
  'code.read': 'Reading code',
};

/** Where credentials sit, as rule targets name them. */
const SECRET_MARKERS = ['.ssh', 'id_rsa', 'id_ed25519', '.aws', '.gcloud', '.kube', '.azure', '.env', '.gnupg', '.netrc', '.npmrc', '_KEY', '_SECRET', '_TOKEN', '_PASSWORD', '_CREDENTIALS', 'DATABASE_URL', 'MONGODB_URI', 'REDIS_URL'].map((marker) => marker.toLowerCase());
/** Git verbs that throw away or rewrite work. */
const GIT_VERBS = new Set(['push-force', 'push-f', 'push-force-with-lease', 'reset-hard', 'reset', 'branch-d', 'branch-delete-force', 'branch-delete', 'push-delete', 'clean', 'clean-f', 'clean-fd', 'clean-force', 'stash-clear', 'stash-drop', 'reflog-expire', 'reflog-delete', 'filter-branch', 'filter-repo', 'gc-prune-now']);
const DELETE_ACTIONS = new Set(['filesystem.delete', 'file.delete', 'fs.delete']);
const WEB_ACTIONS = new Set(['http.request', 'http.*', 'web.request', 'web.*', 'fetch.*']);
const DATABASE_CLIENTS = new Set(['psql', 'pgcli', 'mysql', 'mariadb', 'mycli', 'mongosh', 'sqlite3', 'database']);
const CLOUD_CLIENTS = new Set(['aws', 'gcloud', 'az', 'gh', 'kubectl', 'terraform', 'vercel', 'railway', 'fly', 'heroku', 'netlify', 'stripe', 'deploy']);
const OUTWARD_VERBS = new Set(['docker.push', 'npm.publish', 'npm.unpublish']);
/** The words the runtime writes before a setup answer's reason, which the effect already says. */
const CHOSEN_PREFIX = 'you chose to ';

const namespace = (action: string): string => action.split('.')[0] ?? action;

/** "a and b", or "a, b and c". */
function oneOf(items: readonly string[]): string {
  if (items.length <= 1) return items.join('');
  return `${items.slice(0, -1).join(', ')} and ${items.at(-1) ?? ''}`;
}

/** "a, b and c", or "a, b, c and 4 more" past three. */
function counted(items: readonly string[]): string {
  if (items.length <= NAMES_SHOWN) return oneOf(items);
  return `${items.slice(0, NAMES_SHOWN).join(', ')} and ${items.length - NAMES_SHOWN} more`;
}

function lowerFirst(phrase: string): string {
  // An acronym such as MCP keeps its capitals.
  const second = phrase.charAt(1);
  if (phrase.length > 1 && second !== second.toLowerCase()) return phrase;
  return phrase.charAt(0).toLowerCase() + phrase.slice(1);
}

/** The family a rule's match is, the narrowest first, so a rule on secrets is not read as one on files. */
export function ruleFamily(match: Match): RuleFamily {
  const actions = match.actions.map((action) => action.toLowerCase());
  const wanted = actions.filter((action) => !action.startsWith(EXCLUDE));
  const unwanted = actions.filter((action) => action.startsWith(EXCLUDE));
  const targets = (match.targets ?? []).filter((target) => !target.startsWith(EXCLUDE));
  if (wanted.length === 0) return 'other';
  if (targets.some((target) => SECRET_MARKERS.some((marker) => target.toLowerCase().includes(marker)))) return 'secrets';
  if (wanted.every((action) => namespace(action) === 'git') && wanted.some((action) => GIT_VERBS.has(action.slice('git.'.length)))) return 'destructiveGit';
  if (wanted.every((action) => DELETE_ACTIONS.has(action))) return 'deletes';
  if (wanted.includes('mcp.*') && wanted.every((action) => namespace(action) === 'mcp')) return 'mcpTools';
  if (wanted.every((action) => WEB_ACTIONS.has(action)) && targets.length === 0) return 'webRequests';
  if (wanted.every((action) => DATABASE_CLIENTS.has(namespace(action)))) return 'databaseWrites';
  if (wanted.every((action) => CLOUD_CLIENTS.has(namespace(action)) || OUTWARD_VERBS.has(action))) return 'cloudTools';
  if (wanted.length === 1 && wanted[0] === '*') return unwanted.length === 0 ? 'everything' : 'outsideCodingTools';
  return 'other';
}

/** A setup answer's reason without the words saying it was chosen, as a sentence. */
function reasonLine(reason: string | undefined): string | undefined {
  let line = reason?.trim() ?? '';
  if (line === '') return undefined;
  if (line.toLowerCase().startsWith(CHOSEN_PREFIX)) {
    const colon = line.indexOf(':');
    if (colon < 0) return undefined;
    line = line.slice(colon + 1).trim();
  }
  if (line === '') return undefined;
  line = line.charAt(0).toUpperCase() + line.slice(1);
  return line.endsWith('.') ? line : `${line}.`;
}

/** Targets as places a person recognises: `**\/.ssh/**` is `.ssh`, and an exclusion or a bare star names nothing. */
function placesLine(targets: readonly string[]): string | undefined {
  const places: string[] = [];
  for (const target of targets) {
    if (target.startsWith(EXCLUDE)) continue;
    let place = target;
    if (place.startsWith('**/')) place = place.slice(3);
    if (place.endsWith('/**')) place = place.slice(0, -3);
    if (place.endsWith('.*')) place = place.slice(0, -2);
    if (place === '' || /^\*+$/.test(place) || places.includes(place)) continue;
    places.push(place);
  }
  return places.length === 0 ? undefined : counted(places);
}

/** Any other rule: one action in the console's words, else at most three by name and the rest counted, and where. */
function fallback(match: Match): string {
  const wanted = match.actions.filter((action) => !action.startsWith(EXCLUDE));
  const where = placesLine(match.targets ?? []);
  const places = where === undefined ? '' : ` in ${where}`;
  const only = wanted.length === 1 ? wanted[0] : undefined;
  const words = only === undefined ? undefined : ACTION_WORDS[only.toLowerCase()];
  if (only !== undefined && words !== undefined) {
    const branches = (match.branches ?? []).filter((branch) => !branch.startsWith(EXCLUDE));
    if (only.toLowerCase() === 'git.push' && branches.length > 0) return `${words} to ${counted(branches)}${places}`;
    return `${words}${places}`;
  }
  const phrases: string[] = [];
  for (const action of wanted) {
    const phrase = actionPhrase(action);
    if (!phrases.includes(phrase)) phrases.push(phrase);
  }
  const [first, ...rest] = phrases;
  if (first === undefined) return `What this rule names${places}`;
  return `${counted([first, ...rest.map(lowerFirst)])}${places}`;
}

/** A rule in plain words: its family's title or a fallback, the agents it is only for, and why. */
export function plainRule(rule: RuleShape, agentName: (kind: string) => string = agentLabel): PlainRule {
  const family = ruleFamily(rule.match);
  const agents = rule.match.agents;
  const only = agents === undefined || agents.length === 0 ? undefined : oneOf(agents.map(agentName));
  const title = TITLES[family] ?? fallback(rule.match);
  const why = reasonLine(rule.reason) ?? WHYS[family] ?? (isEffect(rule.effect) ? `${EFFECT_WORDS[rule.effect].says}.` : undefined);
  return { title, why, family, only };
}

/** The row's caption: who it is for, where it is only for some agents, and why. */
export function plainCaption(plain: PlainRule): string | undefined {
  const parts = [plain.only === undefined ? undefined : `Only for ${plain.only}.`, plain.why].filter((part): part is string => part !== undefined);
  return parts.length === 0 ? undefined : parts.join(' ');
}

/** The rules once each by what they say, do and whom they are for, in the order they came, so five that read alike are one row. */
export function plainGroups<R extends RuleShape>(rules: readonly R[], agentName: (kind: string) => string = agentLabel): PlainRuleGroup<R>[] {
  const found = new Map<string, { plain: PlainRule; effect: string; rules: R[] }>();
  for (const rule of rules) {
    const plain = plainRule(rule, agentName);
    const key = [rule.effect, plain.title, plain.only ?? ''].join('\u0000');
    const known = found.get(key);
    if (known === undefined) found.set(key, { plain, effect: rule.effect, rules: [rule] });
    else known.rules.push(rule);
  }
  return [...found.values()];
}

/** "3 rules say this", beside a row standing for more than one. */
export function plainCountLine(count: number): string | undefined {
  return count > 1 ? `${count} rules say this` : undefined;
}

/** The label of the disclosure holding the rule's own actions and patterns. */
export const AS_WRITTEN = 'Show the rule as written';

/** The rule's actions and targets as the runtime holds them, for whoever wants the pattern itself. */
export function writtenLines(match: Match): { label: string; value: string }[] {
  const lines = [{ label: 'Actions', value: match.actions.join(', ') }];
  const more: [string, readonly string[] | undefined][] = [
    ['Targets', match.targets],
    ['Agents', match.agents],
    ['Folders', match.workingDirectories],
    ['Branches', match.branches],
    ['Kinds of call', match.classes],
  ];
  for (const [label, values] of more) if (values !== undefined && values.length > 0) lines.push({ label, value: values.join(', ') });
  return lines;
}
