import { describe, expect, it } from 'vitest';
import { DaemonSupport } from '../src/core/application/daemon-support';
import { RequestIds } from '../src/core/application/request-ids';
import {
  commands,
  destinationInfo,
  keyOf,
  LANDING,
  matchCommands,
  paneHeading,
  projectRoute,
  PROJECTS_ROUTE,
  RouteHistory,
  routeForPage,
  routeFrom,
  rowTabs,
  rowTarget,
  searchOf,
  settled,
  SIDEBAR_FOOT,
  SIDEBAR_SECTIONS,
  tabGroups,
  tabOf,
  visibleTabs,
  widthClass,
  withWorkspaceAgents,
  type Destination,
  type Supports,
} from '../src/core/domain/destinations';
import { ScriptedDaemon } from './doubles';

/** Mirrors the Mac's DestinationsTests and SidebarTests, so the window lays out the same on every desktop. */

const nothingNew: Supports = () => false;
const everything: Supports = () => true;

describe('the window’s pages', () => {
  it('shows the agents list with no daemon only while the person is signed in to Memnox Cloud', () => {
    expect(visibleTabs('agents', withWorkspaceAgents(nothingNew, true)).map((tab) => tab.id)).toEqual(['agents', 'this-computer']);
    expect(visibleTabs('agents', withWorkspaceAgents(nothingNew, false)).map((tab) => tab.id)).toEqual(['this-computer']);
    expect(withWorkspaceAgents(nothingNew, true)('profiles')).toBe(false);
  });

  it('hides a tab until the daemon answers the method it reads', () => {
    expect(visibleTabs('connectors', nothingNew).map((tab) => tab.id)).toEqual(['systems']);
    // Not asked yet is not a yes, so nothing shows before the daemon answers.
    expect(visibleTabs('needs-you', () => undefined).map((tab) => tab.id)).toEqual(['decide-now']);
  });

  it('groups Settings under who a change is about, as the console’s settings tree does', () => {
    const groups = tabGroups('settings', everything).map((group) => [group.title, ...group.tabs.map((tab) => tab.id)]);
    expect(groups).toEqual([
      ['Account', 'account', 'permissions'],
      ['Devices', 'connection', 'phones'],
      ['Voice', 'voice', 'listening', 'dictation'],
      ['App', 'appearance', 'help'],
    ]);
    expect(tabGroups('memory', everything)).toEqual([]);
  });

  it('names the pane a route opens with what it is for', () => {
    expect(tabOf({ destination: 'memory', tab: 'list' })?.title).toBe('List');
    expect(tabOf({ destination: 'home' })).toBeUndefined();
  });

  it('lands on the first tab shown when the one asked for is hidden', () => {
    expect(settled({ destination: 'connectors', tab: 'mcp' }, nothingNew)).toEqual({ destination: 'connectors', tab: 'systems' });
    expect(settled({ destination: 'connectors', tab: 'mcp' }, everything)).toEqual({ destination: 'connectors', tab: 'mcp' });
    expect(settled({ destination: 'home' }, everything)).toEqual({ destination: 'home' });
    expect(settled({ destination: 'settings' }, nothingNew)).toEqual({ destination: 'settings', tab: 'account' });
  });

  it('keeps every old link working', () => {
    expect(routeFrom('?page=overview')).toEqual({ destination: 'home' });
    expect(routeFrom('?page=phones')).toEqual({ destination: 'settings', tab: 'phones' });
    expect(routeFrom('?page=tools')).toEqual({ destination: 'agents', tab: 'this-computer' });
    expect(routeFrom('?page=apps')).toEqual({ destination: 'connectors', tab: 'systems' });
    expect(routeFrom('?page=connection')).toEqual({ destination: 'settings', tab: 'connection' });
    expect(routeFrom('?dest=governance&tab=approvals')).toEqual(LANDING);
    expect(routeFrom('')).toEqual(LANDING);
    expect(routeForPage('learn')).toEqual({ destination: 'needs-you', tab: 'decide-now' });
    expect(routeForPage('today')).toEqual(LANDING);
    expect(routeForPage('needs-you')).toEqual({ destination: 'needs-you' });
  });

  it('writes a route a link can carry and reads it back', () => {
    const route = { destination: 'connectors', tab: 'mcp' } as const;
    expect(routeFrom(searchOf(route))).toEqual(route);
  });

  it('changes layout at the same widths as the Mac', () => {
    expect([1280, 1000, 760, 480].map(widthClass)).toEqual(['wide', 'medium', 'narrow', 'compact']);
  });

  it('finds a place by any word of it, titles that start with it first', () => {
    expect(matchCommands('dec', nothingNew)[0]?.title).toBe('Decide now');
    expect(matchCommands('conn', nothingNew).map((each) => each.title)).toContain('Connectors');
    expect(matchCommands('mcp', nothingNew)).toEqual([]);
    expect(matchCommands('  ', nothingNew)).toEqual(commands(nothingNew));
  });

  it('opens the first nine rows with a digit, and the palette says which one', () => {
    const rows: readonly Destination[] = ['home', 'needs-you', 'sessions', 'activity'];
    expect(rows.map(keyOf)).toEqual(['1', '2', '3', '8']);
    expect(keyOf('settings')).toBeUndefined();
    expect(commands(nothingNew).find((each) => each.title === 'Sessions')?.key).toBe('3');
  });

  it('goes back and forward through routes as a browser does', () => {
    const history = new RouteHistory({ destination: 'home' });
    history.visit({ destination: 'agents' });
    history.visit({ destination: 'agents' });
    history.visit({ destination: 'connectors', tab: 'systems' });
    history.back();
    expect(history.current).toEqual({ destination: 'agents' });
    expect(history.canGoForward).toBe(true);
    history.visit({ destination: 'settings', tab: 'voice' });
    expect(history.canGoForward).toBe(false);
    history.back();
    history.back();
    history.back();
    expect(history.current).toEqual({ destination: 'home' });
    expect(history.canGoBack).toBe(false);
  });

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
});

