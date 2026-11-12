import { describe, expect, it } from 'vitest';
import {
  endLinks,
  FirstRunCoverage,
  joinedThings,
  nextStep,
  previousStep,
  GuideLines,
  GuideMemory,
  ONBOARDING_STEPS,
  ONBOARDING_IDS,
  TRY_PROMPT,
  progressOf,
  rowSpoken,
  startingPacks,
  stepCounter,
  stepHeading,
  WELCOME_ROWS,
} from '../src/core/domain/onboarding';

describe('the first run guide', () => {
  it('greets by name as the Mac does, and with no name at all', () => {
    expect(GuideLines.welcome('Moise')).toMatch(/^Hi Moise, I’m Memnox\./);
    expect(GuideLines.welcome(undefined)).toMatch(/^Hi, I’m Memnox\./);
    expect(GuideLines.welcome(undefined)).toContain('No account needed.');
    expect(GuideLines.ready('Moise', 'Ctrl Alt Space')).toBe('You’re all set Moise. Press Ctrl Alt Space and say what you need. When an agent needs you, I will ask right here in the island.');
  });

  it("names each system's own grants and key in the setup line", () => {
    expect(GuideLines.setup('windows')).toContain('From you I need one thing now: Windows Hello so only you approve.');
    expect(GuideLines.setup('linux')).toContain('your password so only you approve');
    expect(GuideLines.boundaries('windows')).toContain('confirm it with Windows Hello on the island');
    for (const platform of ['windows', 'linux'] as const) expect(GuideLines.setup(platform)).toContain('I install the Memnox service in your home folder');
  });

  it('says a line for every part the welcome lists, with the key of this system', () => {
    for (const row of WELCOME_ROWS) expect(rowSpoken(row.id, 'windows').length).toBeGreaterThan(20);
    expect(rowSpoken('tools', 'windows')).toContain('send it with Windows Hello');
    expect(rowSpoken('tools', 'linux')).toContain('send it with your password');
  });

  it('runs two of the contract’s steps, then an end screen', () => {
    expect(ONBOARDING_IDS).toEqual(['connect', 'rules']);
    expect(ONBOARDING_STEPS).toHaveLength(2);
    expect(([0, 1] as const).map((step) => stepCounter(step))).toEqual(['Step 1 of 2', 'Step 2 of 2']);
    expect(progressOf(0)).toBeCloseTo(1 / 2);
    expect(progressOf(1)).toBe(1);
    expect(progressOf(0, 'done')).toBe(1);
    expect(nextStep(0)).toBe(1);
    expect(nextStep(1)).toBeUndefined();
    expect(previousStep(0)).toBeUndefined();
    expect(stepHeading(0, 'Windows Hello').detail).toContain('Windows Hello becomes the key only you approve with');
    expect(stepHeading(1, 'Windows Hello').detail).toContain('The recommended rules are chosen for you');
  });

  it('says how short setup is, and where the phone and Memnox Cloud wait', () => {
    expect(GuideLines.twoSteps).toBe('Setup takes two short steps, and I will talk you through both.');
    expect(GuideLines.done).toContain('pair your phone or sign in to Memnox Cloud later');
  });

  it('introduces each step only once', () => {
    const memory = new GuideMemory();
    expect(memory.first('step-1')).toBe(true);
    expect(memory.first('step-1')).toBe(false);
    expect(memory.first('step-2')).toBe(true);
  });
});

describe('the starting rules step', () => {
  it('chooses the safe defaults the runtime ships, and folds the rest away', () => {
    const packs = [{ id: 'read-only-agents' }, { id: 'safe-defaults' }, { id: 'no-outward-writes' }];
    const starting = startingPacks(packs);
    expect(starting.recommended?.id).toBe('safe-defaults');
    expect(starting.others.map((pack) => pack.id)).toEqual(['read-only-agents', 'no-outward-writes']);
  });

  it('falls back to the first pack where the runtime ships no safe defaults, and to none where it ships nothing', () => {
    expect(startingPacks([{ id: 'careful' }, { id: 'open' }]).recommended?.id).toBe('careful');
    expect(startingPacks([])).toEqual({ recommended: undefined, others: [] });
  });
});

describe('the end screen', () => {
  it('offers the name and the voice, each in Settings', () => {
    expect(endLinks(undefined).map((link) => [link.id, link.page])).toEqual([
      ['name', 'account'],
      ['voice', 'voice'],
    ]);
    expect(endLinks('Sam').map((link) => link.id)).toEqual(['voice']);
  });

  it('offers the contract’s prompt to try first', () => {
    expect(TRY_PROMPT).toBe('Make a folder called memnox-try, then delete it with rm -rf memnox-try.');
  });
});

describe('what Memnox can and cannot do, at the end', () => {
  const levels = {
    context: 'mediated',
    instructions: 'mediated',
    tools: 'enforced',
    activity: 'observed',
    coordination: 'none',
    approval: 'enforced',
    enforcement: { shell: 'enforced', filesystem: 'enforced', git: 'mediated', network: 'none', browser: 'none', mcp: 'observed' },
  } as const;

  it('groups what an agent does by level in plain words, strongest first, a level with nothing left out', () => {
    const lines = FirstRunCoverage.lines(levels);
    expect(lines.map((line) => line.plain)).toEqual(['Memnox stops this', 'Memnox checks this', 'Memnox only sees this', 'Outside Memnox']);
    expect(lines[0]?.sentence).toBe('Memnox stops this: Its tools, Asking you first, Commands and Files.');
  });

  it('lists things the way a sentence does', () => {
    expect(joinedThings(['Git'])).toBe('Git');
    expect(joinedThings([])).toBe('');
  });
});
