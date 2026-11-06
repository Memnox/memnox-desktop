import type { PolicyRuleView } from '@memnox/core/wire';
import { EFFECT_WORDS, isEffect, type Effect } from './studio-lines';

/**
 * A rule in force said the way somebody deciding about an agent reads it, after the console's `plainRule`:
 * `filesystem.read` on `**\/.ssh/**` is how a rule is written, while "Reading secrets and credentials" is what it
 * means. The Mac says the same titles, so the platforms read alike. This only words what the daemon sent; it
 * decides nothing, and the rule as written stays one press away.
 */

export interface RuleWords {
  /** A short plain title: what the rule is about, with its effect left to the badge beside it. */
  readonly title: string;
  /** One line saying why, the rule's own reason where it gave one. */
  readonly why: string;
}

type RuleShape = Pick<PolicyRuleView, 'effect' | 'match' | 'reason'>;

/** Each family a setup writes, with the words its rules wear when they give no reason of their own. */
interface Family {
  readonly title: string;
  readonly why: string;
  readonly holds: (rule: RuleShape) => boolean;
}

/** The namespaces an agent writes code with, which a rule on everything else leaves out by negating them. */
const CODING_TOOLS = new Set(['filesystem', 'file', 'fs', 'shell', 'process', 'git', 'editor', 'test', 'build', 'package']);

/** The CLIs that reach a cloud, a deploy target or a package registry. */
const CLOUD_CLIS = new Set(['aws', 'gcloud', 'az', 'gh', 'kubectl', 'terraform', 'vercel', 'railway', 'fly', 'heroku', 'netlify', 'stripe', 'docker', 'npm', 'pnpm', 'yarn', 'helm', 'pulumi', 'firebase', 'wrangler']);

/** The database clients, and the name a statement an MCP database tool was handed is ruled under. */
const DATABASE_CLIENTS = new Set(['psql', 'pgcli', 'mysql', 'mariadb', 'mycli', 'mongosh', 'sqlite3', 'redis-cli', 'database', 'db', 'sql']);

/** Where credentials sit, and the variable names that hold them, as a rule's targets name them. */
const SECRET_TARGET = /(^|\/)\.(ssh|aws|gcloud|kube|gnupg|docker|netrc|npmrc|env)(\/|$|\.)|_(KEY|KEYS|SECRET|TOKEN|PASSWORD|CREDENTIALS)$|^(DATABASE_URL|MONGODB_URI|REDIS_URL)$|secret|credential/i;

/** Git verbs that rewrite or throw away history, which the setup's git question lists. */
const DESTRUCTIVE_GIT = /^git\.(push-force|push-f|push-delete|reset|reset-hard|clean|clean-f|clean-fd|clean-force|branch-d|branch-delete-force|reflog-expire|reflog-delete|stash-clear|stash-drop|filter-branch|filter-repo|gc-prune-now)$/;

const familyOf = (action: string): string => action.replace(/^!/, '').split('.')[0]?.toLowerCase() ?? '';
const positive = (actions: readonly string[]): string[] => actions.filter((action) => !action.startsWith('!'));
const negated = (actions: readonly string[]): string[] => actions.filter((action) => action.startsWith('!'));
const every = (actions: readonly string[], test: (action: string) => boolean): boolean => actions.length > 0 && actions.every(test);

