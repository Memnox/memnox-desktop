import { describe, expect, it } from 'vitest';
import {
  AGENT_PLACES,
  endLinks,
  FirstRunCoverage,
  FirstRunQuestions,
  joinedThings,
  nextStep,
  previousStep,
  suggestedPlace,
  throughCloud,
  GuideLines,
  GuideMemory,
  ONBOARDING_STEPS,
  permissionsAsked,
  permissionsLine,
  progressOf,
  rowSpoken,
  startingPacks,
  stepCounter,
  stepHeading,
  WELCOME_ROWS,
} from '../src/core/domain/onboarding';
import { permissionSteps, waitingSteps, type PermissionFacts } from '../src/core/domain/permission-steps';

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

  it('runs short steps with two questions asked one at a time, then an end screen', () => {
    expect(ONBOARDING_STEPS).toEqual(['Connect', 'Permissions', 'Its job', 'Where it runs', 'Starting rules']);
    expect(([0, 2, 4] as const).map((step) => stepCounter(step))).toEqual(['Step 1 of 5', 'Step 3 of 5', 'Step 5 of 5']);
    expect(progressOf(0)).toBeCloseTo(1 / 5);
    expect(progressOf(4)).toBe(1);
    expect(progressOf(0, 'done')).toBe(1);
    expect(nextStep(3)).toBe(4);
    expect(nextStep(4)).toBeUndefined();
    expect(previousStep(0)).toBeUndefined();
    expect(stepHeading(0, 'Windows Hello').detail).toContain('Windows Hello becomes the key only you approve with');
    expect(stepHeading(2, 'Windows Hello').title).toBe('What do you want your AI to help with?');
    expect(stepHeading(3, 'Windows Hello').title).toBe('Where does your agent run?');
    expect(stepHeading(4, 'Windows Hello').detail).toContain('The recommended rules are chosen for you');
  });

  it('introduces each step only once', () => {
    const memory = new GuideMemory();
    expect(memory.first('step-1')).toBe(true);
    expect(memory.first('step-1')).toBe(false);
    expect(memory.first('step-2')).toBe(true);
  });
});

describe('the grants step', () => {
  const windows = (microphone: PermissionFacts['microphone']): PermissionFacts => ({ platform: 'windows', session: 'desktop', microphone, typing: true });

  it('lists on Windows only the microphone switch, which is the one thing Windows asks for', () => {
    expect(permissionsAsked(permissionSteps(windows('denied'))).map((step) => step.id)).toEqual(['hear']);
    expect(permissionsLine(permissionsAsked(permissionSteps(windows('denied'))))).toBe('One grant left. Memnox carries on without it, and asks again in Settings.');
    expect(permissionsLine(permissionsAsked(permissionSteps(windows('allowed'))))).toBe('Everything this computer asks for is granted.');
  });

  it('lists nothing on an X11 desktop that asks for nothing, and only what Wayland still lacks', () => {
    const x11: PermissionFacts = { platform: 'linux', session: 'x11', microphone: 'allowed', typing: true, seeing: { portal: null, accessibility: true } };
    expect(permissionsAsked(permissionSteps(x11))).toEqual([]);
    expect(permissionsLine([])).toContain('Nothing to grant');
    const wayland: PermissionFacts = { platform: 'linux', session: 'wayland', microphone: 'allowed', typing: false, seeing: { portal: true, accessibility: true } };
    expect(permissionsAsked(permissionSteps(wayland)).map((step) => step.id)).toEqual(['type']);
  });

  it('says it is still asking before the facts arrive', () => {
    expect(permissionsLine(permissionsAsked(waitingSteps()))).toBe('Asking this computer what it needs.');
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
  it('offers the name, the voice, the workspace and the phone, each in Settings', () => {
    expect(endLinks(undefined).map((link) => [link.id, link.page])).toEqual([
      ['name', 'account'],
      ['voice', 'voice'],
      ['workspace', 'account'],
      ['phone', 'phones'],
    ]);
  });

  it('stops asking for the name once it is given', () => {
    expect(endLinks('Sam').map((link) => link.id)).toEqual(['voice', 'workspace', 'phone']);
  });

  it('offers Memnox Cloud and the phone as optional, never a step', () => {
    const links = endLinks('Sam');
    expect(links.find((link) => link.id === 'workspace')).toMatchObject({ title: 'Sign in to Memnox Cloud', detail: expect.stringMatching(/^Optional\./) });
    expect(links.find((link) => link.id === 'phone')?.detail).toMatch(/^Optional\./);
  });
});

describe('the two questions', () => {
  it('offers every place an agent can run, this computer first, and suggests it when agents were found here', () => {
    expect(AGENT_PLACES.map((place) => place.id)).toEqual(['computer-coding', 'computer-app', 'hosted', 'inside-app', 'no-code', 'own-code', 'none-yet']);
    expect(suggestedPlace(2)).toBe('computer-coding');
    expect(suggestedPlace(0)).toBeUndefined();
    expect(throughCloud('hosted')).toBe(true);
    expect(throughCloud('computer-app')).toBe(false);
    expect(throughCloud('none-yet')).toBe(false);
  });

  it('says what became of the job', () => {
    expect(FirstRunQuestions.jobLine(undefined, undefined)).toBeUndefined();
    expect(FirstRunQuestions.jobLine('Code Review', 'Cursor')).toBe('Code Review now works through Cursor.');
    expect(FirstRunQuestions.jobLine('Code Review', undefined)).toBe('Code Review has no agent behind it yet. Connect one whenever you are ready, under AI agents.');
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

  it('says a place elsewhere is outside Memnox until it reports, and a job with nobody behind it shows no level', () => {
    expect(FirstRunCoverage.place('inside-app')).toBe('Outside Memnox until it is connected. Connected this way, expect: The agent asks Memnox.');
    expect(FirstRunCoverage.place('none-yet')).toBe('Nothing yet. Connect an agent whenever you are ready.');
    expect(FirstRunCoverage.job('Testing')).toBe('Testing has no agent behind it yet, so there is nothing for Memnox to stop or see yet.');
    expect(joinedThings(['Git'])).toBe('Git');
    expect(joinedThings([])).toBe('');
  });
});
