import type { McpHubServerView, MemoryItemView, PolicyRuleView, ProjectView, SkillView } from '@memnox/core/wire';

/**
 * Whose an item is, as the scope chip on every rule, server, skill, profile and memory item says it: the
 * person's own, one project's, one agent's, or the organization's once Memnox Cloud is connected. The chip is
 * grey and always carries its word, since the scope is never told by colour alone.
 */
export type ScopeKind = 'personal' | 'project' | 'agent' | 'organization';

export const SCOPE_WORDS: Record<ScopeKind, string> = {
  personal: 'Personal',
  project: 'Project',
  agent: 'Agent',
  organization: 'Organization',
};

/** What the chip says to a screen reader, where the word alone could be read as a heading. */
export function scopeLabel(kind: ScopeKind): string {
  return `Scope: ${SCOPE_WORDS[kind]}`;
}

/** A rule's scope: the organization's when the workspace published it, then one agent, then one folder, else the person's. */
export function ruleScope(rule: Pick<PolicyRuleView, 'source' | 'match'>): ScopeKind {
  if (rule.source === 'workspace') return 'organization';
  if ((rule.match.agents ?? []).length > 0) return 'agent';
  if ((rule.match.workingDirectories ?? []).length > 0) return 'project';
  return 'personal';
}

/** A server's scope: the organization's, one project's when it is given only inside repositories, else the person's. */
export function serverScope(server: Pick<McpHubServerView, 'scope' | 'agents' | 'projects'>): ScopeKind {
  if (server.scope === 'organization') return 'organization';
  const projectOnly = server.agents.length === 0 && (server.projects ?? []).length > 0;
  return projectOnly ? 'project' : 'personal';
}

export function skillScope(skill: Pick<SkillView, 'scope'>): ScopeKind {
  return skill.scope;
}

/** Memory kept nowhere is still the person's to see, so it reads as personal. */
export function memoryScope(item: Pick<MemoryItemView, 'scope'>): ScopeKind {
  return item.scope === 'project' ? 'project' : 'personal';
}

export function projectScope(project: Pick<ProjectView, 'scope'>): ScopeKind {
  return project.scope === 'organization' ? 'organization' : 'project';
}

/** A profile is a bundle the person made on this machine, so it is always theirs. */
export const PROFILE_SCOPE: ScopeKind = 'personal';