describe('the sidebar', () => {
  it('reads as the console’s sidebar does', () => {
    const sections = SIDEBAR_SECTIONS.map((section) => [section.title ?? '', ...section.rows.map((id) => destinationInfo(id).title)]);
    expect(sections).toEqual([
      ['', 'Home', 'Needs you', 'Sessions', 'Agents', 'Projects'],
      ['Govern', 'Rules', 'Hand over', 'Activity'],
      ['Knowledge', 'Memory', 'Connectors'],
    ]);
    expect(SIDEBAR_FOOT.map((id) => destinationInfo(id).title)).toEqual(['Settings']);
  });

  it('opens Needs you on Decide now whatever the runtime answers', () => {
    expect(rowTarget('needs-you', nothingNew)).toEqual({ destination: 'needs-you', tab: 'decide-now' });
    expect(rowTabs({ destination: 'needs-you', tab: 'decide-now' }, nothingNew)).toEqual([]);
  });

  it('leaves a row out until the daemon answers one of its pages', () => {
    expect(rowTarget('rules', nothingNew)).toBeUndefined();
    expect(rowTarget('rules', everything)).toMatchObject({ destination: 'rules' });
  });

  it('gathers memory and its skills as one row that opens on the map', () => {
    expect(rowTarget('memory', everything)).toEqual({ destination: 'memory', tab: 'map' });
    expect(rowTabs({ destination: 'memory', tab: 'list' }, everything).map((tab) => tab.title)).toEqual(['Map', 'List', 'Layers', 'Skills']);
  });

  it('keeps Settings as a tree rather than a strip', () => {
    expect(rowTabs({ destination: 'settings', tab: 'voice' }, everything)).toEqual([]);
  });

  it('carries an open project through a link, history and settling', () => {
    const open = projectRoute('p1', 'memory');
    expect(routeFrom(searchOf(open))).toEqual(open);
    expect(settled(open, everything)).toEqual(open);
    expect(routeFrom('?dest=projects&project=p1&part=tools')).toEqual(projectRoute('p1'));
    expect(PROJECTS_ROUTE).toEqual({ destination: 'projects' });
  });

  it('heads a page with its tab’s title, Settings with its tree, and Home with nothing', () => {
    expect(paneHeading({ destination: 'memory', tab: 'map' })).toEqual({ kind: 'page', title: 'Map', subtitle: 'Your agents and everything they reach, drawn as one map of what they know and use.' });
    expect(paneHeading({ destination: 'settings', tab: 'voice' })).toEqual({ kind: 'sub-nav', title: 'Settings' });
    expect(paneHeading({ destination: 'sessions' })).toEqual({ kind: 'page', title: 'Sessions', subtitle: expect.stringContaining('Every session') });
    expect(paneHeading({ destination: 'home' })).toEqual({ kind: 'none' });
  });
});