/** The families in the order they are tried, the narrowest first, so a rule on secrets is not read as one on files. */
const FAMILIES: readonly Family[] = [
  {
    title: 'Reading secrets and credentials',
    why: 'Keys in ~/.ssh, ~/.aws and .env files. Almost no task needs the key itself.',
    holds: (rule) =>
      every(positive(rule.match.actions), (action) => /^(filesystem|file|fs|environment|env)\.(read|\*)$/.test(action) || action === 'environment.*') &&
      (rule.match.targets ?? []).some((target) => !target.startsWith('!') && SECRET_TARGET.test(target)),
  },
  {
    title: 'Force-pushing and hard resets',
    why: 'It rewrites history somebody else may already have pulled.',
    holds: (rule) => every(positive(rule.match.actions), (action) => DESTRUCTIVE_GIT.test(action)),
  },
  {
    title: 'Deleting files',
    why: 'Sometimes it really is the build directory, so a person should look.',
    holds: (rule) => every(positive(rule.match.actions), (action) => /^(filesystem|file|fs)\.(delete|remove|rm)$/.test(action)),
  },
  {
    title: 'MCP tools that change something',
    why: 'These are the calls whose consequences other people see.',
    holds: (rule) => every(positive(rule.match.actions), (action) => familyOf(action) === 'mcp'),
  },
  {
    title: 'Web requests that change something',
    why: 'A POST, PUT, PATCH or DELETE changes somebody else’s state.',
    holds: (rule) => every(positive(rule.match.actions), (action) => /^(http|https|network|web|fetch)\./.test(action)),
  },
  {
    title: 'Database changes',
    why: 'A statement with no WHERE, a TRUNCATE or a DROP takes every row at once.',
    holds: (rule) => every(positive(rule.match.actions), (action) => DATABASE_CLIENTS.has(familyOf(action))),
  },
  {
    title: 'Cloud, deploy and publish commands',
    why: 'A deploy, a merge or a delete lands on somebody else’s system.',
    holds: (rule) => every(positive(rule.match.actions), (action) => CLOUD_CLIS.has(familyOf(action)) || DATABASE_CLIENTS.has(familyOf(action))),
  },
  {
    title: 'Anything outside the usual coding tools',
    why: 'Files, the shell, git, tests and builds go ahead, while the rest reaches past this computer.',
    holds: (rule) => {
      const actions = positive(rule.match.actions);
      const left = negated(rule.match.actions).map(familyOf);
      return actions.length === 1 && actions[0] === '*' && left.length > 0 && left.every((each) => CODING_TOOLS.has(each));
    },
  },
  {
    title: 'Every action',
    why: 'It reaches whatever an agent does, wherever it does it.',
    holds: (rule) => rule.match.actions.length === 0 || (rule.match.actions.length === 1 && rule.match.actions[0] === '*'),
  },
];

/** What a single action a setup or the console writes means, in a phrase, as the console words them. */
const ACTION_WORDS: Readonly<Record<string, string>> = {
  'filesystem.read': 'Reading files',
  'filesystem.write': 'Changing files',
  'filesystem.delete': 'Deleting files',
  'environment.read': 'Reading environment variables',
  'http.request': 'Reaching a host no rule names',
  'mcp.*': 'MCP tools that change something',
  'shell.*': 'Shell commands',
  'git.push': 'Pushing',
  'git.commit': 'Committing',
  'git.merge': 'Merging',
  'git.tag': 'Tagging a release',
  'npm.publish': 'Publishing a package',
  'docker.push': 'Pushing an image',
};

/** How many names a title shows before the rest become a count. */
const NAMES_SHOWN = 3;

/** The prefix a setup answer writes before its reason, which the badge beside it already says. */
const CHOSEN = /^you chose to [^:]*:\s*/i;

