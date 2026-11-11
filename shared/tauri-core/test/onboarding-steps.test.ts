import { describe, expect, it } from 'vitest';
import { agentsFoundLine, packTitle } from '../src/core/domain/setup-steps';
import { FirstRunCoverage, ONBOARDING_STEPS, stepHeading } from '../src/core/domain/onboarding';

/** The Mac's first run, `FirstRunLines.steps`, which these steps keep in step with, "Mac" said as "computer". */
const MAC_STEPS = ['Who it is for', 'Your agents', 'This Mac', 'Where you are asked', 'Starting rules'];

describe('the first run, in the Mac’s order', () => {
  it('walks the same five steps as the Mac, ending on the rules', () => {
    expect(ONBOARDING_STEPS.map((step) => step.replace('This computer', 'This Mac'))).toEqual(MAC_STEPS);
    expect(stepHeading(1, 'Windows Hello').title).toBe('Which agents do you run?');
    expect(stepHeading(2, 'Windows Hello').title).toBe('Connect this machine');
  });

  it('never shows an agent elsewhere as stopped, only outside Memnox until it is connected', () => {
    for (const place of ['hosted', 'inside-app', 'no-code', 'own-code'] as const) {
      expect(FirstRunCoverage.place(place)).toMatch(/^Outside Memnox until it is connected\./);
      expect(FirstRunCoverage.place(place)).not.toContain('Memnox stops this');
    }
  });
});

describe('choosing boundaries and connecting agents', () => {
  it('lists a pack with its rule count', () => {
    expect(packTitle({ name: 'Careful', ruleCount: 6 })).toBe('Careful · 6 rules');
    expect(packTitle({ name: 'Open', ruleCount: 1 })).toBe('Open · 1 rule');
  });

  it('says which agents still run outside Memnox', () => {
    expect(agentsFoundLine([{ name: 'Claude Code', status: 'protected' }, { name: 'Cursor', status: 'unprotected' }])).toBe('Found 2 agents. 1 still runs outside Memnox until you protect it.');
    expect(agentsFoundLine([{ name: 'Claude Code', status: 'protected' }])).toBe('Found 1 agent. Every one passes your boundaries first.');
  });
});
