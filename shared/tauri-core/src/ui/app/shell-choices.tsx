import type { ProjectView } from '@memnox/core/wire';
import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { currentProject, CURRENT_PROJECT_KEY, hasOrganization, SCOPE_KEY, shownScope, type ShownScope } from '../../core/domain/shell-lines';
import { useObserved, type SettingsParts } from '../settings/parts';

/** The top bar's two choices, read by the pages they narrow: the current project and the scope shown. */
export interface ShellChoices {
  readonly projects: readonly ProjectView[] | undefined;
  /** The project picked, or undefined for all projects. */
  readonly project: ProjectView | undefined;
  chooseProject(id: string | undefined): void;
  /** Whether the runtime handed down anything of an organization, which only a Cloud connection does. */
  readonly connected: boolean;
  readonly scope: ShownScope;
  chooseScope(scope: ShownScope): void;
}

const NO_CHOICES: ShellChoices = {
  projects: undefined,
  project: undefined,
  chooseProject: () => undefined,
  connected: false,
  scope: 'personal',
  chooseScope: () => undefined,
};

const Choices = createContext<ShellChoices>(NO_CHOICES);

export function useShellChoices(): ShellChoices {
  return useContext(Choices);
}

/** A choice kept in the webview's storage, which every window of the app shares, and followed when another window changes it. */
function useKept(key: string): [string | undefined, (value: string | undefined) => void] {
  const [value, setValue] = useState(() => localStorage.getItem(key) ?? undefined);
  useEffect(() => {
    const changed = (event: StorageEvent) => {
      if (event.key === key) setValue(event.newValue ?? undefined);
    };
    window.addEventListener('storage', changed);
    return () => window.removeEventListener('storage', changed);
  }, [key]);
  const keep = (next: string | undefined) => {
    if (next === undefined) localStorage.removeItem(key);
    else localStorage.setItem(key, next);
    setValue(next);
  };
  return [value, keep];
}

/**
 * Reads the projects for the switcher and the hub, the skills and the rules for whether an organization handed
 * anything down, each only where this computer's runtime answers it. Nothing here asks for Cloud.
 */
export function ShellChoicesProvider({ parts, children }: { parts: SettingsParts; children: ReactNode }) {
  const { support, projects, hub, skills, studio } = parts;
  useObserved(support, projects, hub, skills, studio);
  const [savedProject, keepProject] = useKept(CURRENT_PROJECT_KEY);
  const [savedScope, keepScope] = useKept(SCOPE_KEY);
  const reads = { projects: support.supports('projects'), hub: support.supports('mcp-hub'), skills: support.supports('skills-hub'), rules: support.supports('rules') };
  useEffect(() => {
    if (reads.projects === true && projects.projects === undefined) void projects.refresh();
    if (reads.hub === true && hub.hub === undefined) void hub.refresh();
    if (reads.skills === true && skills.hub === undefined) void skills.refresh();
    if (reads.rules === true && studio.rules === undefined) void studio.refresh();
  }, [reads.projects, reads.hub, reads.skills, reads.rules]);
  const connected = hasOrganization({ servers: hub.hub?.servers, skills: skills.hub?.skills, rules: studio.rules?.rules });
  const choices: ShellChoices = {
    projects: projects.projects,
    project: currentProject(projects.projects, savedProject),
    chooseProject: keepProject,
    connected,
    scope: shownScope(savedScope, connected),
    chooseScope: keepScope,
  };
  return <Choices.Provider value={choices}>{children}</Choices.Provider>;
}
