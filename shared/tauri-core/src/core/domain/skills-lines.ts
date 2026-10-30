import type { SkillCompatibility, SkillDraft, SkillHold, SkillView, SkillsSyncSummary } from '@memnox/core/wire';

const DAY_MS = 86_400_000;

/** "3 agents assigned", or that none is yet. A count, never a score. */
export function assignedLine(count: number): string {
  if (count === 0) return 'No agents assigned';
  return count === 1 ? '1 agent assigned' : `${count} agents assigned`;
}

/** "Updated 4 days ago", counted in whole days so the card does not change by the minute. */
export function updatedLine(updatedAt: string, now: number): string {
  const at = Date.parse(updatedAt);
  if (Number.isNaN(at)) return 'Updated at some point';
  const days = Math.max(0, Math.floor((now - at) / DAY_MS));
  if (days === 0) return 'Updated today';
  if (days === 1) return 'Updated yesterday';
  return `Updated ${days} days ago`;
}

/** "Testing · v1.2.0", or the version alone where no category was given. */
export function categoryVersion(skill: Pick<SkillView, 'category' | 'version'>): string {
  const version = `v${skill.version}`;
  return skill.category === undefined || skill.category === '' ? version : `${skill.category} · ${version}`;
}

/** Why a skill is held, in a sentence, and what accepting it does. */
export function heldLine(hold: SkillHold): string {
  const reach = hold.gained.length === 0 ? '' : ` It now reaches ${listed(hold.gained)}.`;
  const sign = hold.signed ? ' Accepting it waits for your signature on the island.' : ' Accepting it happens at once.';
  if (hold.standing === 'new') return `Nobody has accepted this folder yet, so no agent is given it.${reach}${sign}`;
  if (hold.standing === 'widened') return `Its folder reaches further than the version you accepted, so nothing new of it is handed out.${reach}${sign}`;
  return `Its folder changed since you accepted it, so nothing new of it is handed out.${reach}${sign}`;
}

/** What one agent keeps of a skill once written in its format. */
export function compatibilityLine(compatibility: Pick<SkillCompatibility, 'supported' | 'loses'>): string {
  if (!compatibility.supported) return 'Cannot take skills';
  if (compatibility.loses.length === 0) return 'Keeps everything';
  return compatibility.loses.length === 1 ? 'Loses 1 thing in conversion' : `Loses ${compatibility.loses.length} things in conversion`;
}

/** "Wrote 3, removed 1, skipped 2." or that every agent already had what the hub gives it. */
export function skillsSyncedLine(synced: Pick<SkillsSyncSummary, 'written' | 'removed' | 'skipped'>): string {
  const parts = [
    synced.written > 0 ? `wrote ${synced.written}` : undefined,
    synced.removed > 0 ? `removed ${synced.removed}` : undefined,
    synced.skipped.length > 0 ? `skipped ${synced.skipped.length}` : undefined,
  ].filter((part): part is string => part !== undefined);
  if (parts.length === 0) return 'Every agent already has the skills the hub gives it.';
  const line = parts.join(', ');
  return `${line.charAt(0).toUpperCase()}${line.slice(1)}.`;
}

/** The agents to give a skill to and to take it from, so Continue sends only what changed. */
export function assignmentChanges(current: readonly string[], chosen: ReadonlySet<string>): { give: string[]; take: string[] } {
  const had = new Set(current);
  return {
    give: [...chosen].filter((agent) => !had.has(agent)).sort(),
    take: current.filter((agent) => !chosen.has(agent)),
  };
}

/** What a Continue that gave and took said in one line, the gives waiting on the island. */
export function assignedNote(results: { proposed: number; done: number; failed: string[] }, keyTitle: string): string {
  if (results.failed.length > 0) return results.failed[0] ?? 'The runtime refused this.';
  const waits = results.proposed === 0 ? '' : results.proposed === 1 ? `1 agent waits for your signature with ${keyTitle} on the island.` : `${results.proposed} agents wait for your signature with ${keyTitle} on the island.`;
  const now = results.done === 0 ? '' : results.done === 1 ? '1 change made at once.' : `${results.done} changes made at once.`;
  const said = [waits, now].filter((part) => part !== '').join(' ');
  return said === '' ? 'Nothing changed.' : said;
}

/** Every loss across the agents chosen, said before Continue, so nobody learns of it afterwards. */
export function conversionLosses(compatibility: readonly SkillCompatibility[], chosen: ReadonlySet<string>): { label: string; loses: string[] }[] {
  return compatibility.filter((each) => chosen.has(each.agent) && each.loses.length > 0).map((each) => ({ label: each.label, loses: each.loses }));
}

/** What a skill asks to reach, a line per kind that has anything. */
export function permissionLines(skill: Pick<SkillView, 'tools' | 'mcpServers' | 'permissions'>): { title: string; items: string[] }[] {
  const all = [
    { title: 'Agent tools', items: skill.tools },
    { title: 'MCP servers', items: skill.mcpServers },
    { title: 'Commands', items: skill.permissions.commands },
    { title: 'Files outside its folder', items: skill.permissions.filesystem },
    { title: 'Hosts', items: skill.permissions.network },
  ];
  return all.filter((each) => each.items.length > 0);
}

/** A word a person typed made into a name every agent folder takes. */
export function skillNameFrom(typed: string): string {
  return typed
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 64);
}

/** A comma or line separated field as a list, blanks dropped. */
export function listFrom(typed: string): string[] {
  return typed
    .split(/[,\n]/)
    .map((each) => each.trim())
    .filter((each) => each !== '');
}

/** What the New skill form holds, every list as typed. */
export interface SkillForm {
  readonly name: string;
  readonly version: string;
  readonly description: string;
  readonly category: string;
  readonly instructions: string;
  readonly tools: string;
  readonly commands: string;
}

/** The form as the runtime takes it, or what is missing in the words the form shows. */
export function draftFrom(form: SkillForm): SkillDraft | string {
  const name = skillNameFrom(form.name);
  if (name === '') return 'Give the skill a name.';
  if (form.description.trim() === '') return 'Say in a line what the skill is for.';
  if (form.instructions.trim() === '') return 'Write the instructions the agent follows.';
  const version = form.version.trim() === '' ? '1.0.0' : form.version.trim();
  const tools = listFrom(form.tools);
  const commands = listFrom(form.commands);
  return {
    name,
    version,
    description: form.description.trim(),
    instructions: form.instructions,
    ...(form.category.trim() === '' ? {} : { category: form.category.trim() }),
    ...(tools.length === 0 ? {} : { tools }),
    ...(commands.length === 0 ? {} : { permissions: { commands } }),
  };
}

function listed(items: readonly string[]): string {
  if (items.length <= 1) return items.join('');
  return `${items.slice(0, -1).join(', ')} and ${items.at(-1) ?? ''}`;
}
