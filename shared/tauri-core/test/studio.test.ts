import type { PolicyRulesView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { RequestIds } from '../src/core/application/request-ids';
import { Activity, Agents, Studio } from '../src/core/application/studio';
import { almostLine, countsByEffect, exportedCount, sourceWords, weekLine } from '../src/core/domain/studio-lines';
import { ScriptedDaemon } from './doubles';

const rules: PolicyRulesView = {
  rules: [
    { name: 'git-deny', effect: 'deny', match: { actions: ['git.push-force'] }, sentence: 'Deny force pushes', source: 'file', file: 'memnox.policies.toml', editable: false },
    { name: 'mine', effect: 'ask', match: { actions: ['filesystem.delete'] }, sentence: 'Ask before deleting', source: 'person', editable: true },
  ],
  problems: [],
  missing: [],
};

describe('the rules as the window keeps them', () => {
  it('says a new rule waits for a signature rather than claiming it is in force', async () => {
    const daemon = new ScriptedDaemon({ 'rule-propose': (request) => [{ id: request.id, ok: true, proposed: 'prp_9' }] });
    const studio = new Studio(daemon, new RequestIds());
    expect(await studio.propose({ effect: 'ask', action: 'git.push', reason: 'main is shared', branches: ['main'] })).toEqual({ kind: 'proposed', id: 'prp_9' });
    expect(daemon.sent('rule-propose')[0]).toMatchObject({ ruleDraft: { action: 'git.push', branches: ['main'] } });
  });

  it('reads rules and progress together, and says when the rules could not be read', async () => {
    const daemon = new ScriptedDaemon({
      rules: (request) => [{ id: request.id, ok: true, policyRules: rules }],
      progress: (request) => [{ id: request.id, ok: false, error: 'no method progress' }],
    });
    const studio = new Studio(daemon, new RequestIds());
    await studio.refresh();
    expect(studio.rules?.rules).toHaveLength(2);
    expect(studio.progress).toBeUndefined();
    expect(studio.unreadable).toBe(false);
  });
});

describe('activity a page at a time', () => {
  it('reads on from where the last page stopped, and starts over when the filter changes', async () => {
    let page = 0;
    const row = (id: string) => ({ id, at: '2026-10-30T10:00:00Z', agent: 'claude-code', agentName: 'Claude Code', session: 's', kind: 'command' as const, operation: 'git.push', effect: 'ask' as const, reason: 'asked' });
    const daemon = new ScriptedDaemon({
      activity: (request) => {
        page += 1;
        return [{ id: request.id, ok: true, activity: page === 1 ? { rows: [row('a')], nextCursor: 'c1' } : { rows: [row('b')] } }];
      },
    });
    const activity = new Activity(daemon, new RequestIds());
    await activity.show({ effect: 'ask' });
    expect(activity.more).toBe(true);
    await activity.readOn();
    expect(activity.rows.map((each) => each.id)).toEqual(['a', 'b']);
    expect(activity.more).toBe(false);
    expect(daemon.sent('activity')[1]).toMatchObject({ activityCursor: 'c1', activityFilter: { effect: 'ask' } });
  });
});

describe('agents', () => {
  it('passes resuming on for a signature, since it gives an agent back its reach', async () => {
    const daemon = new ScriptedDaemon({ 'agent-resume': (request) => [{ id: request.id, ok: true, proposed: 'prp_r' }] });
    expect(await new Agents(daemon, new RequestIds()).resume('codex-cli')).toEqual({ kind: 'proposed', id: 'prp_r' });
  });
});

describe('the studio’s words', () => {
  it('counts rules per effect and says where each came from', () => {
    expect(countsByEffect(rules.rules)).toEqual({ allow: 0, ask: 1, deny: 1 });
    expect(sourceWords({ source: 'workspace' })).toBe('From your team');
    expect(sourceWords({ source: 'person', decidedBy: 'Sam' })).toBe('Set by Sam');
  });

  it('says the week in counts and how close a habit is to being let go', () => {
    expect(weekLine({ thisWeek: { from: '', asked: 12, answeredByAutopilot: 0, handedOver: 0 }, lastWeek: { from: '', asked: 1, answeredByAutopilot: 0, handedOver: 0 } })).toBe(
      'Asked you 12 times this week, 1 time last week.',
    );
    expect(almostLine({ action: 'git.push', approvals: 4, needed: 5 })).toBe('1 more yes to git.push and it is ready to let go');
    expect(exportedCount('[[policies]]\nname = "a"\n[[policies]]\n')).toBe(2);
  });
});

describe('a rule being built', () => {
  it('reads back what it will do before anything is proposed', async () => {
    const { draftSentence, switchOn } = await import('../src/core/domain/studio-lines');
    expect(draftSentence({ effect: 'ask', action: 'git.push', agents: ['codex-cli'], branches: ['main'] }, () => 'Codex')).toBe('Ask you before Codex runs git.push on the main branch.');
    expect(draftSentence({ effect: 'deny', action: '' }, (kind) => kind)).toBe('Never let any agent run this action.');
    expect(switchOn([{ effect: 'ask', match: { actions: ['git.push'], branches: ['main'] } }], 'git.push', ['main'])).toBe(true);
    expect(switchOn([{ effect: 'allow', match: { actions: ['git.push'] } }], 'git.push')).toBe(false);
  });
});

describe('packs and launching', () => {
  it('reads the packs Memnox ships and imports one as a proposal per rule', async () => {
    const pack = { id: 'careful', name: 'Careful', description: 'Asks before anything outward', ruleCount: 2, toml: '[[policies]]' };
    const daemon = new ScriptedDaemon({
      'rule-packs': (request) => [{ id: request.id, ok: true, rulePacks: [pack] }],
      'rule-pack-import': (request) => [{ id: request.id, ok: true, packProposed: ['prp_1', 'prp_2'] }],
    });
    const studio = new Studio(daemon, new RequestIds());
    await studio.readPacks();
    expect(studio.packs).toEqual([pack]);
    expect(await studio.importPack(pack.toml)).toEqual({ kind: 'done', note: '2 rules wait for your signature on the island.' });
    expect(daemon.sent('rule-pack-import')[0]?.rulePack).toBe('[[policies]]');
  });

  it('opens an agent in a folder and says what it typed', async () => {
    const daemon = new ScriptedDaemon({
      'agent-launch': (request) => [{ id: request.id, ok: true, agentLaunched: { agent: request.agentKind ?? '', workingDirectory: request.workingDirectory ?? '', line: 'claude' } }],
    });
    const agents = new Agents(daemon, new RequestIds());
    expect(await agents.launch('claude-code', ' /code/app ')).toEqual({ kind: 'done', note: 'Opened claude-code in /code/app, typing claude.' });
    expect(daemon.sent('agent-launch')[0]?.workingDirectory).toBe('/code/app');
  });
});
