import type { McpHubServerView, PolicyRuleView, ProjectView, SkillView } from '@memnox/core/wire';

/**
 * The top bar's two pickers, the workspace switcher and the scope selector, with the words both say. Neither
 * decides anything: the switcher narrows what the window shows to one project, and the selector shows the
 * organization's read only items beside the person's own, or either alone, once Memnox Cloud hands any down.
 */

/** Where the chosen project is remembered between openings, by its id. */
export const CURRENT_PROJECT_KEY = 'memnox.project.current';
export const ALL_PROJECTS = 'All projects';
export const SWITCHER_LABEL = 'Current project';

/** The project the person picked, or undefined for every project, also when the one remembered is gone. */
export function currentProject<P extends Pick<ProjectView, 'id'>>(projects: readonly P[] | undefined, saved: string | undefined): P | undefined {
  if (saved === undefined || saved === '' || projects === undefined) return undefined;
  return projects.find((project) => project.id === saved);
}

/** Whether a folder sits inside the project, the project's own folder included. */
export function insideProject(folder: string, project: Pick<ProjectView, 'path'>): boolean {
  const root = project.path.replace(/[\\/]+$/, '');
  if (folder === root) return true;
  return folder.startsWith(`${root}/`) || folder.startsWith(`${root}\\`);
}

/** The projects shown under Workspaces: the one picked, or all of them. */
export function projectsShown<P extends Pick<ProjectView, 'id'>>(projects: readonly P[], current: Pick<ProjectView, 'id'> | undefined): readonly P[] {
  return current === undefined ? projects : projects.filter((project) => project.id === current.id);
}

/** The skills shown for a project: the person's own everywhere, and those written into this project's folder. */
export function skillsShown<S extends Pick<SkillView, 'project' | 'scope'>>(skills: readonly S[], current: Pick<ProjectView, 'path'> | undefined): readonly S[] {
  if (current === undefined) return skills;
  return skills.filter((skill) => skill.project === undefined || insideProject(skill.project, current));
}

/** The folder a launch or open form starts on: the current project's when one is picked and offered, else the form's own first. */
export function preselectedFolder(offered: readonly string[], current: Pick<ProjectView, 'path'> | undefined, fallback: string): string {
  if (current === undefined) return fallback;
  return offered.find((folder) => folder === current.path) ?? fallback;
}

/** The folders a launch or open form offers, with the current project's first so the form starts on it. */
export function withCurrent<F extends { readonly path: string; readonly name: string }>(folders: readonly F[], current: Pick<ProjectView, 'path' | 'name'> | undefined): readonly { path: string; name: string }[] {
  if (current === undefined) return folders;
  return [{ path: current.path, name: current.name }, ...folders.filter((folder) => folder.path !== current.path)];
}

/** All shows both mixed, each with its chip; Personal is what this computer keeps; Organization is what Memnox Cloud hands down, read only here. */
export type ShownScope = 'all' | 'personal' | 'organization';

/** Where the chosen scope is remembered between openings, under a new name since All joined the choices. */
export const SCOPE_KEY = 'memnox.scope.shown';
/** Where the two choice selector remembered it, read once so an earlier choice of Organization is kept. */
export const LEGACY_SCOPE_KEY = 'memnox.scope.current';
export const SCOPE_LABEL = 'Scope';
export const SCOPE_CHOICES: readonly { readonly scope: ShownScope; readonly title: string }[] = [
  { scope: 'all', title: 'All' },
  { scope: 'personal', title: 'Personal' },
  { scope: 'organization', title: 'Organization' },
];

/**
 * The scope the two choice selector remembered, as the three choices name it: Organization stays, and Personal
 * becomes All, since Personal was where everybody started and it hid the organization's items by mistake.
 */
export function migratedScope(legacy: string | undefined): ShownScope | undefined {
  return legacy === 'organization' ? 'organization' : undefined;
}

/** The line over the organization's items, so read only is said before anybody tries an edit. */
export const ORGANIZATION_READ_ONLY = 'Your organization set these up in Memnox Cloud, so they are read only here.';
export const NO_ORGANIZATION_ITEMS = 'Your organization has not handed down anything of this kind.';

export interface OrganizationItems {
  readonly servers?: readonly Pick<McpHubServerView, 'scope'>[];
  readonly skills?: readonly Pick<SkillView, 'scope'>[];
  readonly rules?: readonly Pick<PolicyRuleView, 'source'>[];
}

/** Whether the runtime handed down anything of an organization's, which only a Cloud connection does; the selector shows only then. */
export function hasOrganization(items: OrganizationItems): boolean {
  return (
    (items.servers ?? []).some((server) => server.scope === 'organization') ||
    (items.skills ?? []).some((skill) => skill.scope === 'organization') ||
    (items.rules ?? []).some((rule) => rule.source === 'workspace')
  );
}

/** A remembered scope stands only while there is an organization to show; anything else, or nothing remembered, is All. */
export function shownScope(saved: string | undefined, connected: boolean): ShownScope {
  if (!connected) return 'all';
  return saved === 'personal' || saved === 'organization' ? saved : 'all';
}

/** The items a list shows under the chosen scope: every one under All, else told apart by whether each is the organization's. */
export function inScope<T>(items: readonly T[], scope: ShownScope, organizations: (item: T) => boolean): readonly T[] {
  if (scope === 'all') return items;
  return items.filter((item) => organizations(item) === (scope === 'organization'));
}

/** What a destination's number key says in the palette: Command and the digit on the Mac, Ctrl and the digit elsewhere. */
export function shortcutWords(key: string, mac: boolean): string {
  return mac ? `⌘${key}` : `Ctrl ${key}`;
}
