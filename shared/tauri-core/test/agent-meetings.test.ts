import { describe, expect, it } from 'vitest';
import { meetingLines } from '../src/core/domain/agent-meetings';

const names: Record<string, string> = { 'claude-code': 'Claude Code', codex: 'Codex', cursor: 'Cursor' };

describe('where an agent meets the others', () => {
  it('says shared files, then holds, then waits, for that agent only', () => {
    const view = {
      holds: [{ agent: 'claude-code', path: 'src/billing/', until: 't' }, { agent: 'codex', path: 'a.ts', until: 't' }],
      together: [{ target: '/work/site/prices.json', agents: ['claude-code', 'codex', 'cursor'], at: 't' }],
      heldBack: [{ agent: 'claude-code', what: '/work/site/a.ts', said: 'Codex has it', at: 't' }],
    };
    expect(meetingLines(view, 'claude-code', (kind) => names[kind] ?? kind)).toEqual([
      'In prices.json with Codex and Cursor right now.',
      'Holds billing, so no other agent changes it.',
      'Waited for a.ts, which another agent had.',
    ]);
    expect(meetingLines({ holds: [], together: [], heldBack: [] }, 'codex', (kind) => kind)).toEqual([]);
  });
});
