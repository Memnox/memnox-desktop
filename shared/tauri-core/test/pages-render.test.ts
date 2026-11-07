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
let partsOver: (link: DaemonLink) => Promise<SettingsParts>;
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
  partsOver = async (link) => {
    // Cast is safe: the host stands in only for what the pages call while they draw.
    const parts = buildParts(link, host as unknown as Parameters<typeof buildParts>[1], { found: async () => true, install: async () => true, wired: async () => true, run: async () => true }, { publicPoint: async () => 'P', sign: async () => 's' }, store, relay as unknown as Parameters<typeof buildParts>[5]);
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
