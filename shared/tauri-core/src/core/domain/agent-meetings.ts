import type { AgentOverlapsView } from '@memnox/core/wire';

/**
 * Where one agent meets the others, said on its card in plain words, the Mac's `AgentMeetings`: the files it is in with
 * another agent right now, the files it holds so nobody changes them under it, and the writes it waited on.
 */
export const AGENT_MEETINGS_TITLE = 'Working alongside others';

export function meetingLines(view: AgentOverlapsView, agent: string, name: (kind: string) => string): string[] {
  const together = view.together
    .filter((each) => each.agents.includes(agent))
    .map((each) => `In ${fileOf(each.target)} with ${listed(each.agents.filter((other) => other !== agent).map(name))} right now.`);
  const holds = view.holds.filter((each) => each.agent === agent).map((each) => `Holds ${fileOf(each.path)}, so no other agent changes it.`);
  const held = view.heldBack.filter((each) => each.agent === agent).map((each) => `Waited for ${fileOf(each.what)}, which another agent had.`);
  return [...together, ...holds, ...held];
}

/** The last part of a path, which is how a person knows the file. */
export function fileOf(path: string): string {
  return path.split('/').filter((part) => part !== '').at(-1) ?? path;
}

function listed(names: readonly string[]): string {
  if (names.length === 0) return 'another agent';
  if (names.length === 1) return names[0] ?? 'another agent';
  return `${names.slice(0, -1).join(', ')} and ${names.at(-1) ?? ''}`;
}
