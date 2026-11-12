import type { DaemonRequest, DaemonResponse } from '@memnox/core/wire';
import { createElement, type ReactNode } from 'react';
import { renderToString } from 'react-dom/server';
import { beforeAll, describe, expect, it } from 'vitest';
import type { DaemonLink } from '../src/core/application/ports/daemon-link';
import type { SettingsParts } from '../src/ui/settings/parts';

/**
 * Every page, tab and panel of the window drawn three ways: with no daemon at all, with a daemon that answers every
 * method with nothing, and with the demo world full of data. A page that throws, or one that draws nothing at all
 * where the person can do nothing, fails here rather than on somebody's screen.
 */

// The pages read a browser's storage and location as they draw; a plain object stands in for both.
const memory = new Map<string, string>();
const browser = {
  location: { search: '', href: 'http://localhost/' },
  addEventListener: () => undefined,
  removeEventListener: () => undefined,
  dispatchEvent: () => true,
  matchMedia: () => ({ matches: false, addEventListener: () => undefined, removeEventListener: () => undefined }),
  devicePixelRatio: 1,
  localStorage: { getItem: (key: string) => memory.get(key) ?? null, setItem: (key: string, value: string) => void memory.set(key, value), removeItem: (key: string) => void memory.delete(key) },
};
Object.assign(globalThis, { window: browser, location: browser.location, localStorage: browser.localStorage, document: { documentElement: { style: {}, setAttribute: () => undefined, removeAttribute: () => undefined }, visibilityState: 'visible' } });

/** No daemon: every request fails as a link to a daemon that is not running does. */
const gone: DaemonLink = {
  // eslint-disable-next-line require-yield
  async *stream() {
    throw new Error('no daemon');
  },
};

/** What each read answers on a fresh computer: every list there, and nothing in it. */
const NOTHING: Record<string, Partial<DaemonResponse>> = {
  agents: { agentsView: [] },
  profiles: { profiles: [] },
  templates: { templates: [] },
  'agent-work': { agentWork: [] },
  projects: { projects: { projects: [] } },
  'skills-hub': { skillsHub: { skills: [], found: [], agents: [] } },
  'mcp-hub': { mcpHub: { servers: [], agents: [], found: [], drifted: [], skipped: [] } },
  rules: { policyRules: { rules: [], problems: [], missing: [] } },
  'rule-packs': { rulePacks: [] },
  activity: { activity: { rows: [] } },
  'memory-learn': { memoryLearn: { items: [], more: 0 } },
  'memory-sources': { memorySources: [] },
};

/** A daemon that knows every method and holds nothing. */
const empty: DaemonLink = {
  async *stream(request: DaemonRequest): AsyncIterable<DaemonResponse> {
    if (request.method === 'subscribe') return;
    yield { id: request.id, ok: true, ...NOTHING[request.method] } as DaemonResponse;
  },
};

type Page = { name: string; draw: (parts: SettingsParts) => ReactNode };

let pages: Page[] = [];
let partsOver: (link: DaemonLink, cloud?: CloudScript) => Promise<SettingsParts>;
let pageNamed: (name: string) => Page;

/** Memnox Cloud as a signed in person's workspace answers it, by method and path. */
type CloudScript = Record<string, unknown>;
let demo: () => Promise<DaemonLink>;

