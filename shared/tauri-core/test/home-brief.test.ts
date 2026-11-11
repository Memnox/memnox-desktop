import type { ActivityRow, AgentView, SessionCard } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { briefItems, HOME_BRIEF_NONE, HOME_BRIEF_TITLE, homeBrief } from '../src/core/domain/home-brief';
import type { TodaySources } from '../src/core/domain/today-board';

const now = new Date(2026, 10, 1, 13, 14).getTime();
const at = (minutesAgo: number) => new Date(now - minutesAgo * 60_000).toISOString();
const empty: TodaySources = { held: [], sessions: [], activity: [], agents: [], owed: [] };

function row(id: string, fields: Partial<ActivityRow>): ActivityRow {
  return { id, at: at(5), agent: 'claude-code', agentName: 'Claude Code', session: 's1', kind: 'shell', operation: 'run', target: 'npm test', effect: 'allow', reason: 'allowed', ...fields } as ActivityRow;
}

function card(sessionId: string, fields: Partial<SessionCard>): SessionCard {
  return { sessionId, agent: 'codex', agentName: 'Codex', state: 'working', thinking: false, repository: '/code/memnox', lastActive: at(1), ...fields } as SessionCard;
}

describe('Home brief', () => {
  it('reads the blocks in the contract’s order and words, an empty one kept so it can say so, and Not covered left off for now', () => {
    const blocks = homeBrief(empty, now);
    expect(blocks.map(({ block }) => HOME_BRIEF_TITLE[block])).toEqual(['Needs you', 'Working now', 'Ready to hand over', 'Today']);
    expect(blocks.every(({ items }) => items.length === 0)).toBe(true);
    expect(HOME_BRIEF_NONE.waiting).toBe('Nothing needs you. Agents keep working inside their rules.');
  });

  it('puts each of Today’s items under the block that answers it', () => {
    const blocks = homeBrief(
      {
        ...empty,
        held: [{ subject: 'h1', agent: 'codex', who: 'Codex', what: 'push to main', at: at(2) }],
        activity: [row('ran', { at: at(3) })],
        sessions: [card('s-working', {})],
        owed: ['Sign in'],
        agents: [{ kind: 'cursor', name: 'Cursor', status: 'unprotected' } as AgentView],
        ready: { action: 'npm test', approvals: 12, targets: [], because: 'You always said yes' },
      },
      now,
    );
    expect(blocks.map(({ block, items }) => [block, items.map((item) => item.id)])).toEqual([
      ['waiting', ['held:h1', 'owed:Sign in']],
      ['working', ['session:s-working']],
      ['ready', ['ready:npm test']],
      ['today', ['row:ran']],
    ]);
    expect(briefItems(blocks)[0]?.id).toBe('held:h1');
  });
});
