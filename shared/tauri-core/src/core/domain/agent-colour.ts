/**
 * Each agent keeps one colour everywhere it appears, ported from the Mac's `IslandPalette.color`; any
 * other kind takes one of five by a small hash of its name, so the same name always lands the same.
 */

const KNOWN: Record<string, string> = {
  'claude-code': '#D97757',
  claude: '#D97757',
  'claude-desktop': '#D97757',
  codex: '#2DD4BF',
  'codex-cli': '#2DD4BF',
  cursor: '#C0C4CC',
  gemini: '#8AB4F8',
  'gemini-cli': '#8AB4F8',
  antigravity: '#E879F9',
  hermes: '#A78BFA',
  openclaw: '#F7B32B',
  cline: '#38BDF8',
  'copilot-cli': '#7EE787',
  opencode: '#FB7185',
};

const OTHERS = ['#F472B6', '#34D399', '#FB923C', '#60A5FA', '#E879F9'] as const;

/** How the daemon prefixes an agent id, dropped to leave the agent's kind. */
const AGENT_ID_PREFIX = 'agt_';
/** The multiplier and mask of the name hash, kept small so the index stays positive. */
const HASH_MULTIPLIER = 31;
const HASH_MASK = 0xffff;

export function agentKind(agent: string | undefined): string {
  const id = agent ?? '';
  return id.startsWith(AGENT_ID_PREFIX) ? id.slice(AGENT_ID_PREFIX.length) : id;
}

export function agentColour(agent: string | undefined): string {
  const kind = agentKind(agent);
  const known = KNOWN[kind];
  if (known !== undefined) return known;
  let hash = 0;
  // Over unicode scalars rather than UTF-16 units, as Swift's `unicodeScalars` counts them.
  for (const scalar of kind) hash = (hash * HASH_MULTIPLIER + (scalar.codePointAt(0) ?? 0)) & HASH_MASK;
  return OTHERS[hash % OTHERS.length] ?? OTHERS[0];
}
