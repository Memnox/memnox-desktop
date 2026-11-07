import type { SessionCard } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { workspacesFrom } from '../src/core/domain/workspaces';

function card(over: Partial<SessionCard>): SessionCard {
  return { sessionId: 's', agent: 'claude-code', agentName: 'Claude Code', state: 'ended', thinking: false, ...over };
}

describe('workspaces as the sessions tell them', () => {
  it('groups by repository, names each agent once, and puts the latest first', () => {
    const now = Date.parse('2026-10-30T12:00:00Z');
    const seen = workspacesFrom(
      [
        card({ sessionId: 'a', repository: '/code/memnox', lastActive: '2026-10-30T10:00:00Z' }),
        card({ sessionId: 'b', repository: '/code/memnox', agent: 'codex-cli', agentName: 'Codex', lastActive: '2026-10-30T11:00:00Z' }),
        card({ sessionId: 'c', repository: '/code/site', lastActive: '2026-10-29T11:00:00Z' }),
        card({ sessionId: 'd', repository: '/code/memnox', lastActive: '2026-10-30T09:00:00Z' }),
        card({ sessionId: 'e' }),
      ],
      now,
    );
    expect(seen.map((each) => each.path)).toEqual(['/code/memnox', '/code/site']);
    expect(seen[0]?.agents.map((agent) => agent.name)).toEqual(['Claude Code', 'Codex']);
    expect(seen[0]?.sessions).toBe(3);
    expect(seen[0]?.lastActiveAt).toBe('2026-10-30T11:00:00Z');
  });
});
