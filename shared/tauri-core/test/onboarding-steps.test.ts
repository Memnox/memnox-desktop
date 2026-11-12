import { describe, expect, it } from 'vitest';
import { agentsFoundLine, packTitle } from '../src/core/domain/setup-steps';
import { END_LATER, ONBOARDING_STEPS, stepHeading } from '../src/core/domain/onboarding';
import { CARD_TITLE } from '../src/core/domain/home-steps';

/** The Mac's first run, `FirstRunLines.steps`, which these steps keep in step with, "Mac" said as "computer". */
const MAC_STEPS = ['This Mac', 'Starting rules'];

describe('the first run, in the Mac’s order', () => {
  it('walks the same two steps as the Mac, ending on the rules', () => {
    expect(ONBOARDING_STEPS.map((step) => step.replace('This computer', 'This Mac'))).toEqual(MAC_STEPS);
    expect(stepHeading(0, 'Windows Hello').title).toBe('Connect this machine');
    expect(stepHeading(1, 'Windows Hello').title).toBe('Your starting rules');
  });

  it('says where the rest of setup waits once Memnox opens', () => {
    expect(END_LATER).toContain('phone');
    expect(END_LATER).toContain('Memnox Cloud');
    expect(END_LATER).toContain(CARD_TITLE);
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
