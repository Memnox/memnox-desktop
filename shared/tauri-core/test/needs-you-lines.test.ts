import type { ActivityRow } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { decidedLines, NeedsYouLines } from '../src/core/domain/needs-you-lines';

const row = (id: string, fields: Partial<ActivityRow>): ActivityRow =>
  ({ id, at: '2026-11-01T09:00:00Z', agent: 'codex', agentName: 'Codex', session: 's', kind: 'command', operation: 'git.push', effect: 'allow', reason: 'r', ...fields }) as ActivityRow;

describe('what the person decided today', () => {
  it('keeps only answered rows, said the way the person would tell it', () => {
    const lines = decidedLines([
      row('a', { answeredBy: 'Sam', answeredHow: 'signed', agentName: 'Claude Code' }),
      row('b', { answeredBy: 'Sam', effect: 'deny' }),
      row('c', {}),
    ]);
    expect(lines.map((each) => each.id)).toEqual(['a', 'b']);
    expect(lines[0]?.caption).toBe('Claude Code · Sam, signed');
    expect(lines.map((each) => each.outcome)).toEqual(['Let go ahead', 'Stopped']);
    expect(NeedsYouLines.view.decided).toBe('Decided today');
  });
});
