import type { PolicyRuleView } from '@memnox/core/wire';
import { ALL_CATEGORIES, categoryCounts, matchesSearch, searchWords, type CategoryCount } from './catalog';
import { plainCaption, plainGroups } from './plain-rules';
import { ALWAYS_ASK, EFFECT_WORDS, isEffect, sourceWords, switchOn, type Effect } from './studio-lines';

/**
 * The Rules page as the console's Connected tools page lays a catalogue out: Allow, Ask and Deny as tabs with
 * counts, the kinds of action down the side, a search, and one card per rule. A ready-made rule not in force yet
 * is a card marked Suggested. This only words and sorts what the daemon sent; it decides nothing.
 */

export type RuleCategory = 'git' | 'files' | 'commands' | 'web' | 'tools' | 'everything' | 'other';

/** The kinds of action in the order the rail lists them, the commonest first. */
export const RULE_CATEGORIES: readonly { id: RuleCategory; title: string }[] = [
  { id: 'git', title: 'Git' },
  { id: 'files', title: 'Files' },
  { id: 'commands', title: 'Commands' },
  { id: 'web', title: 'Web' },
  { id: 'tools', title: 'Connected tools' },
  { id: 'everything', title: 'Every action' },
  { id: 'other', title: 'Other' },
];

/** The first word of an action names what it acts on, so `git.push` is Git and `mcp.*` a connected tool. */
const CATEGORY_OF_FAMILY: Readonly<Record<string, RuleCategory>> = {
  git: 'git',
  filesystem: 'files',
  file: 'files',
  fs: 'files',
  shell: 'commands',
  command: 'commands',
  exec: 'commands',
  process: 'commands',
  http: 'web',
  network: 'web',
  browser: 'web',
  web: 'web',
  mcp: 'tools',
  tool: 'tools',
  connector: 'tools',
};

/** Where a rule sits on the rail, read off its first action; a rule on every action is said as such. */
export function ruleCategory(actions: readonly string[]): RuleCategory {
  const first = actions[0]?.trim() ?? '';
  if (first === '' || first === '*') return 'everything';
  const family = first.split('.')[0]?.toLowerCase() ?? '';
  return CATEGORY_OF_FAMILY[family] ?? 'other';
}

/** The marker on a ready-made rule nobody turned on yet. */
export const SUGGESTED = 'Suggested';

/** What a Suggested card's button does: propose it, signed like any other rule. */
export const TURN_ON = 'Turn on';

export type ReadyMade = (typeof ALWAYS_ASK)[number];

export interface RuleCard {
  readonly id: string;
  readonly effect: Effect;
  readonly title: string;
  /** One line under the title: why the rule holds, or what a suggestion would do. */
  readonly line: string;
  readonly category: RuleCategory;
  readonly suggested: boolean;
  /** The words a search reads besides the title and line. */
  readonly keywords: string;
  /** The first rule behind the card, which its scope and its details are read from. */
  readonly rule?: PolicyRuleView;
  /** Every rule in force that reads the same once worded, gathered onto this one card. */
  readonly rules: readonly PolicyRuleView[];
  readonly readyMade?: ReadyMade;
}

/** The ready-made rules not yet in force first, as Suggested, then every rule in force in the daemon's order. */
export function ruleCards(rules: readonly PolicyRuleView[], readyMade: readonly ReadyMade[] = ALWAYS_ASK): RuleCard[] {
  const suggested = readyMade
    .filter((each) => !switchOn(rules, each.draft.action, 'branches' in each.draft ? each.draft.branches : undefined))
    .map(
      (each): RuleCard => ({
        id: `suggested:${each.id}`,
        effect: each.draft.effect,
        title: each.title,
        line: each.line,
        category: ruleCategory([each.draft.action]),
        suggested: true,
        keywords: each.draft.action,
        rules: [],
        readyMade: each,
      }),
    );
  // Rules that read, do and are for the same agents alike are one card with a count, as the Mac's PlainRules.grouped.
  const inForce = plainGroups(rules).flatMap((group): RuleCard[] => {
    const first = group.rules[0];
    if (first === undefined || !isEffect(group.effect)) return [];
    return [
      {
        id: first.name,
        effect: group.effect,
        title: group.plain.title,
        // The caption says whom it is only for and why, else where the rule came from, as the Mac's row.
        line: plainCaption(group.plain) ?? sourceWords(first),
        category: ruleCategory(first.match.actions),
        suggested: false,
        keywords: group.rules.map((rule) => `${rule.name} ${rule.sentence} ${sourceWords(rule)} ${rule.match.actions.join(' ')}`).join(' '),
        rule: first,
        rules: group.rules,
      },
    ];
  });
  return [...suggested, ...inForce];
}

export type EffectTab = 'all' | Effect;

/** All, then Allow, Ask and Deny, each with how many cards it holds. */
export function effectTabs(cards: readonly RuleCard[]): { id: EffectTab; title: string; count: number }[] {
  const of = (effect: Effect) => cards.filter((card) => card.effect === effect).length;
  return [
    { id: 'all', title: 'All', count: cards.length },
    ...(Object.keys(EFFECT_WORDS) as Effect[]).map((effect) => ({ id: effect, title: EFFECT_WORDS[effect].title, count: of(effect) })),
  ];
}

/** The cards on one tab, which is the pool the rail counts and the search's total. */
export function onTab(cards: readonly RuleCard[], tab: EffectTab): RuleCard[] {
  return cards.filter((card) => tab === 'all' || card.effect === tab);
}

/** The rail's rows for a tab's pool, a kind nothing falls into left out. */
export function ruleCategoryCounts(pool: readonly RuleCard[]): CategoryCount[] {
  return categoryCounts(pool, (card) => card.category, RULE_CATEGORIES);
}

/** The cards a category and a search leave on screen, in the pool's order. */
export function shownCards(pool: readonly RuleCard[], category: string, query: string): RuleCard[] {
  const words = searchWords(query);
  return pool.filter((card) => (category === ALL_CATEGORIES || card.category === category) && matchesSearch(words, `${card.title} ${card.line} ${card.keywords}`));
}
