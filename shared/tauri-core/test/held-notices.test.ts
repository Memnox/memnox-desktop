import { describe, expect, it } from 'vitest';
import { HeldNotices, NOTICE_OPENS, noticeOf, type NoticeCall } from '../src/core/domain/held-notices';

const push: NoticeCall = { subject: 'a', label: 'Claude Code', what: 'git push origin main' };
const pushAgain: NoticeCall = { subject: 'b', label: 'Claude Code', what: 'git push origin main' };
const deploy: NoticeCall = { subject: 'c', label: 'Codex', what: 'npm run deploy' };

describe('a held call said by the system', () => {
  it('says who waits and on what', () => {
    expect(noticeOf(push)).toEqual({ subject: 'a', title: 'Claude Code is waiting on you', body: 'git push origin main' });
  });

  it('posts one notification per call, and none for a call told again', () => {
    const notices = new HeldNotices();
    expect(notices.next([push], undefined).map((each) => each.subject)).toEqual(['a']);
    expect(notices.next([push], undefined)).toEqual([]);
    expect(notices.next([push, deploy], undefined).map((each) => each.subject)).toEqual(['c']);
  });

  it('folds an identical hold into the one already said', () => {
    const notices = new HeldNotices();
    notices.next([push], undefined);
    expect(notices.next([push, pushAgain], undefined)).toEqual([]);
  });

  it('says nothing for the call the island is showing, and folds its twins into it', () => {
    const notices = new HeldNotices();
    expect(notices.next([push], 'a')).toEqual([]);
    expect(notices.next([push, pushAgain], 'a')).toEqual([]);
    expect(notices.next([push, pushAgain, deploy], 'a').map((each) => each.subject)).toEqual(['c']);
  });

  it('says the same hold again once every call of it stopped waiting', () => {
    const notices = new HeldNotices();
    notices.next([push], undefined);
    notices.next([], undefined);
    expect(notices.next([pushAgain], undefined).map((each) => each.subject)).toEqual(['b']);
  });

  it('opens Needs you where the call waits', () => {
    expect(NOTICE_OPENS).toEqual({ destination: 'needs-you', tab: 'decide-now' });
  });
});
