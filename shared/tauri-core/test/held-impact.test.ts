import { describe, expect, it } from 'vitest';
import { teamHeldCard } from '../src/core/domain/held-card';
import { impactEvidence, impactRows, readHeldImpact } from '../src/core/domain/held-impact';
import { readHeldCall } from '../src/core/domain/workspace-wire';

const claim = (text: string, basis = 'recorded', source = 'git status') => ({ text, basis, source });
const impact = {
  affected: claim('Pushes three commits to main.'),
  undo: claim('Only by another push.', 'inferred', ''),
  verified: [claim('Tests passed.', 'extracted', 'ci log'), claim('Branch is clean.')],
};
const decoded = () => {
  const read = readHeldImpact(impact);
  if (read === undefined) throw new Error('unread');
  return read;
};
const call = (extra: Record<string, unknown> = {}) => ({ id: 'hc_1', machineId: 'm', agent: 'Codex', operation: 'git.push', reason: 'held', ...extra });

describe('what a held action could affect', () => {
  it('is absent when an older runtime sends none, so the card renders as before', () => {
    const read = readHeldCall(call());
    expect(read?.impact).toBeUndefined();
    if (read === undefined) throw new Error('unread');
    expect('impact' in teamHeldCard(read)).toBe(false);
  });

  it('is read whole and reaches the card', () => {
    const read = readHeldCall(call({ impact }));
    if (read === undefined) throw new Error('unread');
    expect(teamHeldCard(read).impact).toEqual(impact);
    expect(impactRows(decoded())).toEqual([
      { label: 'What could be affected', text: 'Pushes three commits to main.' },
      { label: 'Can it be undone?', text: 'Only by another push.' },
      { label: 'What has been verified', text: 'Tests passed. Branch is clean.' },
    ]);
  });

  it('drops the whole impact when affected or undo is missing or has an unknown basis', () => {
    expect(readHeldImpact({ ...impact, affected: undefined })).toBeUndefined();
    expect(readHeldImpact({ ...impact, undo: claim('x', 'guessed') })).toBeUndefined();
    expect(readHeldImpact({ ...impact, undo: claim('   ') })).toBeUndefined();
    expect(readHeldImpact({ ...impact, verified: 'none' })).toBeUndefined();
    expect(readHeldImpact('impact')).toBeUndefined();
  });

  it('drops only a verified claim that cannot be read', () => {
    const read = readHeldImpact({ ...impact, verified: [claim('ok'), claim('bad', 'maybe'), 7] });
    expect(read?.verified).toEqual([claim('ok')]);
  });

  it('is bounded: text trimmed to 300 and at most eight verified', () => {
    const long = `  ${'a'.repeat(400)}  `;
    const read = readHeldImpact({ ...impact, affected: claim(long, 'recorded', 7 as unknown as string), verified: Array.from({ length: 12 }, (_, i) => claim(`v${i}`)) });
    expect(read?.affected.text).toHaveLength(300);
    expect(read?.affected.source).toBe('');
    expect(read?.verified).toHaveLength(8);
  });

  it('says how each claim is known only for the disclosure', () => {
    expect(impactEvidence(decoded())).toEqual([
      { label: 'recorded', value: 'Pushes three commits to main. (git status)' },
      { label: 'inferred, not checked', value: 'Only by another push.' },
      { label: 'extracted', value: 'Tests passed. (ci log)' },
      { label: 'recorded', value: 'Branch is clean. (git status)' },
    ]);
  });
});
