import type { PolicyRuleView, RulePackView } from '@memnox/core/wire';
import { matchesSearch, searchWords } from './catalog';
import { LIBRARY_RULES, READY_RULE_CATEGORIES, STARTER_SET, type LibraryRule, type RuleMark } from './ready-rule-library';
import { ruleDocument, ruleText, type RuleTable } from './rule-toml';
import { isEffect, type Effect } from './studio-lines';

/**
 * Ready-made rules as a card offers them, ported from the Mac's `ReadyRules.swift`: the console's library, then the
 * rules of every pack the daemon ships. Nothing here decides anything, because adding one only raises a proposal
 * the person signs on the island.
 */

/** Where the rule's text comes from once it is added. */
export type ReadyRuleOrigin =
  /** The console's library, written out as a table with whichever effect the person chose. */
  | { readonly kind: 'library'; readonly library: LibraryRule }
  /** A pack's rule: the pack's header and this rule's own `[[policies]]` table, imported whole. */
  | { readonly kind: 'pack'; readonly header: string; readonly table: string };

export interface ReadyRule {
  /** The rule's name, which it keeps once in force. */
  readonly id: string;
  readonly title: string;
  readonly says: string;
  readonly actions: readonly string[];
  /** The effect it ships with, offered first and marked Suggested. */
  readonly effect: Effect;
  /** The products and kinds of act it is about; empty for a pack's rule, which a screen draws from its actions. */
  readonly marks: readonly RuleMark[];
  readonly origin: ReadyRuleOrigin;
}

/** Ready-made rules under one heading: a library category, or one pack Memnox ships. */
export interface ReadyRuleGroup {
  readonly id: string;
  readonly title: string;
  readonly rules: readonly ReadyRule[];
}

/** Allow, Ask and Deny, the three choices every card offers; an allow is proposed and signed like any other. */
export const READY_EFFECTS: readonly Effect[] = ['allow', 'ask', 'deny'];

const TABLE = '[[policies]]';
const MATCH_TABLE = '[policies.match]';
const DECISION_TABLE = '[policies.decision]';

/** The library rule as a card offers it. */
export function libraryReadyRule(library: LibraryRule): ReadyRule {
  return { id: library.id, title: library.title, says: library.says, actions: library.match.actions, effect: library.recommended, marks: library.marks, origin: { kind: 'library', library } };
}

/** The library in category order, then every pack in the order the runtime lists them, each keeping only the rules the library does not already offer. */
export function readyGroups(packs: readonly RulePackView[]): ReadyRuleGroup[] {
  const library = READY_RULE_CATEGORIES.map((category) => ({
    id: category.id,
    title: category.title,
    rules: LIBRARY_RULES.filter((rule) => rule.category === category.id).map(libraryReadyRule),
  }));
  const offered = new Set(LIBRARY_RULES.map((rule) => rule.id));
  const shipped = packs.map((pack) => ({ id: pack.id, title: pack.name, rules: packRules(pack).filter((rule) => !offered.has(rule.id)) }));
  return [...library, ...shipped].filter((group) => group.rules.length > 0);
}

/** The runtime's first run set, the library's own rules in library order. */
export function starterRules(): ReadyRule[] {
  return LIBRARY_RULES.filter((rule) => STARTER_SET.includes(rule.id)).map(libraryReadyRule);
}

/** A pack's rules read from its TOML, each kept as text the runtime can import on its own. */
export function packRules(pack: Pick<RulePackView, 'toml'>): ReadyRule[] {
  const lines = pack.toml.split('\n');
  const starts = lines.flatMap((line, index) => (line.trim() === TABLE ? [index] : []));
  const first = starts[0];
  if (first === undefined) return [];
  const header = lines.slice(0, first).join('\n');
  return starts.flatMap((start, index) => {
    const rule = packRule(lines.slice(start, starts[index + 1] ?? lines.length), header);
    return rule === undefined ? [] : [rule];
  });
}

/** The groups a category and a search leave, dropping any group with nothing left in it. Every word of the search has to appear in the title, the line under it, the group or an action, so typing `kubectl` finds the rule. */
export function shownGroups(groups: readonly ReadyRuleGroup[], group: string | undefined, query: string): ReadyRuleGroup[] {
  const words = searchWords(query);
  return groups.flatMap((each) => {
    if (group !== undefined && group !== each.id) return [];
    const kept = words.length === 0 ? each.rules : each.rules.filter((rule) => matchesSearch(words, [rule.title, rule.says, each.title, ...rule.actions].join(' ')));
    return kept.length === 0 ? [] : [{ id: each.id, title: each.title, rules: kept }];
  });
}

