import type { ProfileApplied, ProfileView } from '@memnox/core/wire';

/** "2 skills · 1 server · Release rules, 4 rules", counted, never a score. */
export function profileContents(profile: Pick<ProfileView, 'skills' | 'mcpServers' | 'rulePack'>): string {
  const parts = [counted(profile.skills.length, 'skill', 'skills'), counted(profile.mcpServers.length, 'server', 'servers')];
  if (profile.rulePack !== undefined) parts.push(`${profile.rulePack.name}, ${counted(profile.rulePack.rules, 'rule', 'rules')}`);
  else parts.push('No starter rules');
  return parts.join(' · ');
}

/** What applying a profile raised, in a line: the proposals waiting on the island, what was already given, what was skipped. */
export function profileAppliedLine(applied: Pick<ProfileApplied, 'proposed' | 'already' | 'skipped'>, keyTitle: string): string {
  const count = applied.proposed.length;
  const waits = count === 0 ? '' : count === 1 ? `1 change waits for your OK with ${keyTitle} on the island.` : `${count} changes wait for your OK with ${keyTitle} on the island.`;
  const already = applied.already.length === 0 ? '' : applied.already.length === 1 ? '1 was already given.' : `${applied.already.length} were already given.`;
  const skipped = applied.skipped.length === 0 ? '' : `Skipped: ${applied.skipped.join(' ')}`;
  const said = [waits, already, skipped].filter((part) => part !== '').join(' ');
  return said === '' ? 'The profile holds nothing to give.' : said;
}

export function boundLine(profile: string): string {
  return `The agent now works under ${profile}.`;
}

export const unboundLine = 'The agent is back on its own default.';

/** What a save came to: nothing is given by keeping a profile, and an edit gives nothing new until it is applied again. */
export function profileSavedLine(name: string, editing: boolean): string {
  return editing ? `${name} is saved. What it already gave stays, and the change gives nothing until you apply it again.` : `${name} is kept. It gives nothing until you apply it.`;
}

function counted(count: number, one: string, many: string): string {
  return count === 1 ? `1 ${one}` : `${count} ${many}`;
}

/** What an agent's card says beyond its levels, as the Mac's `AgentProfileCard` says it. */
export const AgentCardLines = {
  reached: 'How Memnox reaches it',
  howSure: 'How sure Memnox is',
} as const;
