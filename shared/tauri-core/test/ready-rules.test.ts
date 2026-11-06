import type { PolicyRuleView, RulePackView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { LIBRARY_RULES, markToolkit, READY_RULE_CATEGORIES, STARTER_SET } from '../src/core/domain/ready-rule-library';
import { libraryReadyRule, libraryTable, packRules, READY_EFFECTS, readyGroups, readyInForce, readyTable, readyToml, shownGroups, starterRules } from '../src/core/domain/ready-rules';
import { ACTION_PLACEHOLDER, fieldWords, RULES_HEADER, ruleDocument, ruleText, tableOfDraft, toggledWord } from '../src/core/domain/rule-toml';

/** Mirrors ReadyRulesTests, ReadyRuleLibraryTests and RuleTomlTests under macos/Tests/MemnoxVoiceCoreTests/Domain/Studio. */

const toml = `# A rule pack.
version = 1

[pack]
name = "Safe defaults"
description = "Agents work freely."

[[policies]]
name = "pack-delete-ask"
description = "Deleting files"

[policies.match]
actions = [ "filesystem.delete" ]

[policies.decision]
effect = "ask"
reason = "a delete is sometimes the only copy"

[[policies]]
name = "pack-history-deny"
description = "Force pushing and hard resets"

[policies.match]
actions = [ "git.push-force", "git.reset-hard" ]

[policies.decision]
effect = "deny"
reason = "it rewrites history."`;

const pack: RulePackView = { id: 'safe-defaults', name: 'Safe defaults', description: '', ruleCount: 2, toml };

const library = (id: string) => {
  const found = LIBRARY_RULES.find((rule) => rule.id === id);
  if (found === undefined) throw new Error(`the library carries ${id}`);
  return found;
};

describe('the ready-made rules', () => {
  it('reads each pack rule with its own importable text', () => {
    const rules = packRules(pack);
    expect(rules.map((rule) => rule.id)).toEqual(['pack-delete-ask', 'pack-history-deny']);
    expect(rules.map((rule) => rule.title)).toEqual(['Deleting files', 'Force pushing and hard resets']);
    expect(rules.map((rule) => rule.says)).toEqual(['A delete is sometimes the only copy.', 'It rewrites history.']);
    expect(rules[1]?.actions).toEqual(['git.push-force', 'git.reset-hard']);
    expect(rules.map((rule) => rule.effect)).toEqual(['ask', 'deny']);
    const text = readyToml([{ rule: rules[1]!, effect: 'deny' }]);
    expect(text).toContain('[pack]');
    expect(text).toContain('pack-history-deny');
    expect(text).not.toContain('pack-delete-ask');
  });

  it('puts the library first in category order, then the packs', () => {
    const groups = readyGroups([pack]);
    expect(groups.map((group) => group.id)).toEqual([...READY_RULE_CATEGORIES.map((category) => category.id), 'safe-defaults']);
    expect(groups[0]?.title).toBe('Code and git');
    expect(groups[0]?.rules[0]?.marks).toEqual(['git']);
  });

  it('drops a pack rule the library already offers', () => {
    const doubled: RulePackView = {
      id: 'doubled',
      name: 'Doubled',
      description: '',
      ruleCount: 1,
      toml: 'version = 1\n\n[[policies]]\nname = "no-history-rewrites"\n\n[policies.match]\nactions = [ "git.push-force" ]\n\n[policies.decision]\neffect = "deny"',
    };
    expect(readyGroups([doubled]).some((group) => group.id === 'doubled')).toBe(false);
  });

  it('narrows by group and by every word of the search', () => {
    const groups = readyGroups([pack]);
    expect(shownGroups(groups, 'safe-defaults', '').map((group) => group.id)).toEqual(['safe-defaults']);
    expect(shownGroups(groups, undefined, 'RESET pushing').flatMap((group) => group.rules.map((rule) => rule.id))).toEqual(['pack-history-deny']);
    expect(shownGroups(groups, undefined, 'kubectl.drain').flatMap((group) => group.rules.map((rule) => rule.id))).toEqual(['ask-before-kubernetes-deletes']);
    expect(shownGroups(groups, undefined, 'nothing-matches-this')).toEqual([]);
  });

  it('rewrites only the decision effect of a pack rule', () => {
    const table = readyTable(packRules(pack)[0]!, 'deny');
    expect(table).toContain('effect = "deny"');
    expect(table).not.toContain('effect = "ask"');
    expect(table).toContain('name = "pack-delete-ask"');
  });

  it('writes a library rule with who chose it and the way round only when refused', () => {
    const history = library('no-history-rewrites');
    const denied = libraryTable(history, 'deny');
    expect(denied.reason).toBe('you chose to deny this: it rewrites history somebody else may already have pulled');
    expect(denied.alternative?.action).toBe('git.push');
    const asked = libraryTable(history, 'ask');
    expect(asked.reason).toBe('you chose to be asked about this: it rewrites history somebody else may already have pulled');
    expect(asked.alternative).toBeUndefined();
    const document = readyToml([{ rule: libraryReadyRule(history), effect: 'ask' }]);
    expect(document?.startsWith(RULES_HEADER)).toBe(true);
    expect(document).not.toContain('[policies.decision.alternative]');
  });

  it('finds the rule in force by its name', () => {
    const rules: PolicyRuleView[] = [{ name: 'pack-history-deny', effect: 'deny', match: { actions: ['git.push-force'] }, sentence: '', source: 'person', editable: true }];
    const ready = packRules(pack);
    expect(readyInForce(ready[1]!, rules)?.name).toBe('pack-history-deny');
    expect(readyInForce(ready[0]!, rules)).toBeUndefined();
  });

  it('offers the starter set in library order', () => {
    expect(starterRules().map((rule) => rule.id)).toEqual([
      'no-history-rewrites', 'ask-before-deleting-files', 'ask-before-changing-production', 'ask-before-moving-money',
      'keep-out-of-credentials', 'ask-before-mcp-changes', 'ask-before-http-changes',
    ]);
  });
});

describe('the library', () => {
  it('carries every console rule once under its own name', () => {
    const ids = LIBRARY_RULES.map((rule) => rule.id);
    expect(ids.length).toBe(38);
    expect(new Set(ids).size).toBe(ids.length);
    expect(STARTER_SET.every((id) => ids.includes(id))).toBe(true);
  });

  it('suggests only effects that hold something', () => {
    expect(READY_EFFECTS).toEqual(['allow', 'ask', 'deny']);
    for (const rule of LIBRARY_RULES) {
      expect(rule.recommended, rule.id).not.toBe('allow');
      expect(rule.match.actions.length, rule.id).toBeGreaterThan(0);
      expect(rule.marks.length, rule.id).toBeGreaterThan(0);
    }
  });

  it('draws a product with its Composio logo and a kind of act as a glyph', () => {
    expect(markToolkit('github')).toBe('github');
    expect(markToolkit('docker')).toBe('docker_hub');
    expect(markToolkit('postgresql')).toBe('postgres');
    expect(markToolkit('git')).toBeUndefined();
    expect(markToolkit('kubernetes')).toBeUndefined();
  });

  it('writes the production rule with its environments and classes', () => {
    const text = ruleText(libraryTable(library('ask-before-changing-production'), 'ask'));
    expect(text).toContain('environments = [ "prod*", "production", "live" ]');
    expect(text).toContain('classes = [ "write", "destructive", "communication" ]');
    expect(text).toContain('"!git.*"');
  });

  it('holds no dash in any line a card shows', () => {
    for (const rule of LIBRARY_RULES) {
      for (const line of [rule.title, rule.says, rule.because, rule.alternative?.note ?? '']) expect(line).not.toMatch(/\u2014|\u2013| - /);
    }
  });
});

describe('the rules file writer', () => {
  it('writes a rule in the runtime table shape', () => {
    const text = ruleText({
      name: 'no-history-rewrites',
      match: { actions: ['git.push-force'], agents: ['claude-code'] },
      effect: 'deny',
      reason: 'it rewrites history',
      alternative: { action: 'git.push', note: 'Push a branch.' },
    });
    expect(text).toBe(
      [
        '[[policies]]',
        'name = "no-history-rewrites"',
        '',
        '[policies.match]',
        'actions = [ "git.push-force" ]',
        'agents = [ "claude-code" ]',
        '',
        '[policies.decision]',
        'effect = "deny"',
        'reason = "it rewrites history"',
        '',
        '[policies.decision.alternative]',
        'action = "git.push"',
        'note = "Push a branch."',
      ].join('\n'),
    );
  });

  it('writes arguments in their own table and escapes quotes', () => {
    const text = ruleText({ name: 'http', match: { actions: ['http.request'], arguments: [{ name: 'method', values: ['POST'] }] }, effect: 'ask', reason: 'a "change"' });
    expect(text).toContain('[policies.match.arguments]\nmethod = [ "POST" ]');
    expect(text).toContain('reason = "a \\"change\\""');
  });

  it('writes a draft with its data and a placeholder until an action is named', () => {
    const empty = tableOfDraft({ effect: 'ask', action: '', reason: 'why' });
    expect(empty.name).toBe('rule-ask');
    expect(empty.match.actions).toEqual([ACTION_PLACEHOLDER]);
    const table = tableOfDraft({ effect: 'deny', action: 'Vercel.deploy-prod', targets: ['!api.stripe.com'], reason: 'why' }, ['secret']);
    expect(table.name).toBe('vercel-deploy-prod-deny');
    expect(ruleText(table)).toContain('targets = [ "!api.stripe.com" ]\ndataClassifications = [ "secret" ]');
  });

  it('toggles a word in a comma separated field', () => {
    expect(toggledWord('secret', '')).toBe('secret');
    expect(toggledWord('health', 'secret, codename')).toBe('secret, codename, health');
    expect(toggledWord('secret', 'secret, codename')).toBe('codename');
    expect(fieldWords(' , ')).toBeUndefined();
  });

  it('opens a document with the version line', () => {
    expect(ruleDocument(['a', 'b'])).toBe('version = 1\n\na\n\nb');
  });
});
