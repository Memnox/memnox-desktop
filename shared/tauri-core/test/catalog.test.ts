import type { PolicyRuleView, ProjectView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { ALL_CATEGORIES, categoryCounts, matchesSearch, searchWords, settledCategory, showingLine } from '../src/core/domain/catalog';
import { NO_REPOSITORY, projectCard } from '../src/core/domain/project-lines';
import { effectTabs, onTab, ruleCards, ruleCategory, ruleCategoryCounts, shownCards, SUGGESTED, TURN_ON } from '../src/core/domain/rule-catalog';
import { EFFECT_WORDS } from '../src/core/domain/studio-lines';

const rule = (name: string, effect: string, actions: string[], extra: Partial<PolicyRuleView> = {}): PolicyRuleView => ({
  name,
  effect: effect as PolicyRuleView['effect'],
  match: { actions },
  sentence: `${effect} ${actions.join(' ')}`,
  source: 'person',
  editable: true,
  ...extra,
});

describe('the catalogue every page shares', () => {
  it('says how much of the whole is on screen as N of M', () => {
    expect(showingLine(3, 12)).toBe('3 of 12');
  });

  it('matches every word typed in any order, and an empty search matches everything', () => {
    expect(matchesSearch(searchWords('  Main push '), 'Ask before a push to main')).toBe(true);
    expect(matchesSearch(searchWords('main delete'), 'Ask before a push to main')).toBe(false);
    expect(matchesSearch(searchWords(''), 'anything')).toBe(true);
  });

  it('counts categories in the page’s order and leaves an empty one off the rail', () => {
    const order = [
      { id: 'a', title: 'A' },
      { id: 'b', title: 'B' },
      { id: 'c', title: 'C' },
    ];
    expect(categoryCounts(['c', 'a', 'c'], (each) => each, order)).toEqual([
      { id: 'a', title: 'A', count: 1 },
      { id: 'c', title: 'C', count: 2 },
    ]);
  });

  it('falls back to all when the category chosen holds nothing on this tab', () => {
    const counts = [{ id: 'git', title: 'Git', count: 2 }];
    expect(settledCategory('git', counts)).toBe('git');
    expect(settledCategory('web', counts)).toBe(ALL_CATEGORIES);
  });
});

describe('the rules as a catalogue', () => {
  it('words the three choices Allow, Ask and Deny', () => {
    expect(Object.values(EFFECT_WORDS).map((each) => each.title)).toEqual(['Allow', 'Ask', 'Deny']);
  });

  it('places a rule by what its first action acts on', () => {
    expect(ruleCategory(['git.push'])).toBe('git');
    expect(ruleCategory(['filesystem.delete'])).toBe('files');
    expect(ruleCategory(['http.post'])).toBe('web');
    expect(ruleCategory(['mcp.*'])).toBe('tools');
    expect(ruleCategory(['shell.exec'])).toBe('commands');
    expect(ruleCategory(['*'])).toBe('everything');
    expect(ruleCategory(['deploy.prod'])).toBe('other');
  });

  it('offers a ready made rule as Suggested until a rule in force already asks about it', () => {
    const none = ruleCards([]);
    expect(none.filter((card) => card.suggested).map((card) => card.title)).toEqual(['Pushing to main', 'Deleting files', 'MCP tools that change something']);
    expect(none[0]?.effect).toBe('ask');
    expect(SUGGESTED).toBe('Suggested');
    expect(TURN_ON).toBe('Turn on');

    const asking = ruleCards([rule('mine', 'ask', ['filesystem.delete'])]);
    expect(asking.filter((card) => card.suggested).map((card) => card.title)).toEqual(['Pushing to main', 'MCP tools that change something']);
    expect(asking.at(-1)).toMatchObject({ id: 'mine', title: 'Deleting files', suggested: false, line: 'Sometimes it really is the build folder, so a person should look first.', category: 'files' });
  });

  it('counts each tab, narrows by category and search, and totals against the tab’s pool', () => {
    const cards = ruleCards([rule('push-deny', 'deny', ['git.push-force']), rule('web-ok', 'allow', ['http.get'])], []);
    expect(effectTabs(cards).map((tab) => `${tab.title} ${tab.count}`)).toEqual(['All 2', 'Allow 1', 'Ask 0', 'Deny 1']);
    const pool = onTab(cards, 'all');
    expect(ruleCategoryCounts(pool).map((each) => `${each.title} ${each.count}`)).toEqual(['Git 1', 'Web 1']);
    expect(shownCards(pool, 'git', '').map((card) => card.id)).toEqual(['push-deny']);
    expect(shownCards(pool, ALL_CATEGORIES, 'http').map((card) => card.id)).toEqual(['web-ok']);
    expect(onTab(cards, 'deny').map((card) => card.id)).toEqual(['push-deny']);
  });

  it('gathers rules that read the same into one card that keeps every rule behind it', () => {
    const cards = ruleCards([rule('a', 'deny', ['git.push-force']), rule('b', 'deny', ['git.reset-hard']), rule('c', 'ask', ['git.reset'])], []);
    expect(cards.map((card) => `${card.title} ${card.effect} ${card.rules.length}`)).toEqual(['Force-pushing and hard resets deny 2', 'Force-pushing and hard resets ask 1']);
    expect(shownCards(cards, ALL_CATEGORIES, 'reset-hard').map((card) => card.id)).toEqual(['a']);
  });

  it('leaves out a rule whose effect it cannot word rather than guessing one', () => {
    expect(ruleCards([rule('odd', 'shrug', ['git.push'])], [])).toEqual([]);
  });
});

describe('a project as a card', () => {
  const base: Parameters<typeof projectCard>[0] = {
    name: 'web',
    path: '/code/web',
    openMissions: [],
    agentsSeen: ['claude-code', 'codex-cli'],
    sessions: { total: 5 },
    servers: [{ name: 'github', inHub: true, agents: [] }],
    skills: [],
    memoryScope: 'project',
  } as unknown as Pick<ProjectView, 'name' | 'path' | 'scope' | 'organization' | 'openMissions' | 'agentsSeen' | 'sessions' | 'servers' | 'skills' | 'memoryScope'>;

  it('shows its folder, its sessions so far, and only a memory chip, never server or skill counts', () => {
    expect(projectCard(base)).toEqual({ name: 'web', repository: '/code/web', line: '5 sessions so far.', chips: ['Memory'] });
    expect(projectCard({ ...base, sessions: { total: 0, ended: 0 } }).line).toBe('No agent has worked here yet.');
  });

  it('says what it is working on, and that it keeps no memory where it keeps none', () => {
    const card = projectCard({ ...base, memoryScope: 'none', openMissions: [{ id: 'm', statement: 'the checkout', startedAt: '' }] });
    expect(card.line).toBe('the checkout');
    expect(card.chips.at(-1)).toBe('No memory');
  });

  it('shows an organization project by its repository and description, and says when there is no repository', () => {
    const shared = projectCard({
      ...base,
      scope: 'organization',
      organization: { id: 'o', name: 'web', repository: 'github.com/acme/web', description: 'The storefront', servers: [], skills: [], rules: 0, memory: 'project', skipped: [], editedIn: '' },
    });
    expect(shared).toMatchObject({ repository: 'github.com/acme/web', line: 'The storefront' });
    expect(projectCard({ ...base, path: ' ' }).repository).toBe(NO_REPOSITORY);
    expect(NO_REPOSITORY).toBe('No repository yet');
  });
});
