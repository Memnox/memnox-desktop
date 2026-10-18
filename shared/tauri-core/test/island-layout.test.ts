import { describe, expect, it } from 'vitest';
import { finishedCard } from '../src/core/domain/finished-card';
import {
  answeringTurn,
  idleCountdown,
  isLongReply,
  isGrowing,
  ISLAND_WINDOW,
  islandSize,
  islandTop,
  orbSpot,
  RESTING,
  settle,
  showsHeader,
  showsSatellites,
  STAND_IN_NOTCH,
  type IslandMode,
} from '../src/core/domain/island-layout';
import { settledLine } from '../src/core/domain/settled-line';

const notch = STAND_IN_NOTCH;

describe('which mode the island takes', () => {
  it('rests as a peek, and shows the logos beside the notch while something works', () => {
    expect(settle(RESTING)).toBe('peek');
    expect(settle({ ...RESTING, working: 2 })).toBe('compact');
  });

  it('puts a held call first, before anything else that wants the screen', () => {
    expect(settle({ ...RESTING, held: true, question: true, talking: true, opened: true })).toBe('held');
    expect(settle({ ...RESTING, question: true, draft: true })).toBe('question');
    expect(settle({ ...RESTING, draft: true, rule: true })).toBe('draft');
    expect(settle({ ...RESTING, rule: true, finished: true })).toBe('rule');
    expect(settle({ ...RESTING, finished: true, talking: true })).toBe('finished');
  });

  it('keeps the orb alone while talking until words are heard, a rule is said or dictation runs', () => {
    expect(settle({ ...RESTING, talking: true })).toBe('voice');
    expect(settle({ ...RESTING, talking: true, wordsHeard: true })).toBe('hearing');
    expect(settle({ ...RESTING, talking: true, ruling: true })).toBe('hearing');
    expect(settle({ ...RESTING, talking: true, dictating: true })).toBe('hearing');
  });

  it('shows a reply under its question, tall when it is long, and a rule or dictation over both', () => {
    expect(settle({ ...RESTING, talking: true, wordsHeard: true, answering: true })).toBe('conversation');
    expect(settle({ ...RESTING, talking: true, answering: true, answerTall: true })).toBe('answer');
    expect(settle({ ...RESTING, talking: true, answering: true, ruling: true })).toBe('hearing');
    expect(settle({ ...RESTING, answering: true, opened: true })).toBe('empty');
  });

  it('counts only a reply to something asked in this time talking', () => {
    const before = { phase: 'idle', heard: 'what changed', reply: 'Two files.' } as const;
    expect(answeringTurn({ ...before, phase: 'listening' }, before)).toBe(false);
    expect(answeringTurn({ phase: 'thinking', heard: 'and why', reply: '' }, before)).toBe(true);
    expect(answeringTurn({ phase: 'speaking', heard: 'and why', reply: 'Because' }, before)).toBe(true);
    expect(answeringTurn({ phase: 'listening', heard: 'and why', reply: 'Because' }, before)).toBe(true);
    expect(answeringTurn({ phase: 'listening', heard: undefined, reply: '' }, undefined)).toBe(false);
  });

  it('opens a reply tall once it outgrows its card', () => {
    expect(isLongReply('Two files changed.')).toBe(false);
    expect(isLongReply('word '.repeat(120))).toBe(true);
    expect(isLongReply(Array.from({ length: 9 }, (_, line) => `${line}`).join('\n'))).toBe(true);
  });

  it('lets the person talking here come before a phone turn, which only waits behind them', () => {
    expect(settle({ ...RESTING, talking: true, phoneTurn: true })).toBe('voice');
    expect(settle({ ...RESTING, phoneTurn: true, opened: true })).toBe('conversation');
  });

  it('opens on the launcher, a picked answer, the sessions or nothing running', () => {
    const opened = { ...RESTING, opened: true };
    expect(settle({ ...opened, launcher: true, pickedAnswer: true })).toBe('launcher');
    expect(settle({ ...opened, pickedAnswer: true })).toBe('answer');
    expect(settle(opened)).toBe('empty');
    expect(settle({ ...opened, sessions: 3 })).toBe('overview');
    expect(settle({ ...opened, sessions: 3, detail: true })).toBe('session');
  });
});