beforeAll(async () => {
  const { DESTINATIONS, PROJECT_PAGE_IDS } = await import('../src/core/domain/destinations');
  const { RoutePage } = await import('../src/ui/app/pages/RoutePage');
  const { OnboardingApp } = await import('../src/ui/onboarding/OnboardingApp');
  const { ProjectGone, ProjectPages } = await import('../src/ui/app/pages/ProjectPages');
  const { buildParts } = await import('../src/ui/settings/parts');
  const { DemoLink } = await import('../src/ui/adapters/demo-link');
  const fixture = (await import('../../demo/power-user.json')).default;
  const go = () => undefined;
  const width = 'wide' as const;
  pages = DESTINATIONS.flatMap((destination) => {
    const tabs = destination.tabs.length === 0 ? [undefined] : destination.tabs.map((tab) => tab.id);
    return tabs.map((tab) => ({
      name: `${destination.id}/${tab ?? ''}`,
      draw: (parts: SettingsParts) => createElement(RoutePage, { parts, route: { destination: destination.id, ...(tab === undefined ? {} : { tab }) }, width, go }),
    }));
  });
  // Each page of the first project the daemon keeps, or the page that says it is gone when it keeps none.
  pages.push(
    ...PROJECT_PAGE_IDS.map((page) => ({
      name: `project/${page}`,
      draw: (parts: SettingsParts) => {
        const project = parts.projects.projects?.[0];
        return project === undefined ? createElement(ProjectGone, { back: go }) : createElement(ProjectPages, { parts, project, page, go });
      },
    })),
  );
  for (const stage of ['intro', 'steps', 'done'] as const) {
    for (const step of [0, 1] as const) {
      if (stage !== 'steps' && step > 0) continue;
      pages.push({ name: `onboarding/${stage}/${step}`, draw: (parts) => createElement(OnboardingApp, { parts, stage, step }) });
    }
  }
  const host = {
    platform: 'windows' as const,
    computerName: () => 'Desk',
    permissionFacts: async () => ({ platform: 'windows' as const, session: 'desktop', microphone: 'allowed' as const, typing: true, editors: { present: false, withExtension: [] } }),
    openPrivacy: async () => true,
    startsAtSignIn: async () => true,
    setStartsAtSignIn: async (on: boolean) => on,
    restart: () => undefined,
    openPage: () => undefined,
    openSettings: () => undefined,
    openOnboarding: () => undefined,
    close: () => undefined,
    applyLook: () => undefined,
    talk: () => undefined,
    copy: async () => undefined,
    onShowPage: () => () => undefined,
    voices: { choice: async () => ({ speed: 1, voices: ['system'], chosen: 'system' }), choose: async () => undefined, setSpeed: async () => undefined, installed: async () => true, install: async () => undefined, say: async () => undefined, test: async () => undefined },
  };
  const store = { load: (key: string) => memory.get(key) ?? null, save: (key: string, value: string) => void memory.set(key, value) };
  const relay = {
    pairer: { pair: () => new Promise<never>(() => undefined), servers: async () => [], forget: async () => undefined },
    cloud: { send: async () => ({ status: 404, body: '{}' }) },
    credentials: { load: async () => undefined, save: async () => undefined, delete: async () => undefined },
  };
  pageNamed = (name) => {
    const page = pages.find((each) => each.name === name);
    if (page === undefined) throw new Error(`no page ${name}`);
    return page;
  };
  partsOver = async (link, cloud) => {
    const signedIn = { token: 'tok', tokenId: 'tid', personId: 'psn_me', name: 'Sam', orgId: 'org', workspaces: ['ws_1'], deviceId: 'dev' };
    const reach =
      cloud === undefined
        ? relay
        : {
            ...relay,
            cloud: { send: async (method: string, path: string) => (cloud[`${method} ${path}`] === undefined ? { status: 404, body: '{}' } : { status: 200, body: JSON.stringify(cloud[`${method} ${path}`]) }) },
            credentials: { load: async () => signedIn, save: async () => undefined, delete: async () => undefined },
          };
    // Cast is safe: the host stands in only for what the pages call while they draw.
    const parts = buildParts(link, host as unknown as Parameters<typeof buildParts>[1], { found: async () => true, install: async () => true, wired: async () => true, run: async () => true }, { publicPoint: async () => 'P', sign: async () => 's' }, store, reach as unknown as Parameters<typeof buildParts>[5]);
    // Reads every page starts with, so the drawing sees what a page would after its first answers.
    await Promise.allSettled([
      parts.agents.refresh(),
      parts.profiles.refresh(),
      parts.profiles.readTemplates(),
      parts.work.refresh(),
      parts.workspaceAgents.refresh(),
      parts.skills.refresh(),
      parts.hub.refresh(),
      parts.studio.readPacks(),
      parts.projects.refresh(),
      parts.home.refresh(),
      parts.studio.refresh(),
      parts.memory.refreshLearn(),
      parts.memory.refreshSources(),
      ...['agents', 'profiles', 'templates', 'agent-work', 'projects', 'skills-hub', 'mcp-hub', 'rules', 'activity', 'memory-facts', 'memory-layers'].map(async (method) => parts.support.supports(method)),
    ]);
    await new Promise((resolve) => setTimeout(resolve, 10));
    return parts;
  };
  demo = async () => new DemoLink(fixture);
});

