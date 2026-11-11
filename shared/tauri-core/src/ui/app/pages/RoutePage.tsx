import type { ReactNode } from 'react';
import type { Route, WidthClass } from '../../../core/domain/destinations';
import { pageNamed } from '../../../core/domain/settings-pages';
import type { SettingsParts } from '../../settings/parts';
import { PageBody } from '../../settings/PageBody';
import { ToolsPage } from '../../settings/pages/ToolsPage';
import { YourAppsPage } from '../../settings/pages/YourAppsPage';
import { ActivityPage } from './ActivityPage';
import { AgentListTab } from './AgentListTab';
import { HandOverPage } from './HandOverPage';
import { HomePage } from './HomePage';
import { JobsTab } from './JobsTab';
import { McpHubPage } from './McpHubPage';
import { MemoryPage, MemorySourcesPage } from './MemoryPage';
import { NeedsYouPage } from './NeedsYouPage';
import { PoliciesPage } from './PoliciesPage';
import { ProjectsPage } from './ProjectsPage';
import { SessionsPage } from './SessionsPage';
import { SkillsPage } from './SkillsPage';
import { WorkTab } from './WorkTab';

/** The page a route draws, one per page of the contract, shared by the window and the test that draws every one. */
export function RoutePage({ parts, route, width, go }: { parts: SettingsParts; route: Route; width: WidthClass; go: (route: Route) => void }): ReactNode {
  switch (route.destination) {
    case 'home':
      return <HomePage parts={parts} width={width} go={go} />;
    case 'needs-you':
      return <NeedsYouPage parts={parts} />;
    case 'sessions':
      return <SessionsPage parts={parts} width={width} />;
    case 'agents':
      if (route.tab === 'this-computer') return <ToolsPage parts={parts} />;
      if (route.tab === 'jobs') return <JobsTab parts={parts} />;
      return <AgentListTab parts={parts} />;
    case 'projects':
      return <ProjectsPage parts={parts} width={width} go={go} />;
    case 'work':
      return <WorkTab parts={parts} />;
    case 'rules':
      return <PoliciesPage parts={parts} width={width} />;
    case 'hand-over':
      return <HandOverPage parts={parts} />;
    case 'activity':
      return <ActivityPage parts={parts} width={width} go={go} />;
    case 'memory':
      if (route.tab === 'skills') return <SkillsPage parts={parts} width={width} />;
      return <MemoryPage parts={parts} tab={route.tab} width={width} go={go} />;
    case 'connectors':
      if (route.tab === 'files') return <MemorySourcesPage parts={parts} />;
      if (route.tab === 'mcp') return <McpHubPage parts={parts} width={width} go={go} />;
      return <YourAppsPage parts={parts} />;
    case 'machines':
      return <PageBody page="connection" parts={parts} />;
    case 'settings': {
      const page = pageNamed(route.tab) ?? 'account';
      // The pane header above it names the page, as the console's settings pane does.
      return (
        <div className="flex w-full max-w-settings-page flex-col gap-5">
          <PageBody page={page} parts={parts} />
        </div>
      );
    }
  }
}

