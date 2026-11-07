import { describe, expect, it } from 'vitest';
import { heldFacts, NOTHING_WAITING, NOTHING_WAITING_DETAIL, signedLine, waitingLine } from '../src/core/domain/approvals-lines';

describe('the Approvals page words, as the Mac says them', () => {
  it('says what waits and in what order', () => {
    expect(waitingLine(3)).toBe('3 waiting, oldest first.');
    expect(NOTHING_WAITING).toBe('Nothing is waiting on you');
    expect(NOTHING_WAITING_DETAIL).toBe('When an agent asks before doing something your rules hold, it waits here and on the island.');
  });

  it('says how a yes is signed, with the key this computer has', () => {
    expect(signedLine(false, undefined, 'Windows Hello')).toBe('Inside its own repository, so a yes needs no signature');
    expect(signedLine(true, undefined, 'Windows Hello')).toBe('A yes is signed with Windows Hello');
    expect(signedLine(true, 'sha256:x', 'Windows Hello')).toBe('A yes is signed with Windows Hello over exactly this call, so one changed since is refused');
  });

  it('lists the project, why it asks and how it is signed, and nothing else', () => {
    expect(heldFacts({ why: 'Pushing to main asks first', touchID: true, actionDigest: undefined }, 'memnox-desktop', 'Windows Hello').map(([name]) => name)).toEqual(['Project', 'Why it asks', 'Signed']);
    expect(heldFacts({ why: undefined, touchID: false, actionDigest: undefined }, undefined, 'Windows Hello').map(([name]) => name)).toEqual(['Signed']);
  });
});
