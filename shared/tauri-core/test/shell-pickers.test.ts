import { describe, expect, it } from 'vitest';
import {
  ALL_PROJECTS,
  currentProject,
  hasOrganization,
  inScope,
  insideProject,
  preselectedFolder,
  projectsShown,
  shortcutWords,
  shownScope,
  skillsShown,
} from '../src/core/domain/shell-lines';

const app = { id: 'p1', path: '/code/app' };
const site = { id: 'p2', path: '/code/site' };

describe('the workspace switcher', () => {
  it('starts on all projects and forgets a project that is gone', () => {
    expect(ALL_PROJECTS).toBe('All projects');
    expect(currentProject([app, site], undefined)).toBeUndefined();
    expect(currentProject([app, site], 'p2')).toBe(site);
    expect(currentProject([app], 'p2')).toBeUndefined();
    expect(currentProject(undefined, 'p1')).toBeUndefined();
  });

  it('narrows Workspaces to the project picked', () => {
    expect(projectsShown([app, site], undefined)).toEqual([app, site]);
    expect(projectsShown([app, site], site)).toEqual([site]);
  });

  it('keeps the person’s own skills and those written into the project', () => {
    const skills = [{ scope: 'personal' as const }, { scope: 'project' as const, project: '/code/app' }, { scope: 'project' as const, project: '/code/site' }];
    expect(skillsShown(skills, app)).toEqual([skills[0], skills[1]]);
    expect(skillsShown(skills, undefined)).toEqual(skills);
  });

  it('tells a folder inside a project from one that only starts alike', () => {
    expect(insideProject('/code/app', app)).toBe(true);
    expect(insideProject('/code/app/web', app)).toBe(true);
    expect(insideProject('/code/apparel', app)).toBe(false);
  });

  it('starts a launch or open form on the current project when the form offers it', () => {
    expect(preselectedFolder(['/code/site', '/code/app'], app, '/code/site')).toBe('/code/app');
    expect(preselectedFolder(['/code/site'], app, '/code/site')).toBe('/code/site');
    expect(preselectedFolder(['/code/site', '/code/app'], undefined, '/code/site')).toBe('/code/site');
  });
});

describe('the scope selector', () => {
  it('shows only once the runtime hands down something of an organization', () => {
    expect(hasOrganization({ servers: [{ scope: 'personal' }], skills: [{ scope: 'project' }], rules: [{ source: 'person' }] })).toBe(false);
    expect(hasOrganization({ servers: [{ scope: 'organization' }] })).toBe(true);
    expect(hasOrganization({ skills: [{ scope: 'organization' }] })).toBe(true);
    expect(hasOrganization({ rules: [{ source: 'workspace' }] })).toBe(true);
  });

  it('falls back to personal when nothing is connected', () => {
    expect(shownScope('organization', false)).toBe('personal');
    expect(shownScope('organization', true)).toBe('organization');
    expect(shownScope(undefined, true)).toBe('personal');
  });

  it('shows the person’s items or the organization’s, never both mixed', () => {
    const items = [{ name: 'mine', org: false }, { name: 'theirs', org: true }];
    expect(inScope(items, 'personal', (item) => item.org).map((item) => item.name)).toEqual(['mine']);
    expect(inScope(items, 'organization', (item) => item.org).map((item) => item.name)).toEqual(['theirs']);
  });
});

describe('the number keys', () => {
  it('are named as each platform presses them', () => {
    expect(shortcutWords('3', true)).toBe('⌘3');
    expect(shortcutWords('3', false)).toBe('Ctrl 3');
  });
});
