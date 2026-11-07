import { describe, expect, it } from 'vitest';
import { DaemonSupport } from '../src/core/application/daemon-support';
import { RequestIds } from '../src/core/application/request-ids';
import {
  LEFT_OFF,
  commands,
  LANDING,
  matchCommands,
  projectRoute,
  PROJECTS_ROUTE,
  pageSymbol,
  paneHeading,
  rowOf,
  rowTabs,
  shownPages,
  shownRows,
  SIDEBAR_ROWS,
  SIDEBAR_SECTIONS,
  SIDEBAR_TOP,
  RouteHistory,
  routeForPage,
  routeFrom,
  searchOf,
  settled,
  tabGroups,
  tabOf,
  visibleTabs,
  widthClass,
  type Supports,
} from '../src/core/domain/destinations';
import { ScriptedDaemon } from './doubles';

const nothingNew: Supports = () => false;
const everything: Supports = () => true;

describe('the window’s destinations', () => {
  it('hides a tab until the daemon answers the method it reads', () => {
    expect(visibleTabs('mcp', nothingNew).map((tab) => tab.id)).toEqual(['apps']);
    expect(visibleTabs('mcp', everything).map((tab) => tab.id)).toEqual(['servers', 'apps']);
  });

  it('shows memory and the Skills Hub only where the runtime keeps them, and never profiles, which Memnox Cloud keeps', () => {
    expect(visibleTabs('workspaces', nothingNew).map((tab) => tab.id)).toEqual(['projects']);
    expect(visibleTabs('workspaces', everything).map((tab) => tab.id)).toEqual(['projects', 'map', 'memory', 'layers', 'sources', 'skills']);
  });

  it('leaves the local network and personal sync off Settings for now, even where the runtime answers them', () => {
    expect(visibleTabs('settings', nothingNew).map((tab) => tab.id)).not.toContain('network');
    expect(visibleTabs('settings', everything).map((tab) => tab.id)).not.toContain('sync');
    expect(settled({ destination: 'settings', tab: 'sync' }, everything)).toEqual({ destination: 'settings', tab: 'account' });
  });

  it('leaves Learn, Clients, Secrets, Assigned and Sessions off for now, an old link settling on the first tab shown', () => {
    expect(LEFT_OFF).toEqual(['governance/learn', 'mcp/clients', 'mcp/secrets', 'workspaces/assigned', 'agents/sessions', 'settings/sync']);
    expect(settled({ destination: 'governance', tab: 'learn' }, everything)).toEqual({ destination: 'governance', tab: 'approvals' });
    expect(settled({ destination: 'mcp', tab: 'secrets' }, everything)).toEqual({ destination: 'mcp', tab: 'servers' });
    expect(settled({ destination: 'workspaces', tab: 'assigned' }, everything)).toEqual({ destination: 'workspaces', tab: 'projects' });
    expect(settled({ destination: 'agents', tab: 'sessions' }, everything)).toEqual({ destination: 'agents', tab: 'list' });
  });

  it('groups Settings under who a change is about, as the console’s settings tree does', () => {
    const groups = tabGroups('settings', everything).map((group) => [group.title, group.tabs.map((tab) => tab.id)]);
    expect(groups).toEqual([
      ['Account', ['account', 'permissions', 'connection']],
      ['Devices', ['phones']],
      ['Voice', ['voice', 'listening', 'dictation']],
      ['App', ['appearance', 'help']],
    ]);
  });

  it('drops a heading whose every tab is hidden, so no group stands over nothing', () => {
    expect(tabGroups('mcp', nothingNew).map((group) => group.title)).toEqual(['Apps']);
    expect(tabGroups('mcp', everything).map((group) => group.title)).toEqual(['Hub', 'Apps']);
    expect(tabGroups('home', everything)).toEqual([]);
  });

  it('names the pane a route opens with its heading and what it is for', () => {
    expect(tabOf({ destination: 'workspaces', tab: 'memory' })).toMatchObject({ group: 'Knowledge', tab: { title: 'Memory' } });
    expect(tabOf({ destination: 'settings', tab: 'voice' })?.tab.summary).toBe('Who thinks for the voice, and the voice it answers in.');
    expect(tabOf({ destination: 'home' })).toBeUndefined();
  });

  it('lands on the first tab shown when the one asked for is hidden', () => {
    expect(settled({ destination: 'mcp', tab: 'servers' }, nothingNew)).toEqual({ destination: 'mcp', tab: 'apps' });
    expect(settled({ destination: 'mcp', tab: 'servers' }, everything)).toEqual({ destination: 'mcp', tab: 'servers' });
    expect(settled({ destination: 'home' }, everything)).toEqual({ destination: 'home' });
  });

  it('opens on Home and sends an old Today link there', () => {
    expect(LANDING).toEqual({ destination: 'home' });
    expect(settled({ destination: 'today' }, everything)).toEqual({ destination: 'home' });
    expect(settled(routeFrom('?dest=today'), everything)).toEqual({ destination: 'home' });
    expect(commands(everything).some((each) => each.route.destination === 'today')).toBe(false);
  });

  it('keeps every old settings link working', () => {
    expect(routeFrom('?page=overview')).toEqual({ destination: 'home' });
    expect(routeFrom('?page=phones')).toEqual({ destination: 'settings', tab: 'phones' });
    expect(routeFrom('?page=tools')).toEqual({ destination: 'agents', tab: 'computer' });
    expect(routeFrom('?page=apps')).toEqual({ destination: 'mcp', tab: 'apps' });
    expect(routeFrom('')).toEqual({ destination: 'home' });
    expect(routeForPage('voice')).toEqual({ destination: 'settings', tab: 'voice' });
    expect(routeForPage('governance')).toEqual({ destination: 'governance' });
  });

  it('writes a route a link can carry and reads it back', () => {
    const route = { destination: 'governance' as const, tab: 'approvals' };
    expect(routeFrom(searchOf(route))).toEqual(route);
  });

  it('changes layout at the same widths as the Mac', () => {
    expect([1280, 1000, 760, 480].map(widthClass)).toEqual(['wide', 'medium', 'narrow', 'compact']);
  });

  it('finds a place by any word of it, titles that start with it first', () => {
    const found = matchCommands('app', nothingNew).map((each) => each.title);
    expect(found[0]).toBe('Approvals');
    expect(matchCommands('conn', nothingNew).map((each) => each.title)).toContain('Connectors');
    expect(matchCommands('servers', nothingNew)).toEqual([]);
    expect(matchCommands('servers', everything).map((each) => each.title)).toEqual(['Servers']);
  });

  it('goes back and forward through routes as a browser does', () => {
    const history = new RouteHistory({ destination: 'home' });
    history.visit({ destination: 'agents' });
    history.visit({ destination: 'agents' });
    history.visit({ destination: 'mcp', tab: 'apps' });
    history.back();
    expect(history.current).toEqual({ destination: 'agents' });
    history.visit({ destination: 'settings', tab: 'voice' });
    expect(history.canGoForward).toBe(false);
  });
});

