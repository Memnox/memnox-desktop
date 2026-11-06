import type { PolicyRuleView } from '@memnox/core/wire';
import { readyInForce, readyToml, type ReadyRule, type ReadyRuleGroup } from './ready-rules';
import { EFFECT_WORDS, effectTone, isEffect, type Effect } from './studio-lines';

/**
 * The words of Protection settings, the console's own except where this computer signs in place of an admin
 * approving, and the same as the Mac says them in ProtectionLines.swift. Team and fleet sentences are left out,
 * since one machine has neither. This only words and sorts what the daemon sent; it decides nothing.
 */

export type ProtectionTab = 'readyMade' | 'allRules' | 'autonomy';

/** The tabs drawn. Autonomy is left off for now, since Ready to hand over on Home already offers the same. */
export const PROTECTION_TABS: readonly { id: ProtectionTab; title: string }[] = [
  { id: 'readyMade', title: 'Ready-made rules' },
  { id: 'allRules', title: 'All rules' },
];

export const PROTECTION = {
  // Ready-made rules, as the console's library and its choices say them.
  readyIntro: (keyTitle: string) => `Rules written for you. Choose Allow, Ask or Deny on one; it holds once you confirm it with ${keyTitle}.`,
  search: 'Search by tool, command or what it protects: kubectl, refund, secrets',
  searchLabel: 'Search ready-made rules',
  allRules: 'All rules',
  starter: 'Add the starter set',
  /** Under one category, the console's own words for taking every suggestion there. */
  everySuggestion: 'Use every suggestion',
  noneMatchTitle: 'No ready-made rule matches that.',
  noneMatchDetail: 'Propose your own under All rules.',
  notAdded: 'Not added',
  suggested: 'Suggested',
  changed: 'Changed',
  details: 'Details',
  /** Said over the review when a rule in force is changed, since that takes two signatures. */
  retaken: 'A rule already in force is changed by taking it out and adding it again, so each waits for your signature on the island.',
  starterHelp: 'Sets the suggested effect on each rule not added yet; nothing is proposed until you review and save',
  // The bar and the review, as the console's choices save.
  notSaved: 'Not saved yet',
  undo: 'Undo',
  review: 'Review and save',
  previewed: 'Not saved yet. Nothing has changed.',
  save: 'Save',
  saving: 'Saving',
  reviewDescription: (keyTitle: string) => `Saving proposes each change, and it takes effect once you confirm it with ${keyTitle} on the island.`,
  // All rules, as the console's full list.
  allIntro: 'Every rule your AI follows, in full. Each one either lets it go ahead, makes it ask you first, or stops it.',
  simplerTitle: 'Want the simple version?',
  simplerNote: 'Choose Allow, Ask or Deny in plain words, one thing at a time.',
  startTitle: 'Start from a ready-made rule',
  startNote: 'Rules written for you, for force pushes, deploys, payments and secrets. Add one in a click.',
  handOver: 'See what to hand over',
  propose: 'Propose a rule',
  rulesInForce: 'Rules in force',
  allTab: 'All',
  noRuleHere: 'No rule here yet',
  noRuleHereBody: 'A rule with this effect shows here once one holds.',
  noRules: 'No rules yet',
  noRulesBody: 'A rule comes from an Allow from now on answer, a ready-made rule, or one proposed here.',
  // Autonomy, as the console's hand over page.
  autonomyIntro: 'What your agents could start doing on their own, based on what you keep saying yes to.',
  readyToHandOver: 'Ready to hand over',
  stopAsking: 'Stop asking',
  proposing: 'Proposing',
  nothingReady: 'Nothing ready yet',
  nothingReadyBody: 'When you say yes to the same action several times and never no, it shows here as something you can hand over.',
  almostCaption: 'It needs the same yes a few more times, with no refusal.',
  takeBack: 'Take it back',
} as const;

/** "In force as ask", the badge of a ready-made rule that holds. */
export function inForceAs(effect: Effect): string {
  return `In force as ${EFFECT_WORDS[effect].title.toLowerCase()}`;
}

/** "1 change", "3 changes", the bar's count. */
export function changeCountLine(count: number): string {
  return count === 1 ? '1 change' : `${count} changes`;
}

/** The effect a rule in force holds with, undefined for a word this app does not know. */
function effectOf(rule: PolicyRuleView): Effect | undefined {
  return isEffect(rule.effect) ? rule.effect : undefined;
}

