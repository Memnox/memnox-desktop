import type { PolicyRuleView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { groupCountLine, namesLine, ruleAsWritten, ruleGroups, ruleWords } from '../src/core/domain/rule-words';

const rule = (name: string, effect: string, match: PolicyRuleView['match'], reason?: string): PolicyRuleView => ({
  name,
  effect: effect as PolicyRuleView['effect'],
  match,
  sentence: `${effect} ${match.actions.join(', ')}`,
  source: 'default',
  editable: false,
  ...(reason === undefined ? {} : { reason }),
});

const CODING = ['!filesystem.*', '!file.*', '!fs.*', '!shell.*', '!process.*', '!git.*', '!editor.*', '!test.*', '!build.*', '!package.*'];

describe('a rule in plain words', () => {
  it('reads the setup’s credential rule as secrets rather than a list of globs', () => {
    const secrets = rule('filesystem-deny', 'deny', { actions: ['filesystem.read', 'environment.read'], targets: ['**/.ssh', '**/.ssh/**', '**/.aws', '**/.env', '!**/.env.example', '*_TOKEN'] }, 'you chose to deny this: almost no task needs the key itself, and a leaked one is somebody’s weekend');
    expect(ruleWords(secrets)).toEqual({ title: 'Reading secrets and credentials', why: 'Almost no task needs the key itself, and a leaked one is somebody’s weekend.' });
  });

  it('names the common families the way the console does', () => {
    const title = (actions: string[], extra: Partial<PolicyRuleView['match']> = {}) => ruleWords(rule('r', 'ask', { actions, ...extra })).title;
    expect(title(['git.push-force', 'git.push-f', 'git.reset-hard', 'git.clean-fd', 'git.reset'])).toBe('Force-pushing and hard resets');
    expect(title(['filesystem.delete'])).toBe('Deleting files');
    expect(title(['mcp.*'], { classes: ['write', 'destructive'] })).toBe('MCP tools that change something');
    expect(title(['http.request'])).toBe('Web requests that change something');
    expect(title(['aws.*', 'gcloud.*', 'kubectl.*', 'psql.*', 'docker.push', 'npm.publish'])).toBe('Cloud, deploy and publish commands');
    expect(title(['psql.*', '!psql.insert', 'mongosh.*', 'sqlite3.*'])).toBe('Database changes');
    expect(title(['*', ...CODING])).toBe('Anything outside the usual coding tools');
    expect(title(['*'])).toBe('Every action');
    expect(title(['git.push'], { branches: ['main'] })).toBe('Pushing to main');
  });

  it('falls back to at most three names and a count, with where it holds', () => {
    expect(ruleWords(rule('r', 'deny', { actions: ['git.tag'] })).title).toBe('Tagging a release');
    expect(ruleWords(rule('r', 'deny', { actions: ['a.one', 'b.two', 'c.three', 'd.four', 'e.five'] })).title).toBe('a.one, b.two, c.three and 2 more');
    expect(ruleWords(rule('r', 'ask', { actions: ['filesystem.write'], targets: ['**/infra/**', '**/deploy/**'] })).title).toBe('Changing files in infra and deploy');
    expect(namesLine(['x', 'y'])).toBe('x and y');
    expect(namesLine(['x', 'x'])).toBe('x');
  });

  it('says why in one line: its own reason without the setup’s prefix, else the family’s, else what the effect does', () => {
    expect(ruleWords(rule('r', 'ask', { actions: ['filesystem.delete'] }, 'you chose to be asked about this: sometimes it really is the build directory')).why).toBe('Sometimes it really is the build directory.');
    expect(ruleWords(rule('r', 'ask', { actions: ['filesystem.delete'] }, 'you chose to ask this')).why).toBe('Sometimes it really is the build directory, so a person should look.');
    expect(ruleWords(rule('r', 'deny', { actions: ['odd.thing'] })).why).toBe('Refused, and told what to do instead.');
  });
});

describe('rules gathered by what they say', () => {
  it('collapses rows whose title and effect match into one with a count, in first seen order', () => {
    const rules = [
      rule('consequential-ask', 'ask', { actions: ['*', ...CODING] }, 'you chose to be asked about this: a refund should be a person’s'),
      rule('production-ask', 'ask', { actions: ['*', ...CODING] }, 'you chose to be asked about this: changing production is where an incident gets made'),
      rule('mcp-ask', 'ask', { actions: ['mcp.*'] }),
      rule('everything-deny', 'deny', { actions: ['*', ...CODING] }),
      rule('odd', 'shrug', { actions: ['git.push'] }),
    ];
    const groups = ruleGroups(rules);
    expect(groups.map((group) => `${group.title} ${group.effect} ${group.rules.length}`)).toEqual([
      'Anything outside the usual coding tools ask 2',
      'MCP tools that change something ask 1',
      'Anything outside the usual coding tools deny 1',
    ]);
    // Two reasons that differ give way to the family's own line.
    expect(groups[0]?.why).toBe('Files, the shell, git, tests and builds go ahead, while the rest reaches past this computer.');
    expect(groupCountLine(2)).toBe('2 rules say this');
    expect(groupCountLine(1)).toBeUndefined();
  });

  it('keeps the raw pattern field by field for the disclosure', () => {
    expect(ruleAsWritten(rule('r', 'ask', { actions: ['git.push'], branches: ['main'], targets: [] }))).toEqual([
      { field: 'Actions', values: 'git.push' },
      { field: 'Branches', values: 'main' },
    ]);
  });
});