describe('every page draws', () => {
  for (const [state, link] of [
    ['with no daemon', async () => gone],
    ['with a daemon that holds nothing', async () => empty],
    ['with the demo world full of data', async () => demo()],
  ] as const) {
    it(state, async () => {
      const parts = await partsOver(await link());
      const failed: string[] = [];
      const blank: string[] = [];
      for (const page of pages) {
        try {
          const html = renderToString(createElement('div', null, page.draw(parts)));
          if (html.replace(/<[^>]*>/g, '').trim() === '') blank.push(page.name);
        } catch (error) {
          // A store read with no server snapshot is the server renderer's own limit, never the page's.
          if (!String(error).includes('getServerSnapshot')) failed.push(`${page.name}: ${String(error)}`);
        }
      }
      expect(failed).toEqual([]);
      // Needs you holds what Learn held, and the MCP servers tab what Secrets did, so both are among those drawn.
      expect(pages.map((page) => page.name)).toEqual(expect.arrayContaining(['needs-you/decide-now', 'connectors/mcp']));
      // No page of the contract may draw nothing once its first reads answered.
      expect(blank).toEqual([]);
      expect(pages.length).toBeGreaterThan(30);
    });
  }
});

describe('the workspace’s agents', () => {
  const workspace: CloudScript = {
    'GET v1/workspaces/ws_1/agent-profiles': { profiles: [{ profile: { id: 'prf_1', name: 'Content Agent', purpose: 'Drafts the campaign briefs', responsiblePersonId: 'psn_x' }, needsResponsiblePerson: false, responsiblePersonName: 'Ana Ruiz', connections: [{ machineId: 'mch_1', connection: 'gateway', label: 'openai', live: true, levels: { context: 'mediated' } }], levels: { context: 'mediated' } }] },
    'GET v1/workspaces/ws_1/me/agent-work': { work: [], handoffs: [{ id: 'hof_1', workId: 'wrk_9', fromProfileId: 'prf_1', toPersonId: 'psn_me', reason: 'needs the numbers', state: 'requested', requestedAt: 't' }] },
  };

  it('stands beside this computer’s agents and waits in Needs your attention while signed in, named by who answers', async () => {
    const parts = await partsOver(await demo(), workspace);
    const list = renderToString(createElement('div', null, pageNamed('agents/agents').draw(parts)));
    expect(list).toContain('In your workspace');
    expect(list).toContain('Answers to Ana Ruiz');
    const approvals = renderToString(createElement('div', null, pageNamed('needs-you/decide-now').draw(parts)));
    expect(approvals).toContain('needs the numbers');
  });

  it('keeps AI agents shown with no daemon while signed in, with the way to start Memnox and the workspace alone', async () => {
    const { visibleTabs, withWorkspaceAgents } = await import('../src/core/domain/destinations');
    const parts = await partsOver(gone, workspace);
    const supports = withWorkspaceAgents((method) => parts.support.supports(method), parts.workspaceAgents.signedIn);
    expect(visibleTabs('agents', supports).map((tab) => tab.id)).toContain('agents');
    const list = renderToString(createElement('div', null, pageNamed('agents/agents').draw(parts)));
    expect(list).toContain('No Memnox runtime is running on this computer');
    expect(list).toContain('Start Memnox');
    expect(list).toContain('In your workspace');
    expect(list).toContain('Content Agent');
  });

  it('is not there with no account, and nothing is asked of the cloud', async () => {
    const parts = await partsOver(await demo());
    expect(renderToString(createElement('div', null, pageNamed('agents/agents').draw(parts)))).not.toContain('In your workspace');
  });
});

