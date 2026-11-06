import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { actionPhrase, RULE_BUILDER, RULE_DETAIL, RULE_DIALOG, RULE_EXAMPLES, ruleCaption, ruleDetailSentence, ruleFacts } from '../src/core/domain/rule-dialog-lines';
import { inForceTabs } from '../src/core/domain/protection-lines';
import { ruleAsWritten } from '../src/core/domain/rule-words';
import { tomlLine, tomlLines } from '../src/core/domain/toml-tokens';

/**
 * The propose dialog and a rule's details say what the Mac says. The Mac keeps these words inline, so the test reads
 * its sources and finds each one there as a Swift string, "this computer" read back as "this Mac" where it differs.
 */
const mac = (path: string) => readFileSync(fileURLToPath(new URL(`../../../macos/Sources/${path}`, import.meta.url)), 'utf8');
const app = 'MemnoxVoice/Presentation/App';
const swift = [mac(`${app}/RuleDialogParts.swift`), mac(`${app}/RuleBuilderSheet.swift`), mac(`${app}/PoliciesDestination.swift`), mac('MemnoxVoiceCore/Domain/Studio/PlainRules.swift')].join('\n');
const said = (text: string) => swift.includes(`"${text}"`) || swift.includes(`"${text.replace(/this computer/g, 'this Mac')}"`);

describe('the rule dialogs use the Mac words', () => {
  it('frames every dialog the same', () => {
    const { proposeDescription, ...plain } = RULE_DIALOG;
    for (const text of Object.values(plain)) expect(said(text), text).toBe(true);
    expect(proposeDescription('Touch ID').replace('this computer', 'this Mac')).toBe('It is proposed on this Mac and holds once you sign it with Touch ID on the island.');
  });

  it('names every field of Propose a rule the same', () => {
    const { readBack, classesHint, ...plain } = RULE_BUILDER;
    for (const text of Object.values(plain)) expect(said(text), text).toBe(true);
    expect(classesHint).toBe('What the action does: read, write, destructive, communication, unknown. A send needs none, since the data it carries and where it goes already narrow it.');
    expect(swift).toContain('"This rule would say: \\(sentence)"');
    expect(readBack('x')).toBe('This rule would say: x');
  });

  it('offers the same examples in the same order', () => {
    let at = 0;
    for (const example of RULE_EXAMPLES) {
      at = swift.indexOf(`("${example.action}", "${example.title}")`, at);
      expect(at, example.title).toBeGreaterThan(-1);
    }
  });

  it('says a rule in its details the same', () => {
    for (const text of Object.values(RULE_DETAIL)) expect(said(text), text).toBe(true);
    const rule = { name: 'git-push-ask', source: 'file', file: 'memnox.policies.toml', until: '2026-11-06T10:00:00Z' } as const;
    expect(ruleFacts(rule, () => 'Nov 6').map(([label]) => label)).toEqual(['Name', 'From', 'File', 'Until']);
    expect(ruleAsWritten({ match: { actions: ['git.push'], classes: ['write'] } }).at(-1)?.field).toBe('Kinds of call');
  });

  it('reads a rule back as one sentence', () => {
    expect(actionPhrase('filesystem.delete')).toBe('Delete a file');
    expect(actionPhrase('mcp.stripe.create')).toBe('Create stripe');
    expect(actionPhrase('brew.unknown')).toBe('A brew command Memnox does not recognise');
    expect(actionPhrase('https://x')).toBe('Automated action');
    expect(ruleDetailSentence({ actions: ['git.commit'], targets: ['main'], effect: 'deny' }, (kind) => kind)).toBe('When any agent tries to commit code on main, it is refused and told what to do instead.');
    expect(ruleCaption(['claude', 'codex'], 'Why.', (kind) => kind)).toBe('Only for claude and codex. Why.');
    expect(ruleCaption(undefined, 'Why.', (kind) => kind)).toBe('Why.');
  });

  it('counts the effect tabs by rule, as the Mac does', () => {
    expect(inForceTabs([{ effect: 'ask' }, { effect: 'ask' }, { effect: 'deny' }]).map((tab) => `${tab.title} ${tab.count}`)).toEqual(['All 3', 'Allow 0', 'Ask 2', 'Deny 1']);
  });
});

describe('TOML is coloured as the Mac colours it', () => {
  it('cuts a line into the same runs', () => {
    expect(tomlLine('[[policies]]')).toEqual([{ text: '[[policies]]', kind: 'table' }]);
    expect(tomlLine('actions = ["git.push", "x"] # why')).toEqual([
      { text: 'actions', kind: 'key' },
      { text: ' ', kind: 'plain' },
      { text: '=', kind: 'punctuation' },
      { text: ' ', kind: 'plain' },
      { text: '[', kind: 'punctuation' },
      { text: '"git.push"', kind: 'string' },
      { text: ',', kind: 'punctuation' },
      { text: ' ', kind: 'plain' },
      { text: '"x"', kind: 'string' },
      { text: ']', kind: 'punctuation' },
      { text: ' ', kind: 'plain' },
      { text: '# why', kind: 'comment' },
    ]);
    expect(tomlLines('a\n\n# c').map((line) => line.map((token) => token.text).join(''))).toEqual(['a', '', '# c']);
  });
});