/** The rule in force this card stands for, by the name it keeps. */
export function readyInForce(rule: Pick<ReadyRule, 'id'>, rules: readonly PolicyRuleView[]): PolicyRuleView | undefined {
  return rules.find((each) => each.name === rule.id);
}

/** A library rule as the runtime reads it: the reason says who chose the effect, and only a refusal names a way round. */
export function libraryTable(library: LibraryRule, effect: Effect): RuleTable {
  return {
    name: library.id,
    description: library.title,
    match: library.match,
    effect,
    reason: `${chose(effect)}: ${library.because}`,
    ...(effect === 'deny' && library.alternative !== undefined ? { alternative: library.alternative } : {}),
  };
}

/** The rule's table as it goes to the runtime with the effect the person chose. */
export function readyTable(rule: ReadyRule, effect: Effect): string {
  return rule.origin.kind === 'library' ? ruleText(libraryTable(rule.origin.library, effect)) : withEffect(rule.origin.table, effect);
}

/** Several rules as one document to import, each still its own proposal signed on its own. */
export function readyToml(picks: readonly { rule: ReadyRule; effect: Effect }[]): string | undefined {
  if (picks.length === 0) return undefined;
  const header = picks.flatMap((pick) => (pick.rule.origin.kind === 'pack' ? [pick.rule.origin.header] : []))[0];
  const tables = picks.map((pick) => readyTable(pick.rule, pick.effect));
  // A pack's header already opens with the version line, so it stands in for the plain one.
  return header === undefined ? ruleDocument(tables) : [header, ...tables].join('\n');
}

/** The opening of the reason an agent is told, by the effect somebody chose. */
function chose(effect: Effect): string {
  switch (effect) {
    case 'allow':
      return 'you chose to allow this';
    case 'ask':
      return 'you chose to be asked about this';
    case 'deny':
      return 'you chose to deny this';
  }
}

function packRule(lines: readonly string[], header: string): ReadyRule | undefined {
  let section = '';
  let name: string | undefined;
  let description: string | undefined;
  let actions: string[] = [];
  let effect: string | undefined;
  let reason: string | undefined;
  for (const line of lines) {
    const text = line.trim();
    if (text.startsWith('[')) {
      section = text;
      continue;
    }
    const field = `${section} ${keyOf(text) ?? ''}`;
    if (field === `${TABLE} name`) name = quoted(text)[0];
    else if (field === `${TABLE} description`) description = quoted(text)[0];
    else if (field === `${MATCH_TABLE} actions`) actions = quoted(text);
    else if (field === `${DECISION_TABLE} effect`) effect = quoted(text)[0];
    else if (field === `${DECISION_TABLE} reason`) reason = quoted(text)[0];
  }
  if (name === undefined || effect === undefined || !isEffect(effect)) return undefined;
  const says = reason === undefined ? actions.join(', ') : sentence(reason);
  return { id: name, title: description ?? name, says, actions, effect, marks: [], origin: { kind: 'pack', header, table: lines.join('\n') } };
}

/** The table with its decision's effect rewritten, every other line kept as the pack wrote it. */
function withEffect(table: string, effect: Effect): string {
  let section = '';
  return table
    .split('\n')
    .map((line) => {
      const text = line.trim();
      if (text.startsWith('[')) section = text;
      return section === DECISION_TABLE && keyOf(text) === 'effect' ? `effect = "${effect}"` : line;
    })
    .join('\n');
}

/** The key of a `key = value` line, undefined on any other line. */
function keyOf(text: string): string | undefined {
  const equals = text.indexOf('=');
  return equals < 0 ? undefined : text.slice(0, equals).trim();
}

/** Every double quoted string after the line's equals sign, which is all a pack's values are. */
function quoted(text: string): string[] {
  const equals = text.indexOf('=');
  if (equals < 0) return [];
  const parts = text.slice(equals + 1).split('"');
  const values: string[] = [];
  for (let index = 1; index < parts.length; index += 2) values.push(parts[index] ?? '');
  return values;
}

/** A pack's reason is a clause, so a card says it as a sentence. */
function sentence(clause: string): string {
  if (clause === '') return clause;
  const body = clause.charAt(0).toUpperCase() + clause.slice(1);
  return body.endsWith('.') ? body : `${body}.`;
}