/** Glob dressing that makes `**\/.ssh/**`, `**\/.ssh` and `.env.*` one place to a reader. */
function placeName(target: string): string {
  return target.replace(/^\*\*\//, '').replace(/\/\*\*$/, '').replace(/\.\*$/, '');
}

/** "a, b and c", or "a, b, c and 4 more" once there are more than three. */
export function namesLine(names: readonly string[]): string {
  const unique = [...new Set(names)];
  if (unique.length <= 1) return unique.join('');
  if (unique.length <= NAMES_SHOWN) return `${unique.slice(0, -1).join(', ')} and ${unique.at(-1) ?? ''}`;
  return `${unique.slice(0, NAMES_SHOWN).join(', ')} and ${unique.length - NAMES_SHOWN} more`;
}

/** The rule's own reason with the setup's prefix taken off, or undefined where it gave none worth saying. */
function reasonOf(reason: string | undefined): string | undefined {
  if (reason === undefined) return undefined;
  const bare = reason.replace(CHOSEN, '').trim();
  // "you chose to deny this" with nothing after it only restates the badge.
  if (bare === '' || /^you chose to\b/i.test(bare)) return undefined;
  const line = `${bare.charAt(0).toUpperCase()}${bare.slice(1)}`;
  return /[.!?]$/.test(line) ? line : `${line}.`;
}

/** A rule no family covers, named by what it acts on: up to three names and a count of the rest, then where. */
function fallbackTitle(rule: RuleShape): string {
  const actions = positive(rule.match.actions);
  const names = namesLine(actions.map((action) => ACTION_WORDS[action] ?? action));
  const places = (rule.match.targets ?? []).filter((target) => !target.startsWith('!')).map(placeName);
  const lead = names === '' ? 'Every action' : names;
  return places.length === 0 ? lead : `${lead} in ${namesLine(places)}`;
}

/** Narrows a family's title to the branches a rule names, which is the part a reader needs to tell two apart. */
function onBranches(title: string, rule: RuleShape): string {
  const branches = rule.match.branches ?? [];
  return branches.length === 0 ? title : `${title} to ${namesLine(branches)}`;
}

/** A short plain title and a one line why for a rule in force. */
export function ruleWords(rule: RuleShape): RuleWords {
  const family = FAMILIES.find((each) => each.holds(rule));
  const title = onBranches(family?.title ?? fallbackTitle(rule), rule);
  const why = reasonOf(rule.reason) ?? family?.why ?? (isEffect(rule.effect) ? `${EFFECT_WORDS[rule.effect].says}.` : 'Said as written below.');
  return { title, why };
}

/** Rules that read the same once worded: one row, the count of rules behind it, and the rules themselves. */
export interface RuleGroup<R extends RuleShape = PolicyRuleView> {
  readonly title: string;
  readonly why: string;
  readonly effect: Effect;
  readonly rules: readonly R[];
}

/**
 * The rules in force as rows, those whose plain title and effect match gathered into one, in the order each first
 * appears. A group keeps its why where its rules agree on one, and the family's own line where they do not.
 * A rule whose effect cannot be worded is left out rather than guessed at.
 */
export function ruleGroups<R extends RuleShape>(rules: readonly R[]): RuleGroup<R>[] {
  const groups: { title: string; whys: string[]; effect: Effect; rules: R[] }[] = [];
  for (const rule of rules) {
    if (!isEffect(rule.effect)) continue;
    const words = ruleWords(rule);
    const known = groups.find((group) => group.title === words.title && group.effect === rule.effect);
    if (known === undefined) groups.push({ title: words.title, whys: [words.why], effect: rule.effect, rules: [rule] });
    else {
      known.rules.push(rule);
      if (!known.whys.includes(words.why)) known.whys.push(words.why);
    }
  }
  return groups.map((group) => {
    const shared = group.whys.length === 1 ? group.whys[0] : FAMILIES.find((each) => each.title === group.title)?.why;
    return { title: group.title, why: shared ?? group.whys[0] ?? '', effect: group.effect, rules: group.rules };
  });
}

/** "3 rules say this", said beside a gathered row, or nothing for a row of one. */
export function groupCountLine(count: number): string | undefined {
  return count > 1 ? `${count} rules say this` : undefined;
}

/** The raw pattern a rule matches, field by field, for the disclosure under its plain words. */
export function ruleAsWritten(rule: Pick<PolicyRuleView, 'match'>): { field: string; values: string }[] {
  const fields: [string, readonly string[] | undefined][] = [
    ['Actions', rule.match.actions],
    ['Targets', rule.match.targets],
    ['Agents', rule.match.agents],
    ['Folders', rule.match.workingDirectories],
    ['Branches', rule.match.branches],
    ['Kinds', rule.match.classes],
  ];
  return fields.filter((field): field is [string, readonly string[]] => field[1] !== undefined && field[1].length > 0).map(([field, values]) => ({ field, values: values.join(', ') }));
}
