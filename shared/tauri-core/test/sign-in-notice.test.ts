import type { DaemonEvent } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { IslandNotices } from '../src/core/application/island-notices';
import { movedOn, RESUME_WITHIN_MS } from '../src/core/domain/sign-in-notice';
import { HandTimer } from './doubles';

const notice = (kind: string, account?: { name: string; check: string }): DaemonEvent =>
  ({ kind: 'notice', subject: 'n1', agent: 'memnox', summary: 'Gmail', notice: kind, at: new Date(1_000).toISOString(), signedIn: { toolkit: 'gmail', ...(account === undefined ? {} : { account }) } }) as DaemonEvent;

describe('a sign in that stalled or finished', () => {
  it('hangs the pill for a stalled sign in too, with no account to name, as the Mac does', () => {
    const notices = new IslandNotices(new HandTimer().start);
    notices.handle(notice('sign-in-stalled'));
    expect(notices.state.signedIn).toMatchObject({ toolkit: 'gmail', who: undefined, unverified: true });
  });

  it('names the account a finished one reached', () => {
    const notices = new IslandNotices(new HandTimer().start);
    notices.handle(notice('signed-in', { name: 'Ana', check: 'matched' }));
    expect(notices.state.signedIn).toMatchObject({ who: 'Ana', unverified: false });
  });

  it('carries on only while nothing has moved on since', () => {
    const at = new Date(10_000).toISOString();
    expect(movedOn(at, undefined, 20_000)).toBe(false);
    expect(movedOn(at, 15_000, 20_000)).toBe(true);
    expect(movedOn(at, 5_000, 20_000)).toBe(false);
    expect(movedOn(at, undefined, 10_000 + RESUME_WITHIN_MS + 1)).toBe(true);
    expect(movedOn('not a time', undefined, 0)).toBe(true);
  });
});
