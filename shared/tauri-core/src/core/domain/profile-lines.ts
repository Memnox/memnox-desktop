import type { ProfileApplied, ProfileDraft, ProfileView, RulePackView } from '@memnox/core/wire';

/** "2 skills · 1 server · Release rules, 4 rules", counted, never a score. */
export function profileContents(profile: Pick<ProfileView, 'skills' | 'mcpServers' | 'rulePack'>): string {
  const parts = [counted(profile.skills.length, 'skill', 'skills'), counted(profile.mcpServers.length, 'server', 'servers')];
  if (profile.rulePack !== undefined) parts.push(`${profile.rulePack.name}, ${counted(profile.rulePack.rules, 'rule', 'rules')}`);
  else parts.push('No rule pack');
  return parts.join(' · ');
}

/** What applying a profile raised, in a line: the proposals waiting on the island, what was already given, what was skipped. */
export function profileAppliedLine(applied: Pick<ProfileApplied, 'proposed' | 'already' | 'skipped'>, keyTitle: string): string {
  const count = applied.proposed.length;
  const waits = count === 0 ? '' : count === 1 ? `1 proposal waits for your signature with ${keyTitle} on the island.` : `${count} proposals wait for your signature with ${keyTitle} on the island.`;
  const already = applied.already.length === 0 ? '' : applied.already.length === 1 ? '1 was already given.' : `${applied.already.length} were already given.`;
  const skipped = applied.skipped.length === 0 ? '' : `Skipped: ${applied.skipped.join(' ')}`;
  const said = [waits, already, skipped].filter((part) => part !== '').join(' ');
  return said === '' ? 'The profile holds nothing to give.' : said;
}

/** What the New profile dialog holds: the name and line as typed, and what was ticked in the hubs and packs. */
export interface ProfileForm {
  readonly name: string;
  readonly description: string;
  readonly skills: ReadonlySet<string>;
  readonly servers: ReadonlySet<string>;
  /** A pack's id from the packs the runtime offers, or empty for none. */
  readonly pack: string;
}

/** The form as the runtime takes it, or what is missing in the words the dialog shows. */
export function profileDraftFrom(form: ProfileForm, packs: readonly Pick<RulePackView, 'id' | 'name' | 'toml'>[]): ProfileDraft | string {
  const name = form.name.trim();
  if (name === '') return 'Give the profile a name.';
  const pack = packs.find((each) => each.id === form.pack);
  if (form.pack !== '' && pack === undefined) return 'That rule pack is no longer offered. Choose another.';
  if (form.skills.size === 0 && form.servers.size === 0 && pack === undefined) return 'Choose at least one skill, server or rule pack.';
  return {
    name,
    ...(form.description.trim() === '' ? {} : { description: form.description.trim() }),
    ...(form.skills.size === 0 ? {} : { skills: [...form.skills].sort() }),
    ...(form.servers.size === 0 ? {} : { mcpServers: [...form.servers].sort() }),
    ...(pack === undefined ? {} : { rulePack: { name: pack.name, toml: pack.toml } }),
  };
}

/** The form Edit opens with: the profile as kept, its pack matched by name among the packs offered now. */
export function profileFormOf(profile: Pick<ProfileView, 'name' | 'description' | 'skills' | 'mcpServers' | 'rulePack'>, packs: readonly Pick<RulePackView, 'id' | 'name'>[]): ProfileForm {
  const kept = profile.rulePack;
  const pack = kept === undefined ? undefined : packs.find((each) => each.name === kept.name);
  return { name: profile.name, description: profile.description ?? '', skills: new Set(profile.skills), servers: new Set(profile.mcpServers), pack: pack === undefined ? '' : pack.id };
}

/** The names to tick: what the hub holds now, then any the profile keeps that the hub no longer does, so each can be unticked. */
export function choiceNames(hub: readonly string[], kept: ReadonlySet<string>): string[] {
  return [...hub, ...[...kept].filter((name) => !hub.includes(name)).sort()];
}

