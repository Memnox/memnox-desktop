import { agentKind } from './agent-colour';

/**
 * Which shipped logo an agent wears, by its kind, ported from the Mac's `AgentLogo.files`: Codex wears
 * OpenAI's, and Claude Desktop shares Claude Code's. A kind with none is drawn as its initial.
 */
const FILES: Record<string, string> = {
  'claude-code': 'claude',
  'claude-desktop': 'claude',
  claude: 'claude',
  cursor: 'cursor',
  codex: 'openai',
  'codex-cli': 'openai',
  hermes: 'hermes',
  openclaw: 'openclaw',
  cline: 'cline',
  antigravity: 'antigravity',
  'copilot-cli': 'copilot',
  opencode: 'opencode',
};

/** The logo's name without its extension, or undefined where the agent has none of its own. */
export function agentLogo(agent: string | undefined): string | undefined {
  return FILES[agentKind(agent)];
}

/** The letter that stands in for a logo: the first of the name the person reads, uppercased. */
export function agentInitial(name: string): string {
  return name.replace(/^agt_/, '').charAt(0).toUpperCase();
}
