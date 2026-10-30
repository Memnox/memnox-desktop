import { describe, expect, it } from 'vitest';
import { HeldCallNotices, type NoticeSystem } from '../src/core/application/held-call-notices';
import type { HeldState } from '../src/core/application/held-calls';
import type { HeldCard } from '../src/core/domain/held-card';
import { NOTICES_ASKED_KEY, NOTICES_KEY, type HeldNotice } from '../src/core/domain/held-notices';
import { WaitingCalls } from '../src/core/domain/waiting-calls';

function memoryStore(seed: Record<string, string> = {}) {
  const kept = new Map(Object.entries(seed));
  return { load: (key: string) => kept.get(key) ?? null, save: (key: string, value: string) => void kept.set(key, value), kept };
}

function system(granted: boolean, grants: boolean) {
  const posted: HeldNotice[] = [];
  let asked = 0;
  const port: NoticeSystem = {
    granted: async () => granted,
    ask: async () => {
      asked += 1;
      return grants;
    },
    post: (notice) => void posted.push(notice),
  };
  return { port, posted, asked: () => asked };
}

function state(...calls: { subject: string; what: string }[]): HeldState {
  let waiting = WaitingCalls.empty<HeldCard>();
  for (const call of calls) waiting = waiting.add({ subject: call.subject, label: 'Claude Code', what: call.what } as HeldCard, call.subject, 'this computer');
  return { waiting, key: undefined, connected: true, answering: false, pressed: undefined, settled: undefined };
}

describe('held calls said by the system', () => {
  it('says a call the island is not showing', async () => {
    const { port, posted } = system(true, true);
    const notices = new HeldCallNotices(port, memoryStore(), () => false);
    await notices.changed(state({ subject: 'a', what: 'git push' }));
    expect(posted.map((each) => each.title)).toEqual(['Claude Code is waiting on you']);
  });

  it('says nothing for a call that comes up on the island', async () => {
    const { port, posted } = system(true, true);
    const notices = new HeldCallNotices(port, memoryStore(), () => true);
    await notices.changed(state({ subject: 'a', what: 'git push' }));
    expect(posted).toEqual([]);
    await notices.changed(state({ subject: 'a', what: 'git push' }, { subject: 'b', what: 'npm publish' }));
    expect(posted).toEqual([]);
  });

  it('says nothing once turned off', async () => {
    const { port, posted } = system(true, true);
    const notices = new HeldCallNotices(port, memoryStore({ [NOTICES_KEY]: 'false' }), () => false);
    await notices.changed(state({ subject: 'a', what: 'git push' }));
    expect(posted).toEqual([]);
  });

  it('asks the system once, on the first call due, and never again after a no', async () => {
    const { port, posted, asked } = system(false, false);
    const store = memoryStore();
    const notices = new HeldCallNotices(port, store, () => false);
    await notices.changed(state({ subject: 'a', what: 'git push' }));
    await notices.changed(state({ subject: 'a', what: 'git push' }, { subject: 'b', what: 'npm publish' }));
    expect(asked()).toBe(1);
    expect(store.kept.get(NOTICES_ASKED_KEY)).toBe('true');
    expect(posted).toEqual([]);
  });
});
