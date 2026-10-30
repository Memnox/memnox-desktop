import { describe, expect, it } from 'vitest';
import { DaemonSupport } from '../src/core/application/daemon-support';
import { RequestIds } from '../src/core/application/request-ids';
import {
  matchCommands,
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
    expect(visibleTabs('mcp', everything).map((tab) => tab.id)).toEqual(['servers', 'clients', 'secrets', 'apps']);
  });

  it('shows memory, the Skills Hub, the community index and profiles only where the runtime keeps them', () => {
    expect(visibleTabs('workspaces', nothingNew).map((tab) => tab.id)).toEqual(['projects']);
    expect(visibleTabs('workspaces', everything).map((tab) => tab.id)).toEqual(['projects', 'memory', 'skills', 'assigned', 'discover', 'profiles']);
  });

  it('shows the local network and personal sync under Settings only where the runtime answers them', () => {
    expect(visibleTabs('settings', nothingNew).map((tab) => tab.id)).not.toContain('network');
    expect(visibleTabs('settings', nothingNew).map((tab) => tab.id)).not.toContain('sync');
    expect(visibleTabs('settings', everything).map((tab) => tab.id).slice(3, 6)).toEqual(['phones', 'network', 'sync']);
  });

  it('groups Settings under who a change is about, as the console’s settings tree does', () => {
    const groups = tabGroups('settings', everything).map((group) => [group.title, group.tabs.map((tab) => tab.id)]);
    expect(groups).toEqual([
      ['Account', ['account', 'permissions', 'connection']],
      ['Devices', ['phones', 'network', 'sync']],
      ['Voice', ['voice', 'listening', 'dictation']],
      ['App', ['appearance', 'backup', 'help']],
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
    expect(settled({ destination: 'home' }, everything)).toEqual({ destination: 'home' });
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
    expect(found).toContain('Your apps');
    expect(matchCommands('servers', nothingNew)).toEqual([]);
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
});
