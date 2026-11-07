import type { PolicyRuleView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { AS_WRITTEN, plainCaption, plainCountLine, plainGroups, plainRule, writtenLines, type RuleFamily } from '../src/core/domain/plain-rules';

// Mirrors macos/Tests/MemnoxVoiceCoreTests/Domain/Studio/PlainRulesTests.swift, so both platforms say a rule alike.

const rule = (effect: string, actions: string[], extra: Partial<PolicyRuleView['match']> = {}, reason?: string, name = 'a'): PolicyRuleView => ({
  name,
  effect: effect as PolicyRuleView['effect'],
  match: { actions, ...extra },
  sentence: 'raw',
  source: 'default',
  editable: true,
  ...(reason === undefined ? {} : { reason }),
});

const agentName = (kind: string) => (kind === 'codex' ? 'Codex' : kind);
const plain = (each: PolicyRuleView) => plainRule(each, agentName);

describe('PlainRules', () => {
  it('says each family in the words the Mac uses', () => {
    const said: [PolicyRuleView, string, RuleFamily][] = [
      [rule('deny', ['filesystem.read', 'environment.read'], { targets: ['**/.ssh', '**/.ssh/**', '**/.aws', '!**/.env.example'] }), 'Reading secrets and credentials', 'secrets'],
      [rule('ask', ['git.push-force', 'git.branch-d', 'git.reset-hard']), 'Force-pushing and hard resets', 'destructiveGit'],
      [rule('ask', ['filesystem.delete']), 'Deleting files', 'deletes'],
      [rule('ask', ['mcp.*'], { classes: ['write', 'destructive'] }), 'MCP tools that change something', 'mcpTools'],
      [rule('ask', ['http.request']), 'Web requests that change something', 'webRequests'],
      [rule('ask', ['psql.*', '!psql.insert', 'mysql.*']), 'Database changes', 'databaseWrites'],
      [rule('ask', ['aws.*', 'gh.*', 'vercel.*', 'docker.push', 'npm.publish']), 'Cloud, deploy and publish commands', 'cloudTools'],
      [rule('ask', ['*', '!filesystem.*', '!file.*', '!shell.*', '!git.*']), 'Anything outside the usual coding tools', 'outsideCodingTools'],
      [rule('deny', ['*']), 'Every action', 'everything'],
    ];
    for (const [each, title, family] of said) {
      expect(plain(each).title).toBe(title);
      expect(plain(each).family).toBe(family);
    }
  });

  it('falls back to the console’s words or a few names and a count', () => {
    expect(plain(rule('ask', ['git.tag'])).title).toBe('Tagging a release');
    expect(plain(rule('ask', ['git.push'], { branches: ['main'] })).title).toBe('Pushing to main');
    const said = plain(rule('deny', ['code.read', 'test.run', 'ticket.reply', 'data.export', 'llm.spend']));
    expect(said.title).toBe('Read code, run tests, reply to a support ticket and 2 more');
    expect(said.family).toBe('other');
    expect(plain(rule('ask', ['ticket.reply'], { targets: ['/support/**', '!/support/drafts'] })).title).toBe('Reply to a support ticket in /support');
  });

  it('takes the reason, then the family’s line, then what the effect does', () => {
    expect(plain(rule('deny', ['git.push-force'], {}, 'you chose to deny this: it rewrites history somebody pulled')).why).toBe('It rewrites history somebody pulled.');
    expect(plain(rule('ask', ['filesystem.delete'])).why).toBe('Sometimes it really is the build folder, so a person should look first.');
    expect(plain(rule('ask', ['ticket.reply'], {}, 'you chose to be asked about this')).why).toBe('Waits for a person to say yes.');
  });

  it('says which agents a rule is for apart from its title', () => {
    const said = plain(rule('deny', ['filesystem.delete'], { agents: ['codex'] }));
    expect(said.title).toBe('Deleting files');
    expect(plainCaption(said)).toBe('Only for Codex. Sometimes it really is the build folder, so a person should look first.');
  });

  it('shows rules that read and do the same once with a count', () => {
    const rules = [
      rule('ask', ['*', '!git.*'], {}, undefined, 'one'),
      rule('deny', ['filesystem.delete'], {}, undefined, 'two'),
      rule('ask', ['*', '!filesystem.*'], {}, undefined, 'three'),
      rule('deny', ['*', '!git.*'], {}, undefined, 'four'),
      rule('ask', ['*', '!git.*'], { agents: ['codex'] }, undefined, 'five'),
    ];
    const groups = plainGroups(rules);
    expect(groups.map((group) => group.rules.length)).toEqual([2, 1, 1, 1]);
    expect(groups[0]?.rules.map((each) => each.name)).toEqual(['one', 'three']);
    expect(plainCountLine(2)).toBe('2 rules say this');
    expect(plainCountLine(1)).toBeUndefined();
  });

  it('keeps the pattern as written for whoever wants it', () => {
    const written = writtenLines({ actions: ['filesystem.read'], targets: ['**/.ssh/**'] });
    expect(written.map((line) => line.label)).toEqual(['Actions', 'Targets']);
    expect(written.at(-1)?.value).toBe('**/.ssh/**');
    expect(AS_WRITTEN).toBe('Show the rule as written');
  });
});
