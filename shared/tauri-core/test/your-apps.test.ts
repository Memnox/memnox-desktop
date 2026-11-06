import type { ToolConnection } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import {
  agentsLine,
  catalogue,
  categoriesOf,
  countLine,
  failedNote,
  FEATURED_TOOLKITS,
  inCategory,
  isSettled,
  offered,
  opensSignIn,
  reachLine,
  SIGN_IN_STOPPED,
  showingLine,
  statusLine,
  supportPill,
  tabOf,
  tabTitle,
  YourAppDisconnect,
  YourAppsLayout,
  YourAppsLines,
  yours,
  type YourAppCard,
} from '../src/core/domain/your-apps';

const github: ToolConnection = { toolkit: 'github', connected: true, local: true };
const notion: ToolConnection = { toolkit: 'notion', connected: true };
const slack: ToolConnection = { toolkit: 'slack', connected: false };

const bare = (slug: string, categories: string[]): YourAppCard => ({
  slug,
  name: slug.toUpperCase(),
  logo: undefined,
  standing: 'available',
  description: undefined,
  categories,
  kind: undefined,
  support: undefined,
  connectedSince: undefined,
  uses: [],
  source: undefined,
  weight: undefined,
});

/** The same cases as the Mac's `YourAppsTests`, so both desktops pin the same words. */
describe('your apps, as the Mac draws them', () => {
  it('says a connected app is reached through Memnox and names the agents that used it lately', () => {
    const cards = yours([{ toolkit: 'linear', connected: true, usedBy: [{ agent: 'claude-code', sessionId: 's1', at: 'x' }, { agent: 'codex', at: 'y' }] }, notion, slack]);
    const name = (agent: string) => (agent === 'claude-code' ? 'Claude Code' : 'Codex');
    expect(cards.map((each) => agentsLine(each, name))).toEqual(['Your agents can use it through Memnox. Used lately by Claude Code and Codex', 'Your agents can use it through Memnox', undefined]);
  });

  it('puts what is on this computer first and the rest by name, each tool once', () => {
    const cards = yours([slack, notion, github, notion]);
    expect(cards.map((each) => each.slug)).toEqual(['github', 'notion', 'slack']);
    expect(cards.map((each) => each.standing)).toEqual(['on-this-computer', 'connected', 'sign-in-again']);
    expect(reachLine(cards[0] as YourAppCard)).toBe('Reached from this computer itself');
  });

  it('marks the catalogue against what the person has', () => {
    const cards = catalogue([{ slug: 'notion', name: 'Notion', logo: 'https://logos.example/notion' }, { slug: 'github', name: 'GitHub' }, { slug: 'asana', name: 'Asana' }], [notion, github]);
    expect(cards.map((each) => each.standing)).toEqual(['connected', 'on-this-computer', 'available']);
    expect(cards[0]?.logo).toBe('https://logos.example/notion');
  });

  it('offers the featured tools only when the catalogue could not be read unasked', () => {
    expect(offered([], true, '', []).map((each) => each.slug)).toEqual(FEATURED_TOOLKITS);
    expect(offered([], true, 'asana', [])).toEqual([]);
  });

  it('counts the results and never estimates them', () => {
    expect(countLine(30, '')).toBe('30 apps');
    expect(countLine(1, 'notion')).toBe('1 app matches “notion”');
    expect(countLine(0, ' zz ')).toBe('No app matches “zz”');
  });

  it('says connected since the date or not connected, as the console does', () => {
    const cards = catalogue([{ slug: 'slack', name: 'Slack' }, { slug: 'asana', name: 'Asana' }], [{ toolkit: 'slack', connected: true, connectedAt: '2026-10-02T12:00:00Z' }]);
    expect(cards.map((each) => statusLine(each, false))).toEqual(['Connected since Oct 2, 2026', 'Not connected']);
    expect(statusLine(yours([notion])[0] as YourAppCard, false)).toBe('Connected');
    expect(statusLine(yours([notion])[0] as YourAppCard, true)).toBe('Finish signing in in your browser');
  });

  it('draws the cloud kind, description and support in the console words', () => {
    const found = [
      { slug: 'github', name: 'GitHub', description: '  Code hosting.  ', categories: ['Developer Tools'], kind: 'record' as const, support: 'full' as const },
      { slug: 'gmail', name: 'Gmail', kind: 'conversation' as const, support: 'partial' as const },
      { slug: 'asana', name: 'Asana' },
    ];
    const cards = catalogue(found, []);
    expect(cards.map(reachLine)).toEqual(['System of record', 'System of conversation', 'Your own account']);
    expect(cards.map(supportPill)).toEqual(['Fully supported', 'Limited support', undefined]);
    expect(cards[0]?.description).toBe('Code hosting.');
    expect(yours([github], found)[0]?.categories).toEqual(['Developer Tools']);
  });

  it('counts categories once per card, commonest first, in the console spelling', () => {
    const cards = [bare('a', ['Team Chat', 'team-chat', 'crm']), bare('b', ['team-chat']), bare('c', ['CRM', 'collaboration-&-communication'])];
    const rail = categoriesOf(cards);
    expect(rail.map((each) => each.label)).toEqual(['CRM', 'Team Chat', 'Collaboration-&-communication']);
    expect(rail.map((each) => each.count)).toEqual([2, 2, 1]);
    expect(rail.at(-1)?.id).toBe('collaboration-and-communication');
    expect(cards.filter((each) => inCategory(each, 'team-chat')).map((each) => each.slug)).toEqual(['a', 'b']);
    expect(showingLine(2, 3)).toBe('2 of 3');
  });

  it('opens on Connected for somebody with apps, Recommended otherwise, and All for a search', () => {
    expect(tabOf(undefined, '', 2)).toBe('connected');
    expect(tabOf(undefined, '', 0)).toBe('recommended');
    expect(tabOf(undefined, 'lin', 2)).toBe('all');
    expect(tabOf('recommended', 'lin', 2)).toBe('recommended');
    expect(tabTitle('connected', 3)).toBe('Connected (3)');
  });

  it('opens no sign in for an app already working unless another account is asked for', () => {
    expect(isSettled('Notion', [notion])).toBe(true);
    expect(opensSignIn('notion', false, [notion])).toBe(false);
    expect(opensSignIn('notion', true, [notion])).toBe(true);
    expect(opensSignIn('slack', false, [slack])).toBe(true);
  });

  it('says what did not work on the card, in the daemon words made one sentence', () => {
    expect(failedNote('connect', 'notion', ' Composio  said\nno')).toEqual({ toolkit: 'notion', title: 'Could not connect Notion', words: 'Composio said no.' });
    expect(failedNote('cloud-sign-in', undefined, undefined).words).toBe(SIGN_IN_STOPPED);
    expect(YourAppDisconnect.title('Slack')).toBe('Disconnect Slack?');
  });

  it('keeps the Mac page metrics and promises nothing before a sign in', () => {
    expect(YourAppsLayout).toMatchObject({ cardMinimum: 240, gridSpacing: 16, railWidth: 200, railLeading: 20 });
    expect(YourAppsLines.allowance).toContain('once you sign in to Memnox Cloud');
    expect(YourAppsLines.signInTitle).toBe('Sign in to Memnox Cloud to connect');
    const copy = [...Object.values(YourAppsLines), SIGN_IN_STOPPED, YourAppDisconnect.detail('Slack')];
    expect(copy.some((line) => /[\u2013\u2014]|\u0020-\u0020/.test(line))).toBe(false);
  });
});