/**
 * What saving an edit does to the pack the profile keeps, said under the picker. The runtime hands back only the
 * pack's name, so a pack is sent again from the packs offered now, and one no longer offered cannot be kept.
 */
export function packChangeLine(kept: ProfileView['rulePack'], form: Pick<ProfileForm, 'pack'>, packs: readonly Pick<RulePackView, 'id' | 'name' | 'ruleCount'>[]): string | undefined {
  if (kept === undefined) return undefined;
  const chosen = packs.find((each) => each.id === form.pack);
  const offered = packs.some((each) => each.name === kept.name);
  if (chosen === undefined) return offered ? `Saving takes ${kept.name} out of the profile.` : `${kept.name} is no longer offered here, so saving takes it out of the profile. Choose a pack to keep one.`;
  if (chosen.name !== kept.name) return `Saving replaces ${kept.name} with ${chosen.name}.`;
  if (chosen.ruleCount !== kept.rules) return `Saving takes ${kept.name} as it is offered now, ${counted(chosen.ruleCount, 'rule', 'rules')} where the profile keeps ${kept.rules}.`;
  return undefined;
}

/** What a save came to: nothing is given by keeping a profile, and an edit gives nothing new until it is applied again. */
export function profileSavedLine(name: string, editing: boolean): string {
  return editing ? `${name} is saved. What it already gave stays, and the change gives nothing until you apply it again.` : `${name} is kept. It gives nothing until you apply it.`;
}

/** Where a profile is applied, said before Apply: a repository, or the agent's home folder. */
export function applyWhereLine(project: string): string {
  return project.trim() === '' ? 'Skills go into the agent’s home folder.' : `Skills go into ${project.trim()}.`;
}

function counted(count: number, one: string, many: string): string {
  return count === 1 ? `1 ${one}` : `${count} ${many}`;
}

/** The Profiles page's own words. */
export const ProfilesLines = {
  readWhat: 'the profiles',
  create: 'New profile',
  intro: (keyTitle: string) => `A profile gives nothing until you apply it. Applying it waits for your signature with ${keyTitle} on the island, once for each piece.`,
  emptyTitle: 'No profiles yet',
  emptyBody: 'Bundle the skills, servers and rule pack one kind of work needs, such as Backend Engineering, and apply it to any agent in one go.',
  skills: (names: readonly string[]) => `Skills: ${names.join(', ')}`,
  servers: (names: readonly string[]) => `Servers: ${names.join(', ')}`,
  apply: 'Apply',
  edit: 'Edit',
  remove: 'Remove',
  removeNamed: (name: string) => `Remove ${name}`,
  cancel: 'Cancel',
  removeStays: 'What it already gave stays where it was given.',
  agent: 'Agent',
  repository: 'Repository, optional',
  repositoryPlaceholder: '/home/you/code/project',
  yourProjects: 'Your projects',
  applying: 'Applying',
  applyTo: (agent: string | undefined) => `Apply to ${agent ?? 'the agent'}`,
  editNamed: (name: string) => `Edit ${name}`,
  keep: 'Keep profile',
  saveChanges: 'Save changes',
  name: 'Name',
  namePlaceholder: 'Backend Engineering',
  nameStays: 'The name stays, since a new name would keep a second profile beside this one.',
  description: 'What it is for, optional',
  descriptionPlaceholder: 'Reviews, release notes and the local database',
  hubSkills: 'Skills from the Skills Hub',
  noSkills: 'The Skills Hub holds no skill yet.',
  hubServers: 'Servers from the MCP Hub',
  noServers: 'The MCP Hub holds no server yet.',
  rulePack: 'Rule pack',
  noRulePack: 'No rule pack',
  packOption: (name: string, rules: number) => `${name}, ${rules === 1 ? '1 rule' : `${rules} rules`}`,
} as const;
