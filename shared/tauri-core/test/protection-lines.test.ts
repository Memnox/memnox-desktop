import type { PolicyRuleView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { LIBRARY_RULES } from '../src/core/domain/ready-rule-library';
import { libraryReadyRule, starterRules, type ReadyRule } from '../src/core/domain/ready-rules';
import {
  canChange,
  changeCountLine,
  changeLine,
  changesToml,
  flatRules,
  inForceAs,
  pickingSuggested,
  PROTECTION,
  PROTECTION_TABS,
  readyBadge,
  readyChanges,
  removals,
} from '../src/core/domain/protection-lines';

/** Mirrors macos/Tests/MemnoxVoiceCoreTests/Domain/Studio/ProtectionLinesTests.swift, so both desktops say the console's words. */

const rule = (name: string, effect: PolicyRuleView['effect'], actions: string[], editable = true, branches?: string[]): PolicyRuleView => ({
  name,
  effect,
  match: { actions, ...(branches === undefined ? {} : { branches }) },
  sentence: '',
  source: editable ? 'person' : 'file',
  editable,
});

describe('Protection settings in the console words', () => {
  it('lists the tabs in the console order', () => {
    expect(PROTECTION_TABS.map((tab) => tab.title)).toEqual(['Ready-made rules', 'All rules']);
  });

  it('says the console words for the ready-made rules and their save', () => {
    expect(PROTECTION.search).toBe('Search by tool, command or what it protects: kubectl, refund, secrets');
    expect(PROTECTION.starter).toBe('Add the starter set');
    expect(`${PROTECTION.noneMatchTitle} ${PROTECTION.noneMatchDetail}`).toBe('No ready-made rule matches that. Propose your own under All rules.');
    expect(inForceAs('ask')).toBe('In force as ask');
    expect([PROTECTION.notSaved, PROTECTION.undo, PROTECTION.review]).toEqual(['Not saved yet', 'Undo', 'Review and save']);
    expect(PROTECTION.previewed).toBe('Not saved yet. Nothing has changed.');
    expect(PROTECTION.readyIntro('Windows Hello')).toBe('Rules written for you. Choose Allow, Ask or Deny on one; it holds once you confirm it with Windows Hello.');
    expect(PROTECTION.reviewDescription('Windows Hello')).toBe('Saving proposes each change, and it takes effect once you confirm it with Windows Hello on the island.');
    expect(changeCountLine(1)).toBe('1 change');
    expect(changeCountLine(3)).toBe('3 changes');
  });

  it('points between the tabs as the console does', () => {
    expect(PROTECTION.simplerTitle).toBe('Want the simple version?');
    expect(PROTECTION.startTitle).toBe('Start from a ready-made rule');
    expect(PROTECTION.handOver).toBe('See what to hand over');
    expect(PROTECTION.readyToHandOver).toBe('Ready to hand over');
    expect(PROTECTION.stopAsking).toBe('Stop asking');
  });

  it('holds no dash in any line', () => {
    const lines = [...Object.values(PROTECTION).map((each) => (typeof each === 'function' ? each('Touch ID') : each))];
    for (const line of lines) expect(line).not.toMatch(/\u2014|\u2013| - /);
  });
});

/** Mirrors macos/Tests/MemnoxVoiceCoreTests/Domain/Studio/ReadyRuleChangesTests.swift. */
describe('the ready-made rules read against what holds', () => {
  const history = libraryReadyRule(LIBRARY_RULES[0]!);
  const deleting = starterRules()[1]!;
  const held = (each: ReadyRule, effect: PolicyRuleView['effect'], editable = true) => rule(each.id, effect, [...each.actions], editable);

  it('says the effect in force or Not added on the badge', () => {
    const inForce = [held(history, 'deny')];
    expect(readyBadge(history, inForce)).toEqual({ word: 'In force as deny', tone: 'bad' });
    expect(readyBadge(deleting, inForce)).toEqual({ word: 'Not added', tone: 'quiet' });
  });

  it('gathers only picks that change what holds', () => {
    const inForce = [held(history, 'deny')];
    expect(readyChanges({ [history.id]: 'deny', [deleting.id]: 'ask' }, [history, deleting], inForce)).toEqual([{ rule: deleting, to: 'ask' }]);
    const moved = readyChanges({ [history.id]: 'ask' }, [history], inForce);
    expect(moved.map(changeLine)).toEqual(['Deny to Ask']);
    expect(removals(moved)).toEqual([history.id]);
  });

  it('leaves a rule from a file to where it came from', () => {
    const inForce = [held(history, 'deny', false)];
    expect(canChange(history, inForce)).toBe(false);
    expect(readyChanges({ [history.id]: 'ask' }, [history], inForce)).toEqual([]);
    expect(canChange(deleting, inForce)).toBe(true);
  });

  it('picks the suggested effect for every rule not added yet, keeping a pick already made', () => {
    const inForce = [held(history, 'deny')];
    expect(pickingSuggested([history, deleting], {}, inForce)).toEqual({ [deleting.id]: deleting.effect });
    expect(pickingSuggested([deleting], { [deleting.id]: 'deny' }, [])).toEqual({ [deleting.id]: 'deny' });
  });

  it('counts the changes', () => {
    expect(changeCountLine(1)).toBe('1 change');
    expect(changeLine({ rule: deleting, to: 'allow' })).toBe('Not added to Allow');
  });

  it('writes an allow like any other effect with no way round', () => {
    const toml = changesToml([{ rule: history, to: 'allow' }]) ?? '';
    expect(toml).toContain('effect = "allow"');
    expect(toml).not.toContain('[policies.decision.alternative]');
    expect(changesToml([])).toBeUndefined();
  });

  it('lists each rule once across groups', () => {
    const groups = [
      { id: 'a', title: 'A', rules: [history, deleting] },
      { id: 'b', title: 'B', rules: [history] },
    ];
    expect(flatRules(groups).map((each) => each.id)).toEqual([history.id, deleting.id]);
  });
});
