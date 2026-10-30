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

/** Where a profile is applied, said before Apply: a repository, or the agent's home folder. */
export function applyWhereLine(project: string): string {
  return project.trim() === '' ? 'Skills go into the agent’s home folder.' : `Skills go into ${project.trim()}.`;
}

function counted(count: number, one: string, many: string): string {
  return count === 1 ? `1 ${one}` : `${count} ${many}`;
}
