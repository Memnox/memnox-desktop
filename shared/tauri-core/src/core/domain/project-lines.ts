import type { PolicyRuleView, ProjectApplySummary, ProjectDraft, ProjectInstructionView, ProjectOrganizationView, ProjectView } from '@memnox/core/wire';
import { agentLabel } from './mcp-hub-lines';
import { ago } from './session-text';

/** "1 agent", "3 agents": a count, never a score. */
export function counted(count: number, one: string, many: string): string {
  return count === 1 ? `1 ${one}` : `${count} ${many}`;
}

/** The four counts the Overview leads with, rules counted only while they are in force. */
export function projectTiles(project: Pick<ProjectView, 'agents' | 'skills' | 'servers' | 'rules'>): { value: number; label: string }[] {
  const rules = project.rules.inForce ? project.rules.count : 0;
  return [
    { value: project.agents.length, label: project.agents.length === 1 ? 'Agent' : 'Agents' },
    { value: project.skills.length, label: project.skills.length === 1 ? 'Skill' : 'Skills' },
    { value: project.servers.length, label: project.servers.length === 1 ? 'MCP server' : 'MCP servers' },
    { value: rules, label: rules === 1 ? 'Active rule' : 'Active rules' },
  ];
}

/** Where a project stands, said in a word beside its tone: a manifest that will not read comes first. */
export function projectStanding(project: Pick<ProjectView, 'declared' | 'opened' | 'problems'>): { word: string; tone: 'good' | 'attention' | 'bad' | 'quiet' } {
  if (project.problems !== undefined && project.problems.length > 0) return { word: 'Manifest will not read', tone: 'bad' };
  if (!project.declared) return { word: 'Found, not saved', tone: 'quiet' };
  if (!project.opened) return { word: 'Not opened here', tone: 'attention' };
  return { word: 'Opened', tone: 'good' };
}

/** "Claude Code and Codex read it", or that no agent here reads it. */
export function readersLine(instruction: Pick<ProjectInstructionView, 'agents'>): string {
  if (instruction.agents.length === 0) return 'No agent here reads it';
  return `${listed(instruction.agents.map(agentLabel))} ${instruction.agents.length === 1 ? 'reads' : 'read'} it`;
}

/** What one instruction file is: the source the project reads, a file Memnox wrote, both, or missing. */
export function instructionWord(instruction: Pick<ProjectInstructionView, 'source' | 'present' | 'written'>): string {
  if (!instruction.present) return 'Missing';
  if (instruction.source && instruction.written) return 'Source, written by Memnox';
  if (instruction.source) return 'Source';
  return instruction.written ? 'Written by Memnox' : 'Not written yet';
}

/** "Given to 2 of 3 agents", or that the hub here lacks it, so nobody is given it. */
export function grantLine(grant: { inHub: boolean; agents: readonly string[] }, of: number): string {
  if (!grant.inHub) return 'Not in the hub on this computer, so no agent is given it';
  return `Given to ${grant.agents.length} of ${counted(of, 'agent', 'agents')}`;
}

/** The rules line under Active rules, saying why none are in force when none are. */
export function rulesLine(rules: ProjectView['rules']): string {
  if (rules.problem !== undefined) return `${rules.file ?? 'Its rule file'} will not load: ${rules.problem}`;
  if (rules.file === undefined) return 'This project names no rule file, so the rules of this computer hold.';
  if (!rules.inForce) return `${counted(rules.count, 'rule', 'rules')} in ${rules.file}, not in force until applying is signed.`;
  return `${counted(rules.count, 'rule', 'rules')} from ${rules.file}, in force.`;
}

/** "1 session, 0 ended. Never applied.", the sessions counted and when the project was last applied here. */
export function sessionsLine(project: Pick<ProjectView, 'sessions' | 'appliedAt'>, now: number): string {
  const applied = project.appliedAt === undefined ? ' Never applied.' : ` Applied ${ago(project.appliedAt, now) ?? 'a while ago'}.`;
  return `${counted(project.sessions.total, 'session', 'sessions')}, ${project.sessions.ended} ended.${applied}`;
}

/** "2 open questions" or that none waits. */
export function questionsLine(count: number): string {
  if (count === 0) return 'No open questions';
  return counted(count, 'open question', 'open questions');
}

/** What applying did at once, in a line; what it proposed waits on the island and is said apart. */
export function appliedLine(applied: ProjectApplySummary): string {
  const parts = [
    applied.written.length > 0 ? `wrote ${counted(applied.written.length, 'instruction file', 'instruction files')}` : undefined,
    applied.removed.length > 0 ? `took out ${applied.removed.length}` : undefined,
    applied.kept.length > 0 ? `left ${applied.kept.length} of yours alone` : undefined,
    applied.governed.length > 0 ? `put ${counted(applied.governed.length, 'server', 'servers')} behind the proxy` : undefined,
  ].filter((part): part is string => part !== undefined);
  const done = parts.length === 0 ? 'Every agent already had this project’s instructions.' : `${capital(parts.join(', '))}.`;
  if (applied.missing.length === 0) return done;
  return `${done} The hub here lacks ${listed(applied.missing)}, so no agent is given ${applied.missing.length === 1 ? 'it' : 'them'}.`;
}

/** "3 rules of this computer hold here too, as in every project.", as the Mac's `ProjectLines.everywhereLine` says it. */
export function everywhereLine(count: number): string {
  return count === 1 ? '1 rule of this computer holds here too, as in every project.' : `${count} rules of this computer hold here too, as in every project.`;
}