describe('what the daemon answers', () => {
  it('asks once per method and remembers a refusal as not supported', async () => {
    const daemon = new ScriptedDaemon({ 'mcp-hub': (request) => [{ id: request.id, ok: true }] });
    const support = new DaemonSupport(daemon, new RequestIds());
    expect(support.supports('mcp-hub')).toBeUndefined();
    expect(support.supports('rules')).toBeUndefined();
    support.supports('mcp-hub');
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(support.supports('mcp-hub')).toBe(true);
    expect(support.supports('rules')).toBe(false);
    expect(daemon.sent('mcp-hub')).toHaveLength(1);
  });

  it('lays the sidebar out as the console does: Home, Projects, Needs your attention and Activity, then Your AI and Connected tools', () => {
    expect(SIDEBAR_TOP.map((row) => row.title)).toEqual(['Home', 'Projects', 'Needs your attention', 'Activity']);
    const sections = SIDEBAR_SECTIONS.map((section) => [section.title, shownRows(section, everything).map((row) => row.title)]);
    expect(sections).toEqual([
      ['Your AI', ['AI agents', 'Protection settings', 'Memory', 'Skills', 'MCP servers']],
      ['Connected tools', ['Connectors', 'Files']],
    ]);
  });

  it('keeps a row off the sidebar until the runtime answers a page behind it', () => {
    const shown = SIDEBAR_SECTIONS.map((section) => shownRows(section, nothingNew).map((row) => row.title));
    expect(shown).toEqual([['AI agents'], ['Connectors']]);
    expect(SIDEBAR_TOP.map((row) => shownPages(row, nothingNew).map((page) => page.title))).toEqual([['Home'], ['Projects'], ['Approvals'], []]);
  });

  it('gives Activity, Skills and MCP servers rows of their own and leaves Discover off for now', () => {
    expect(rowOf({ destination: 'governance', tab: 'activity' })?.title).toBe('Activity');
    expect(rowOf({ destination: 'mcp', tab: 'servers' })?.title).toBe('MCP servers');
    // Servers and My Skills stand alone now that Clients, Secrets and Assigned are left off, so neither row shows tabs.
    expect(rowTabs({ destination: 'mcp', tab: 'servers' }, everything)).toEqual([]);
    expect(rowTabs({ destination: 'workspaces', tab: 'skills' }, everything)).toEqual([]);
    expect(visibleTabs('workspaces', everything).map((tab) => tab.id)).not.toContain('discover');
    expect(rowTabs({ destination: 'mcp', tab: 'apps' }, everything)).toEqual([]);
    expect(rowOf({ destination: 'workspaces', tab: 'sources' })?.title).toBe('Files');
    expect(rowOf({ destination: 'workspaces', tab: 'memory' })?.title).toBe('Memory');
  });

  it('makes the map, the list and the layers one Memory row that opens on the map, as the Mac does', () => {
    const memory = SIDEBAR_ROWS.find((row) => row.title === 'Memory');
    expect(memory === undefined ? undefined : shownPages(memory, everything)[0]?.route).toEqual({ destination: 'workspaces', tab: 'map' });
    expect(rowTabs({ destination: 'workspaces', tab: 'memory' }, everything).map((page) => page.title)).toEqual(['Map', 'List', 'Layers']);
    expect(rowOf({ destination: 'workspaces', tab: 'layers' })?.title).toBe('Memory');
    // Without the layers the strip still offers the map and the list.
    const noLayers: Supports = (method) => method !== 'memory-layers';
    expect(rowTabs({ destination: 'workspaces', tab: 'map' }, noLayers).map((page) => page.title)).toEqual(['Map', 'List']);
    expect(settled({ destination: 'workspaces', tab: 'map' }, everything)).toEqual({ destination: 'workspaces', tab: 'map' });
  });

  it('carries an open project through a link, history and settling, and only on the projects tab', () => {
    const open = projectRoute('p1', 'memory');
    expect(routeFrom(searchOf(open))).toEqual(open);
    expect(routeFrom('?dest=workspaces&tab=projects&project=p1&part=tools')).toEqual(projectRoute('p1'));
    expect(routeFrom('?dest=workspaces&tab=projects&project=p1&part=nonsense')).toEqual(projectRoute('p1'));
    expect(settled(open, everything)).toEqual(open);
    expect(settled({ ...PROJECTS_ROUTE, tab: 'skills', project: { id: 'p1', page: 'tools' } }, everything)).toEqual({ destination: 'workspaces', tab: 'skills' });
    const history = new RouteHistory(PROJECTS_ROUTE);
    history.visit(projectRoute('p1'));
    history.visit(projectRoute('p1', 'agents'));
    history.back();
    expect(history.current).toEqual(projectRoute('p1'));
  });

  it('lights the row a page sits behind and shows the row’s other pages as tabs', () => {
    expect(rowOf({ destination: 'home' })?.title).toBe('Home');
    expect(rowTabs({ destination: 'home' }, everything)).toEqual([]);
    expect(rowOf({ destination: 'workspaces', tab: 'skills' })?.title).toBe('Skills');
    expect(rowTabs({ destination: 'agents', tab: 'list' }, everything).map((page) => page.title)).toEqual(['Agents', 'Jobs', 'Work', 'On this computer']);
    // A row with one page shows no tabs, and a row whose other pages the runtime does not answer shows none either.
    expect(rowTabs({ destination: 'governance', tab: 'policies' }, everything)).toEqual([]);
    expect(rowTabs({ destination: 'governance', tab: 'approvals' }, nothingNew)).toEqual([]);
  });

  it('calls projects Projects, never Workspaces or Shared projects', () => {
    expect(shownPages(SIDEBAR_TOP[1] ?? { title: '', symbol: 'folder', pages: [] }, everything).map((page) => page.title)).toEqual(['Projects']);
  });

  it('gives each page the Mac’s icon, falling back to its destination’s', () => {
    expect(pageSymbol({ destination: 'workspaces', tab: 'memory' })).toBe('brain');
    expect(pageSymbol({ destination: 'governance', tab: 'approvals' })).toBe('checkmark.shield');
    expect(pageSymbol({ destination: 'today' })).toBe('sun.max');
  });

  it('heads a page with its own title, Settings with its tree, and Home and Today with nothing', () => {
    expect(paneHeading({ destination: 'workspaces', tab: 'memory' }, everything)).toEqual({ kind: 'page', title: 'Memory', subtitle: expect.stringContaining('What your agents know') });
    expect(paneHeading({ destination: 'workspaces', tab: 'map' }, everything)).toEqual({ kind: 'page', title: 'Memory', subtitle: 'Your agents and everything they reach, drawn as one map of what they know and use.' });
    expect(paneHeading({ destination: 'governance', tab: 'activity' }, everything)).toEqual({ kind: 'page', title: 'Activity', subtitle: expect.stringContaining('What your agents did') });
    expect(paneHeading({ destination: 'governance', tab: 'policies' }, everything)).toEqual({ kind: 'page', title: 'Protection settings', subtitle: 'For each thing your AI might do, choose Allow, Ask or Deny. Nothing changes until you save and the change is approved.' });
    expect(paneHeading({ destination: 'settings', tab: 'voice' }, everything)).toEqual({ kind: 'sub-nav', title: 'Settings' });
    expect(paneHeading({ destination: 'today' }, everything)).toEqual({ kind: 'none' });
    expect(paneHeading({ destination: 'home' }, everything)).toEqual({ kind: 'none' });
  });
});
