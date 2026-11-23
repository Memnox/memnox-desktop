import type { PolicyRuleView, RulePackView } from '@memnox/core/wire';

/**
 * Starting one agent on a shipped rule pack, as the Mac's `AgentPresets`. The runtime names each rule it starts for an
 * agent after it, which is how the pack it started on is read back.
 */
export const AgentPresetLines = {
  title: 'Start it on',
  waits: 'Each rule waits for your signature on the island.',
  line: (started: Pick<RulePackView, 'name'> | undefined) => (started === undefined ? 'Follows your general rules.' : `Started on ${started.name}.`),
} as const;

/** The pack this agent was started on, or undefined where none was; the last one in the list wins. */
export function startedPack<Pack extends Pick<RulePackView, 'id'>>(rules: readonly Pick<PolicyRuleView, 'name'>[], agent: string, packs: readonly Pack[]): Pack | undefined {
  const mine = rules.map((rule) => rule.name).filter((name) => name.endsWith(`-for-${agent}`));
  return [...packs].reverse().find((pack) => mine.some((name) => name.startsWith(`pack-${pack.id}-`)));
}