/**
 * What a ready-made card shows and what the bar under the cards gathers, ported from the Mac's
 * `ReadyRuleChanges.swift`. Nothing here decides anything, because every change is still proposed to the runtime
 * and signed on the island.
 */

/** One change waiting in the bar: the rule, what holds now, and the effect picked. */
export interface ReadyChange {
  readonly rule: ReadyRule;
  /** The effect in force now, undefined while the rule is not added. */
  readonly from?: Effect;
  readonly to: Effect;
}

/** The effect the rule holds with now, undefined while it is not in force or holds with a word this app does not know. */
export function currentEffect(rule: ReadyRule, among: readonly PolicyRuleView[]): Effect | undefined {
  const live = readyInForce(rule, among);
  return live === undefined ? undefined : effectOf(live);
}

/** The card's badge: In force as its effect, as the console's card says it, or Not added in grey. */
export function readyBadge(rule: ReadyRule, among: readonly PolicyRuleView[]): { word: string; tone: ReturnType<typeof effectTone> } {
  const live = readyInForce(rule, among);
  if (live === undefined) return { word: PROTECTION.notAdded, tone: 'quiet' };
  const effect = effectOf(live);
  return { word: effect === undefined ? live.effect : inForceAs(effect), tone: effectTone(live.effect) };
}

/** A rule not added yet, or one a person added on this machine; one from a file or the workspace changes where it came from. */
export function canChange(rule: ReadyRule, among: readonly PolicyRuleView[]): boolean {
  return readyInForce(rule, among)?.editable ?? true;
}

/** The picks that change something, in the order the rules are listed; a pick equal to what holds is dropped. */
export function readyChanges(picked: Readonly<Record<string, Effect>>, rules: readonly ReadyRule[], among: readonly PolicyRuleView[]): ReadyChange[] {
  const seen = new Set<string>();
  return rules.flatMap((rule) => {
    if (seen.has(rule.id)) return [];
    seen.add(rule.id);
    const to = picked[rule.id];
    if (to === undefined || !canChange(rule, among)) return [];
    const from = currentEffect(rule, among);
    return from === to ? [] : [{ rule, to, ...(from === undefined ? {} : { from }) }];
  });
}

/** The picks with every rule given not added yet set to its suggested effect, as Add all and the starter set do; a pick already made is kept. */
export function pickingSuggested(rules: readonly ReadyRule[], picked: Readonly<Record<string, Effect>>, among: readonly PolicyRuleView[]): Record<string, Effect> {
  const next = { ...picked };
  for (const rule of rules) if (readyInForce(rule, among) === undefined && next[rule.id] === undefined) next[rule.id] = rule.effect;
  return next;
}

/** Every rule of the groups once, in their order, for a grid that draws no headings. */
export function flatRules(groups: readonly ReadyRuleGroup[]): ReadyRule[] {
  const seen = new Set<string>();
  return groups.flatMap((group) => group.rules).filter((rule) => (seen.has(rule.id) ? false : (seen.add(rule.id), true)));
}

/** "Not added to Ask", "Ask to Deny", one change as the review lists it. */
export function changeLine(change: ReadyChange): string {
  const from = change.from === undefined ? PROTECTION.notAdded : EFFECT_WORDS[change.from].title;
  return `${from} to ${EFFECT_WORDS[change.to].title}`;
}

/** The rules in force a change takes out first, by name, since a changed effect is the old rule gone and the new one proposed. */
export function removals(changes: readonly ReadyChange[]): string[] {
  return changes.filter((change) => change.from !== undefined).map((change) => change.rule.id);
}

/** Every change as one document to import, each rule still its own proposal signed on its own. */
export function changesToml(changes: readonly ReadyChange[]): string | undefined {
  return readyToml(changes.map((change) => ({ rule: change.rule, effect: change.to })));
}

/** All, then Allow, Ask and Deny over the rules in force, each counting rules rather than rows, as the Mac counts them. */
export function inForceTabs(rules: readonly Pick<PolicyRuleView, 'effect'>[]): { id: 'all' | Effect; title: string; count: number }[] {
  const of = (effect: Effect) => rules.filter((rule) => rule.effect === effect).length;
  return [{ id: 'all', title: PROTECTION.allTab, count: rules.length }, ...(Object.keys(EFFECT_WORDS) as Effect[]).map((effect) => ({ id: effect, title: EFFECT_WORDS[effect].title, count: of(effect) }))];
}
