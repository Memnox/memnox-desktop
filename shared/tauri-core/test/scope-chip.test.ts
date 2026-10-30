import { describe, expect, it } from 'vitest';
import { memoryScope, PROFILE_SCOPE, projectScope, ruleScope, scopeLabel, SCOPE_WORDS, serverScope, skillScope } from '../src/core/domain/scope-lines';

describe('the scope chip', () => {
  it('names every scope with a word', () => {
    expect(SCOPE_WORDS).toEqual({ personal: 'Personal', project: 'Project', agent: 'Agent', organization: 'Organization' });
    expect(scopeLabel('agent')).toBe('Scope: Agent');
  });

  it('reads a rule as the organization’s, one agent’s, one folder’s or the person’s', () => {
    expect(ruleScope({ source: 'workspace', match: { actions: ['git.push'], agents: ['codex'] } })).toBe('organization');
    expect(ruleScope({ source: 'person', match: { actions: ['git.push'], agents: ['codex'] } })).toBe('agent');
    expect(ruleScope({ source: 'file', match: { actions: ['git.push'], workingDirectories: ['/code/app'] } })).toBe('project');
    expect(ruleScope({ source: 'person', match: { actions: ['git.push'] } })).toBe('personal');
  });

  it('reads a server given only inside repositories as a project’s', () => {
    expect(serverScope({ scope: 'organization', agents: [], projects: [] })).toBe('organization');
    expect(serverScope({ scope: 'personal', agents: [], projects: [{ agent: 'codex', project: '/code/app' }] })).toBe('project');
    expect(serverScope({ scope: 'personal', agents: ['codex'], projects: [] })).toBe('personal');
  });

  it('takes a skill’s, a memory item’s and a project’s scope as the runtime names it', () => {
    expect(skillScope({ scope: 'organization' })).toBe('organization');
    expect(memoryScope({ scope: 'project' })).toBe('project');
    expect(memoryScope({ scope: 'none' })).toBe('personal');
    expect(projectScope({ scope: 'organization' })).toBe('organization');
    expect(projectScope({})).toBe('project');
    expect(PROFILE_SCOPE).toBe('personal');
  });
});
