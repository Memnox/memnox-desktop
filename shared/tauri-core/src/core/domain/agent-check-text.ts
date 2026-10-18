import type { VoiceAgentStatus } from '@memnox/core/wire';

/**
 * How setup words one agent's check on its row, ported from the Mac's `AgentCheckText`. The daemon's reason
 * is written to be spoken whole with the agent's own reply inside it, so the row says it shorter and quotes
 * the reply on a line of its own.
 */
export const AgentCheckText = {
  /** The line under the agent's name. */
  status(agent: VoiceAgentStatus, checking: boolean): string {
    if (agent.works === undefined) return checking ? 'Asking it one question' : 'Not asked yet';
    if (agent.works) {
      if (!agent.chosen) return 'Ready to answer';
      return agent.sealed ? 'Answers when you talk, kept to reading' : 'Answers when you talk, and can run shell commands';
    }
    if (AgentCheckText.reply(agent) !== undefined) return 'Its own account answered in place of Memnox';
    return sentence(agent.because) ?? 'Did not answer';
  },

  /** The agent's own words worth quoting, such as a plan asking to be upgraded. */
  reply(agent: VoiceAgentStatus): string | undefined {
    if (agent.works !== false) return undefined;
    const words = agent.reply?.trim() ?? '';
    return words === '' ? undefined : words;
  },

  /** Asked and could not answer, which is what sets a row apart from the ones that can. */
  notReady(agent: VoiceAgentStatus): boolean {
    return agent.installed && agent.works === false;
  },

  /** Names read as a sentence says them: one alone, two joined by and, more with commas before the and. */
  names(labels: readonly string[]): string {
    if (labels.length <= 1) return labels[0] ?? '';
    return `${labels.slice(0, -1).join(', ')} and ${labels[labels.length - 1]}`;
  },
};

/** Starts with a capital, since the daemon writes its reasons to follow a name in a spoken sentence. */
export function sentence(text: string | undefined): string | undefined {
  const trimmed = text?.trim() ?? '';
  return trimmed === '' ? undefined : trimmed.charAt(0).toUpperCase() + trimmed.slice(1);
}
