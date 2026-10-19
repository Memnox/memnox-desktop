import type { DaemonRequest, DaemonResponse } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { AppConnections, TYPING_PAUSE_MS, WATCH_INTERVAL_MS, WATCH_READS } from '../src/core/application/app-connections';
import { RequestIds } from '../src/core/application/request-ids';
import { connectionStatusWord, Tools } from '../src/core/application/tools';
import { ScriptedDaemon } from './doubles';

type Script = Partial<Record<string, (request: DaemonRequest) => DaemonResponse[]>>;

/** The use case over a scripted daemon, with a timer that fires at once and a sleep that only counts. */
function over(script: Script) {
  const daemon = new ScriptedDaemon(script);
  const ids = new RequestIds();
  const tools = new Tools(daemon, ids);
  const opened: string[] = [];
  const slept: number[] = [];
  const waits: number[] = [];
  const apps = new AppConnections(
    daemon,
    ids,
    tools,
    (url) => opened.push(url),
    async (ms) => void slept.push(ms),
    (ms, fire) => {
      waits.push(ms);
      fire();
      return () => undefined;
    },
  );
  return { daemon, tools, apps, opened, slept, waits };
}

const settled = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('app connections', () => {
  it('searches the catalogue with the words trimmed once typing pauses', async () => {
    const { daemon, apps, waits } = over({
      'toolkits-search': (request) => [{ id: request.id, ok: true, toolkits: [{ slug: 'notion', name: 'Notion' }] }],
    });
    apps.search('  notion ');
    await settled();
    expect(waits).toEqual([TYPING_PAUSE_MS]);
    expect(daemon.sent('toolkits-search')[0]?.query).toBe('notion');
    expect(apps.state.found).toEqual([{ slug: 'notion', name: 'Notion' }]);
    expect(apps.state.searching).toBe(false);
  });

  it('asks for the first page when nothing is typed', async () => {
    const { daemon, apps } = over({ 'toolkits-search': (request) => [{ id: request.id, ok: true, toolkits: [] }] });
    apps.search('');
    await settled();
    expect(daemon.sent('toolkits-search')[0]?.query).toBeUndefined();
  });

  it('says why the catalogue cannot be searched in the daemons words', async () => {
    const { apps } = over({ 'toolkits-search': (request) => [{ id: request.id, ok: false, error: 'Sign in to Memnox Cloud first' }] });
    apps.search('slack');
    await settled();
    expect(apps.state.searchNote).toBe('Sign in to Memnox Cloud first');
    expect(apps.state.found).toEqual([]);
  });

  it('leaves the page to the daemon when it opened it, and watches the list until the tool shows up', async () => {
    let reads = 0;
    const { daemon, apps, tools, opened, slept } = over({
      'connections-sign-in': (request) => [{ id: request.id, ok: true, signIn: { toolkit: 'notion', url: 'https://connect.composio.dev/x', opened: true } }],
      'voice-agents': (request) => [{ id: request.id, ok: true, voiceAgents: [] }],
      'connections-list': (request) => {
        reads += 1;
        return [{ id: request.id, ok: true, connections: reads < 3 ? [] : [{ toolkit: 'notion', connected: true }] }];
      },
    });
    await apps.connect('notion');
    expect(daemon.sent('connections-sign-in')[0]).toMatchObject({ toolkit: 'notion' });
    // A first sign in sends no again, so the daemon still refuses a tool that already works.
    expect(daemon.sent('connections-sign-in')[0]?.again).toBeUndefined();
    expect(opened).toEqual([]);
    expect(slept).toEqual([WATCH_INTERVAL_MS, WATCH_INTERVAL_MS, WATCH_INTERVAL_MS]);
    expect(tools.state.connections).toEqual([{ toolkit: 'notion', connected: true }]);
    expect(apps.state.waitingFor).toBeUndefined();
    expect(apps.state.busy).toBeUndefined();
  });

  it('opens the page itself only when the daemon could not', async () => {
    const { daemon, apps, opened } = over({
      'connections-sign-in': (request) => [{ id: request.id, ok: true, signIn: { toolkit: 'slack', url: 'https://connect.composio.dev/y', opened: false } }],
      'voice-agents': (request) => [{ id: request.id, ok: true, voiceAgents: [] }],
      'connections-list': (request) => [{ id: request.id, ok: true, connections: [{ toolkit: 'slack', connected: true }] }],
    });
    await apps.connect('slack', true);
    expect(daemon.sent('connections-sign-in')[0]?.again).toBe(true);
    expect(opened).toEqual(['https://connect.composio.dev/y']);
  });

  it('stops watching after two minutes for a sign in left unfinished', async () => {
    const { apps, slept } = over({
      'connections-sign-in': (request) => [{ id: request.id, ok: true, signIn: { toolkit: 'notion', url: 'https://connect.composio.dev/x', opened: true } }],
      'voice-agents': (request) => [{ id: request.id, ok: true, voiceAgents: [] }],
      'connections-list': (request) => [{ id: request.id, ok: true, connections: [] }],
    });
    await apps.connect('notion');
    expect(slept.length).toBe(WATCH_READS);
    expect(slept.reduce((sum, ms) => sum + ms, 0)).toBe(120_000);
    expect(apps.state.waitingFor).toBeUndefined();
  });

  it('keeps the daemons words for a tool already connected', async () => {
    const why = 'Notion is already connected. Connect it again only to use another account.';
    const { apps, slept } = over({ 'connections-sign-in': (request) => [{ id: request.id, ok: false, error: why }] });
    await apps.connect('notion');
    expect(apps.state.note).toBe(why);
    expect(slept).toEqual([]);
  });

  it('calls a daemon with no sign in older rather than started', async () => {
    const { apps } = over({ 'connections-sign-in': (request) => [{ id: request.id, ok: true }] });
    await apps.connect('notion');
    expect(apps.state.note).toBe('This Memnox is older than the app');
  });

  it('disconnects and shows the list the daemon answers with', async () => {
    const { daemon, apps, tools } = over({
      'connections-sign-out': (request) => [{ id: request.id, ok: true, connections: [{ toolkit: 'github', connected: true }] }],
    });
    await apps.disconnect('slack');
    expect(daemon.sent('connections-sign-out')[0]?.toolkit).toBe('slack');
    expect(tools.state.connections).toEqual([{ toolkit: 'github', connected: true }]);
    expect(apps.state.note).toBeUndefined();
  });

  it('says why a disconnect was refused', async () => {
    const { apps } = over({ 'connections-sign-out': (request) => [{ id: request.id, ok: false, error: 'Slack is not connected' }] });
    await apps.disconnect('slack');
    expect(apps.state.note).toBe('Slack is not connected');
  });

  it('says the daemon is not running when nothing answers', async () => {
    const { apps } = over({});
    await apps.disconnect('slack');
    expect(apps.state.note).toBe('Memnox is not running');
  });

  it('says a tool that does not work is not signed in', () => {
    expect(connectionStatusWord({ connected: false })).toBe('Not signed in');
  });
});
