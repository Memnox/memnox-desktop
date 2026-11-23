import { describe, expect, it } from 'vitest';
import type { DaemonEvent } from '@memnox/core/wire';
import { heldCard } from '../src/core/domain/held-card';
import { ruleHistoryLines } from '../src/core/domain/rule-history-lines';

describe("Rules' history", () => {
  const now = Date.parse('2026-11-23T12:00:00Z');

  it('says what changed, who answered and whether it holds', () => {
    const lines = ruleHistoryLines(
      [
        { id: 'prp_2', kind: 'removed', rules: ['ask-before-push'], answer: 'declined', answeredAt: '2026-11-23T10:30:00Z', answeredBy: 'Ana', proposedBy: 'Ana' },
        { id: 'prp_1', kind: 'added', rules: ['Never deploy to Railway.'], answer: 'confirmed', answeredAt: '2026-11-23T07:30:00Z', proposedBy: 'agt_memnox-operator' },
      ],
      now,
    );
    expect(lines.map((each) => each.title)).toEqual(['Take out ask-before-push', 'Never deploy to Railway.']);
    expect(lines.map((each) => each.caption)).toEqual([expect.stringMatching(/^Declined by Ana, /), expect.stringMatching(/^Signed, /)]);
    expect(lines.map((each) => each.outcome)).toEqual(['Left as it was', 'In force']);
    expect(lines.map((each) => each.inForce)).toEqual([false, true]);
  });
});

describe('a call kept for later', () => {
  const held = (extra: Partial<DaemonEvent>): DaemonEvent => ({ kind: 'held', subject: 'apr_1', agent: 'claude-code', summary: 'push', at: '2026-11-23T09:00:00Z', ...extra }) as DaemonEvent;

  it('is told apart from one an agent is blocked on', () => {
    expect(heldCard(held({ parkedAt: '2026-11-23T10:00:00Z' })).parked).toBe(true);
    expect(heldCard(held({})).parked).toBeUndefined();
  });
});