describe('the measurements each mode is drawn at', () => {
  it('sizes every mode as the Mac does around the stand in notch', () => {
    const sizes: Record<IslandMode, [number, number]> = {
      peek: [144, 24],
      compact: [184, 24],
      voice: [440, 226],
      hearing: [500, 232],
      overview: [560, 196],
      session: [560, 256],
      empty: [560, 150],
      held: [560, 206],
      question: [560, 372],
      finished: [560, 170],
      launcher: [512, 230],
      conversation: [540, 372],
      draft: [540, 430],
      answer: [560, 560],
      rule: [540, 470],
    };
    for (const [mode, [width, height]] of Object.entries(sizes)) expect(islandSize(mode as IslandMode, notch)).toEqual({ width, height });
  });

  it('starts content at 36 and grows a window of 740 by 672 around the island', () => {
    expect(islandTop(notch)).toBe(36);
    expect(islandTop({ width: 185, height: 38 })).toBe(42);
    expect(ISLAND_WINDOW).toEqual({ width: 740, height: 672 });
  });

  it('places the orb beside the notch when small and left of the card when open', () => {
    expect(orbSpot('peek', notch, false)).toEqual({ x: 19, y: 12, diameter: 18 });
    expect(orbSpot('peek', notch, true).diameter).toBe(22);
    expect(orbSpot('compact', notch, true)).toEqual({ x: 27, y: 12, diameter: 23 });
    expect(orbSpot('voice', notch, false)).toEqual({ x: 220, y: 128, diameter: 150 });
    expect(orbSpot('hearing', notch, false)).toEqual({ x: 250, y: 86, diameter: 84 });
    // middle = 36 + (206 - 36 - 10) / 2
    expect(orbSpot('held', notch, false)).toEqual({ x: 62, y: 116, diameter: 56 });
    expect(orbSpot('empty', notch, false)).toEqual({ x: 70, y: 88, diameter: 62 });
    expect(orbSpot('question', notch, false)).toEqual({ x: 30, y: 12, diameter: 20 });
  });

  it('decides growing by area, so the shrinking curve only plays when the island gets smaller', () => {
    expect(isGrowing('peek', 'held', notch)).toBe(true);
    expect(isGrowing('held', 'peek', notch)).toBe(false);
    expect(isGrowing('voice', 'hearing', notch)).toBe(true);
  });

  it('shows the header and the satellites only where the Mac does', () => {
    expect(showsHeader('held', false)).toBe(true);
    expect(showsHeader('hearing', true)).toBe(false);
    expect(showsHeader('answer', true)).toBe(false);
    expect(showsSatellites('voice', true)).toBe(false);
    expect(showsSatellites('empty', false)).toBe(true);
  });

  it('counts the last ten seconds of an untouched minute and then closes', () => {
    expect(idleCountdown(10_000)).toEqual({ fraction: undefined, closes: false });
    expect(idleCountdown(55_000)).toEqual({ fraction: 0.5, closes: false });
    expect(idleCountdown(60_000).closes).toBe(true);
  });
});

describe('the card a settled call leaves', () => {
  it('says how a call was settled elsewhere only from what was reported', () => {
    expect(settledLine(undefined)).toBe('No longer waiting');
    expect(settledLine('deny')).toBe('Denied elsewhere');
    expect(settledLine('once', 'Ana', "Ana's iPhone")).toBe("Allowed once on Ana's iPhone");
    expect(settledLine('session', 'Ana', 'console')).toBe('Allowed for the session by Ana in the console');
  });

});

describe('a session that finished', () => {
  it('makes a card of a finished notice and of nothing else', () => {
    const notice = { kind: 'notice' as const, subject: 'ses_1', agent: 'codex', agentName: 'Codex', summary: 'Fixed the login test.', at: '', notice: 'finished', sessionId: 'ses_1' };
    expect(finishedCard(notice)).toEqual({ agent: 'codex', who: 'Codex', summary: 'Fixed the login test.', sessionId: 'ses_1' });
    expect(finishedCard({ ...notice, notice: 'pushed' })).toBeUndefined();
    expect(finishedCard({ ...notice, kind: 'held' })).toBeUndefined();
  });
});