/**
 * The rules that hold in this project: those reaching into its folder, and those its own rule file brings.
 * A rule naming no folder holds everywhere and is counted apart, so the list says what this project adds.
 */
export function projectRules(rules: readonly PolicyRuleView[], project: Pick<ProjectView, 'path' | 'rules'>): { here: PolicyRuleView[]; everywhere: number } {
  const here = rules.filter((rule) => fromProjectFile(rule, project) || reachesInto(rule.match.workingDirectories, project.path));
  const everywhere = rules.filter((rule) => !here.includes(rule) && (rule.match.workingDirectories === undefined || rule.match.workingDirectories.length === 0)).length;
  return { here, everywhere };
}

function fromProjectFile(rule: PolicyRuleView, project: Pick<ProjectView, 'path' | 'rules'>): boolean {
  if (rule.file === undefined || project.rules.file === undefined) return false;
  const file = normalised(rule.file);
  return file === normalised(`${project.path}/${project.rules.file}`) || (file.startsWith(normalised(project.path)) && file.endsWith(normalised(project.rules.file)));
}

function reachesInto(folders: readonly string[] | undefined, path: string): boolean {
  if (folders === undefined) return false;
  const root = normalised(path);
  return folders.some((folder) => {
    const each = normalised(folder.replace(/\/\*+$/, ''));
    return each === root || each.startsWith(`${root}/`);
  });
}

function normalised(path: string): string {
  return path.replace(/\\/g, '/').replace(/\/+$/, '');
}

/** The project as found, made into the manifest Save as project writes: everything it shows now, named. */
export function draftOf(project: Pick<ProjectView, 'name' | 'agents' | 'servers' | 'skills' | 'instructions' | 'rules' | 'memoryScope'>): ProjectDraft {
  const instructions = project.instructions.filter((each) => each.source).map((each) => each.path);
  return {
    name: project.name,
    ...(project.agents.length === 0 ? {} : { agents: [...project.agents] }),
    ...(project.servers.length === 0 ? {} : { servers: project.servers.map((each) => each.name) }),
    ...(project.skills.length === 0 ? {} : { skills: project.skills.map((each) => each.name) }),
    ...(instructions.length === 0 ? {} : { instructions }),
    ...(project.rules.file === undefined ? {} : { policy: project.rules.file }),
    ...(project.memoryScope === '' ? {} : { memory: project.memoryScope }),
  };
}

/** The badge on a project the organization shares, which is read only here. */
export const FROM_ORGANIZATION = 'From your organization';

/** What the organization hands a shared project, or undefined for the person's own. */
export function sharedBy(project: Pick<ProjectView, 'scope' | 'organization'>): ProjectOrganizationView | undefined {
  return project.scope === 'organization' ? project.organization : undefined;
}

/** "Release rules, 4 rules", or that the organization gives this project no rule pack. */
export function organizationRulesLine(organization: Pick<ProjectOrganizationView, 'rulePack' | 'rules'>): string {
  if (organization.rulePack === undefined) return 'No rule pack from the organization.';
  return `${organization.rulePack}, ${counted(organization.rules, 'rule', 'rules')}`;
}

/** Where what its agents learn is kept, as the organization set it. */
export function organizationMemoryLine(memory: string): string {
  if (memory === 'none') return 'Its agents keep no memory from this project.';
  if (memory === 'project') return 'What its agents learn is kept under the organization’s project rather than this folder.';
  return `Memory is kept as ${memory}.`;
}

/** Said on a project card that names no repository, rather than leaving the line blank. */
export const NO_REPOSITORY = 'No repository yet';

/** What a project card shows, as the console draws one: name, repository, one line and its chips. */
export interface ProjectCardView {
  readonly name: string;
  readonly repository: string;
  readonly line: string;
  readonly chips: readonly string[];
}

/**
 * A project as one card: the organization's repository where it shares one, else the folder it lives in, a line
 * saying what it is or who worked there, and a chip for whether it keeps memory. Server and skill counts are left to
 * the project's own pages, since a project is not only code.
 */
export function projectCard(project: Pick<ProjectView, 'name' | 'path' | 'scope' | 'organization' | 'openMissions' | 'agentsSeen' | 'sessions' | 'memoryScope'>): ProjectCardView {
  const shared = sharedBy(project);
  const repository = shared?.repository.trim() || project.path.trim() || NO_REPOSITORY;
  const mission = project.openMissions[0]?.statement;
  const worked = `${counted(project.agentsSeen.length, 'agent', 'agents')} worked here over ${counted(project.sessions.total, 'session', 'sessions')}`;
  const line = shared?.description?.trim() || (mission === undefined ? worked : `Working on ${mission}`);
  const memory = project.memoryScope === '' || project.memoryScope === 'none' ? 'No memory' : 'Memory';
  return {
    name: project.name,
    repository,
    line,
    chips: [memory],
  };
}

/** Folders the sessions ran in that are not projects yet, offered as quick picks to open. */
export function foldersToOpen(seen: readonly { path: string; name: string }[], projects: readonly Pick<ProjectView, 'path'>[]): { path: string; name: string }[] {
  const known = new Set(projects.map((each) => normalised(each.path)));
  return seen.filter((each) => !known.has(normalised(each.path)));
}

function capital(line: string): string {
  return `${line.charAt(0).toUpperCase()}${line.slice(1)}`;
}

function listed(items: readonly string[]): string {
  if (items.length <= 1) return items.join('');
  return `${items.slice(0, -1).join(', ')} and ${items.at(-1) ?? ''}`;
}
