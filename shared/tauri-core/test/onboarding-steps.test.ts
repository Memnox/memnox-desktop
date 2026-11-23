import { describe, expect, it } from 'vitest';
import { agentsFoundLine, packTitle } from '../src/core/domain/setup-steps';
import { CARE, CARE_LEVELS, END_LATER, ONBOARDING_STEPS, RECOMMENDED_CARE, stepHeading } from '../src/core/domain/onboarding';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { CARD_TITLE } from '../src/core/domain/home-steps';

/** The Mac's first run, `FirstRunLines.steps`, which these steps keep in step with, "Mac" said as "computer". */
const MAC_STEPS = ['Your agents', 'How careful'];

describe('the first run, in the Mac’s order', () => {
  it('walks the same two steps as the Mac, ending on how careful to be', () => {
    expect(ONBOARDING_STEPS.map((step) => step.replace('This computer', 'This Mac'))).toEqual(MAC_STEPS);
    expect(stepHeading(0, 'Windows Hello').title).toBe('Your agents');
    expect(stepHeading(1, 'Windows Hello').title).toBe('How careful should Memnox be?');
  });

  it('says where the rest of setup waits once Memnox opens', () => {
    expect(END_LATER).toContain('phone');
    expect(END_LATER).toContain('Memnox Cloud');
    expect(END_LATER).toContain(CARD_TITLE);
  });
});

describe('how careful Memnox is', () => {
  it('offers the contract’s levels in its words, each with a shipped pack where it stops', () => {
    // Cast is safe: the contract is ours and checked by the runtime's own test.
    const careful = JSON.parse(readFileSync(fileURLToPath(new URL('../../ux/contract.json', import.meta.url)), 'utf8')).careful as {
      order: string[];
      recommended: string;
      levels: Record<string, { label: string; line: string; mode: string; pack?: string }>;
    };
    expect([...CARE_LEVELS]).toEqual(careful.order);
    expect(RECOMMENDED_CARE).toBe(careful.recommended);
    for (const level of CARE_LEVELS) {
      expect(CARE[level].label).toBe(careful.levels[level]?.label);
      expect(CARE[level].line).toBe(careful.levels[level]?.line);
      expect(CARE[level].enforces).toBe(careful.levels[level]?.mode === 'enforce');
      expect(CARE[level].pack).toBe(careful.levels[level]?.pack);
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
