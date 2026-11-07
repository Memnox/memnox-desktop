import { describe, expect, it } from 'vitest';
import { NO_LEVELS, type AgentConnection, type CapabilityLevels } from '../src/core/domain/agent-wire';
import { connectionKindLine, connectionLevel, headlineLevel, LEVEL_WORDS, levelRows, seamRows } from '../src/core/domain/capability-level-lines';

const hooked: CapabilityLevels = {
  ...NO_LEVELS,
  context: 'mediated',
  instructions: 'mediated',
  tools: 'mediated',
  activity: 'mediated',
  coordination: 'mediated',
  approval: 'enforced',
  enforcement: { ...NO_LEVELS.enforcement, shell: 'enforced', filesystem: 'mediated' },
};

describe('capability levels in plain words', () => {
  it('words every level as every surface does', () => {
    expect(Object.values(LEVEL_WORDS)).toEqual(['Memnox stops this', 'Memnox checks this', 'The agent asks Memnox', 'Memnox only sees this', 'Outside Memnox']);
  });

  it('wears the weakest of the six on a pill, so a pill never says more than the strip', () => {
    expect(headlineLevel(hooked)).toBe('mediated');
    expect(headlineLevel({ ...hooked, tools: 'observed' })).toBe('observed');
    expect(levelRows(NO_LEVELS).every((each) => each.plain === 'Outside Memnox')).toBe(true);
  });

  it('never reads an advisory connection as enforced', () => {
    const connection: AgentConnection = { id: 'con_x', profileId: 'p', kind: 'mcp', mediation: 'advisory', firstSeen: '', lastSeen: '', status: 'live' };
    expect(connectionLevel(connection)).toBe('advisory');
    expect(connectionKindLine(connection)).toBe('It talks to Memnox over MCP');
  });

  it('lists the seams in the runtime order with their technical words for Advanced', () => {
    const rows = seamRows(hooked);
    expect(rows.map((each) => each.title)).toEqual(['Commands', 'Files', 'Git', 'The network', 'The browser', 'MCP tools']);
    expect(rows[0]?.technical).toBe('enforcement.shell: enforced');
  });
});
