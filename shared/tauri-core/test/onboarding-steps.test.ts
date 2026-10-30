import { describe, expect, it } from 'vitest';
import { agentsFoundLine, foundLine, foundToImport, importedLine, packTitle } from '../src/core/domain/setup-steps';

describe('setting up a workspace on a fresh computer', () => {
  const servers = [
    { agent: 'cursor', path: '~/.cursor/mcp.json', name: 'notion' },
    { agent: 'claude-code', path: '~/.claude.json', name: 'github' },
    { path: '/code/app/.mcp.json', name: 'playwright' },
  ];
  const skills = [
    { id: 'f1', name: 'frontend-design', agent: 'claude-code', kind: 'skill', path: 'p', tools: [], grant: 'g', imported: false },
    { id: 'f2', name: 'old', agent: 'codex-cli', kind: 'skill', path: 'p', tools: [], grant: 'g', imported: true },
  ];

  it('counts what one agent keeps and leaves a repository file where it is', () => {
    const found = foundToImport(servers, skills);
    expect(found.servers.map((each) => each.name)).toEqual(['notion', 'github']);
    expect(found.skills.map((each) => each.id)).toEqual(['f1']);
    expect(found.agents).toBe(2);
    expect(foundLine(found)).toBe('We found 2 MCP servers and 1 skill across 2 agents.');
  });

  it('says plainly when there is nothing to bring in', () => {
    expect(foundLine(foundToImport([], []))).toBe('Nothing to bring in: no agent here keeps MCP servers or skills of its own yet.');
  });

  it('says what an import brought in and what it left', () => {
    expect(importedLine(3, [])).toBe('Brought in 3, now set up once in Memnox.');
    expect(importedLine(1, ['notion: no such file'])).toBe('Brought in 1, now set up once in Memnox. 1 could not be, and stay where they are: notion: no such file');
  });
});

describe('choosing boundaries and connecting agents', () => {
  it('lists a pack with its rule count', () => {
    expect(packTitle({ name: 'Careful', ruleCount: 6 })).toBe('Careful · 6 rules');
    expect(packTitle({ name: 'Open', ruleCount: 1 })).toBe('Open · 1 rule');
  });

  it('says which agents still run outside Memnox', () => {
    expect(agentsFoundLine([{ name: 'Claude Code', status: 'protected' }, { name: 'Cursor', status: 'unprotected' }])).toBe('Found 2 agents. 1 still runs outside Memnox until you protect it.');
    expect(agentsFoundLine([{ name: 'Claude Code', status: 'protected' }])).toBe('Found 1 agent. Every one passes your boundaries first.');
  });
});
