import type { DaemonRequest, DaemonResponse } from '@memnox/core/wire';
import { createElement, type ReactNode } from 'react';
import { renderToString } from 'react-dom/server';
import { beforeAll, describe, expect, it } from 'vitest';
import { LEFT_OFF } from '../src/core/domain/destinations';
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
  const { AgentsPage } = await import('../src/ui/app/pages/AgentsPage');
  const { GovernancePage } = await import('../src/ui/app/pages/GovernancePage');
  const { HomePage } = await import('../src/ui/app/pages/HomePage');
  const { McpHubPage } = await import('../src/ui/app/pages/McpHubPage');
  const { WorkspacesPage } = await import('../src/ui/app/pages/WorkspacesPage');
  const { PageBody } = await import('../src/ui/settings/SettingsApp');
  const { OnboardingApp } = await import('../src/ui/onboarding/OnboardingApp');
  const { ProjectGone, ProjectPages } = await import('../src/ui/app/pages/ProjectPages');
  const { buildParts } = await import('../src/ui/settings/parts');
  const { DemoLink } = await import('../src/ui/adapters/demo-link');
  const fixture = (await import('../../demo/power-user.json')).default;
  const go = () => undefined;
  const width = 'wide' as const;
  const byDestination: Record<string, (parts: SettingsParts, tab: string | undefined) => ReactNode> = {
    home: (parts) => createElement(HomePage, { parts, width, go }),
    agents: (parts, tab) => createElement(AgentsPage, { parts, tab, width }),
    workspaces: (parts, tab) => createElement(WorkspacesPage, { parts, tab, width, go }),
    mcp: (parts, tab) => createElement(McpHubPage, { parts, tab, width, go }),
    governance: (parts, tab) => createElement(GovernancePage, { parts, tab, width, go }),
    // Cast is safe: every settings tab id is a settings page name.
    settings: (parts, tab) => createElement(PageBody, { page: (tab ?? 'account') as Parameters<typeof PageBody>[0]['page'], parts, go }),
  };
  pages = DESTINATIONS.flatMap((destination) => {
    const draw = byDestination[destination.id];
    if (draw === undefined) return [];
    const tabs = destination.tabs.length === 0 ? [undefined] : destination.tabs.map((tab) => tab.id);
    return tabs.map((tab) => ({ name: `${destination.id}/${tab ?? ''}`, draw: (parts: SettingsParts) => draw(parts, tab) }));
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
    for (const step of [0, 1, 2, 3, 4] as const) {
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
      // Only a tab left off the window, which no route reaches, may draw nothing once its first reads answered.
      expect(blank.filter((name) => !LEFT_OFF.includes(name))).toEqual([]);
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
    const list = renderToString(createElement('div', null, pageNamed('agents/list').draw(parts)));
    expect(list).toContain('In your workspace');
    expect(list).toContain('Answers to Ana Ruiz');
    const approvals = renderToString(createElement('div', null, pageNamed('governance/approvals').draw(parts)));
    expect(approvals).toContain('needs the numbers');
  });

  it('is not there with no account, and nothing is asked of the cloud', async () => {
    const parts = await partsOver(await demo());
    expect(renderToString(createElement('div', null, pageNamed('agents/list').draw(parts)))).not.toContain('In your workspace');
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

  it('offers a default a job, draws a job with nobody behind it grey, and a template with no activity', async () => {
    const html = renderToString(createElement('div', null, pageNamed('agents/profiles').draw(await partsOver(link))));
    expect(html).toContain('Agents with no job yet');
    expect(html).toContain('Give it a job');
    expect(html).toContain('Reviewer');
    expect(html).toContain('Start from a template');
    expect(html).toContain('Use this job');
    expect((html.match(/No agent behind it yet/g) ?? []).length).toBeGreaterThanOrEqual(2);
  });
});
