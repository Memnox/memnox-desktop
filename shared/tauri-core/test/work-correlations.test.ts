import { describe, expect, it } from 'vitest';
import { forSession, readWorkCorrelations, shownAs, workLabel, workReason } from '../src/core/domain/work-correlations';

/** A session's issue reads the same here as in the console: linked, not verified, or ambiguous, and nothing else. */

const row = (over: Record<string, unknown>) => ({ id: 'wcr_1', sessionId: 'ses_1', source: 'branch', state: 'linked', lateMatch: false, claim: 'PAY-42', visible: true, ...over });

describe('the issue a session is on', () => {
  it('reads each row on its own and drops one it cannot read', () => {
    const read = readWorkCorrelations({
      correlations: [row({ item: { provider: 'jira', label: 'PAY-42', url: 'https://acme.atlassian.net/browse/PAY-42' } }), { id: 3 }],
    });
    expect(read).toHaveLength(1);
    expect(read[0]?.item?.label).toBe('PAY-42');
  });

  it('says what a link rests on and why a claim is not linked', () => {
    const [linked] = readWorkCorrelations({ correlations: [row({ item: { provider: 'jira', label: 'PAY-42', url: 'https://x.test' } })] });
    const [waiting] = readWorkCorrelations({ correlations: [row({ state: 'pending' })] });
    const [split] = readWorkCorrelations({ correlations: [row({ state: 'ambiguous', matches: 2 })] });
    if (linked === undefined || waiting === undefined || split === undefined) throw new Error('unread');
    expect([workLabel(linked), workReason(linked)]).toEqual(['PAY-42', 'Linked via branch']);
    expect(workLabel(waiting)).toBe('PAY-42, not verified');
    expect(workLabel(split)).toBe('PAY-42 matches 2 trackers, not linked');
  });

  it('shows an item the reader cannot see without naming it', () => {
    const [hidden] = readWorkCorrelations({ correlations: [row({ visible: false, claim: undefined })] });
    if (hidden === undefined) throw new Error('unread');
    expect(workLabel(hidden)).toBe('An item you cannot see');
  });

  it('leaves replaced and removed matches out, one per claim', () => {
    const all = readWorkCorrelations({
      correlations: [row({}), row({ id: 'wcr_2', source: 'commit' }), row({ id: 'wcr_3', state: 'superseded', claim: 'PAY-1' }), row({ id: 'wcr_4', sessionId: 'ses_2' })],
    });
    expect(forSession(all, 'ses_1').map((each) => each.id)).toEqual(['wcr_1']);
    expect(shownAs(all[2] ?? row({}) as never)).toBeUndefined();
  });
});