describe('the Jobs tab', () => {
  const levels = { context: 'mediated', instructions: 'mediated', tools: 'enforced', activity: 'enforced', coordination: 'mediated', approval: 'enforced', enforcement: { shell: 'enforced', filesystem: 'enforced', git: 'enforced', network: 'observed', browser: 'none', mcp: 'mediated' } };
  const connection = { id: 'c1', profileId: 'agt_claude-code', kind: 'runtime_hook', agentKind: 'claude-code', agentId: 'agt_claude-code', mediation: 'interposed', firstSeen: 't', lastSeen: 't', status: 'live', levels };
  const answers: Record<string, Partial<DaemonResponse>> = {
    profiles: {
      profiles: [
        { id: 'agt_claude-code', name: 'Claude Code', skills: [], mcpServers: [], updatedAt: 't', missing: [], responsibilities: [], projects: [], isDefault: true, connections: [connection], levels },
        { id: 'reviewer', name: 'Reviewer', purpose: 'Reads a change', skills: [], mcpServers: [], updatedAt: 't', missing: [], responsibilities: [], projects: [], connections: [], levels },
      ] as unknown as DaemonResponse['profiles'],
    },
    templates: { templates: [{ id: 'testing', name: 'Testing', purpose: 'Writes and runs tests', role: 'tester', responsibilities: [], suggestedSkills: [], suggestedRules: ['Never push.'], suggestedConnections: [] }] as unknown as DaemonResponse['templates'] },
  };
  const link: DaemonLink = {
    async *stream(request: DaemonRequest): AsyncIterable<DaemonResponse> {
      if (request.method === 'subscribe') return;
      yield { id: request.id, ok: true, ...NOTHING[request.method], ...answers[request.method] } as DaemonResponse;
    },
  };

  it('keeps a default out of Jobs, as the console does, and offers it a job under Agents instead', async () => {
    const parts = await partsOver(link);
    const html = renderToString(createElement('div', null, pageNamed('agents/jobs').draw(parts)));
    expect(html).not.toContain('Agents with no job yet');
    expect(html).not.toContain('Give it a job');
    const { AgentProfileCards } = await import('../src/ui/app/pages/AgentProfileCards');
    const agents = renderToString(createElement(AgentProfileCards, { parts }));
    expect(agents).toContain('Give it a job');
  });

  it('draws a job with nobody behind it grey, and a template with no activity', async () => {
    const html = renderToString(createElement('div', null, pageNamed('agents/jobs').draw(await partsOver(link))));
    expect(html).toContain('Reviewer');
    expect(html).toContain('Start from a template');
    expect(html).toContain('Use this job');
    expect((html.match(/No agent behind it yet/g) ?? []).length).toBeGreaterThanOrEqual(2);
  });
});

describe('with the runtime away', () => {
  it('never says all clear on Home, Needs your attention, On this computer or the sidebar, and opens Connection instead', async () => {
    const { PREFERENCE } = await import('../src/core/application/preferences');
    const { RuntimeStatus } = await import('../src/ui/app/AppShell');
    memory.set(PREFERENCE.setupDone, 'true');
    const { windowOpened } = await import('../src/ui/app/runtime-standing');
    const { START_GRACE_MS } = await import('../src/core/domain/runtime-away');
    const parts = await partsOver(gone);
    await parts.tools.refresh();
    // A window newly open is still waiting on a service being set up, so it says that and shows no fault.
    const starting = renderToString(createElement('div', null, pageNamed('home/').draw(parts), createElement(RuntimeStatus, { parts, rail: false })));
    expect(starting).toContain('Starting Memnox');
    for (const fault of ['could not read', 'not answering', 'Open Connection', 'Runtime running']) expect(starting, `starting says ${fault}`).not.toContain(fault);
    // Once the wait has run out, a service still away is said to be away.
    const openedAt = windowOpened.at;
    windowOpened.at = Date.now() - START_GRACE_MS;
    const drawn = ['home/', 'needs-you/decide-now', 'agents/this-computer'].map((name) => [name, renderToString(createElement('div', null, pageNamed(name).draw(parts)))] as const);
    drawn.push(['sidebar', renderToString(createElement(RuntimeStatus, { parts, rail: false }))]);
    for (const [name, html] of drawn) {
      for (const clear of ['Nothing is waiting', 'Nothing needs you', 'No agents found', 'Runtime running']) expect(html, `${name} says ${clear}`).not.toContain(clear);
    }
    expect(drawn.find(([name]) => name === 'home/')?.[1]).toContain('Open Connection');
    expect(drawn.find(([name]) => name === 'needs-you/decide-now')?.[1]).toContain('The Memnox service is not answering');
    expect(drawn.find(([name]) => name === 'agents/this-computer')?.[1]).toContain('Open Connection');
    expect(drawn.find(([name]) => name === 'sidebar')?.[1]).toContain('Runtime not answering');
    windowOpened.at = openedAt;
    memory.delete(PREFERENCE.setupDone);
  });
});
