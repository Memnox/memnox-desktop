import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { PROPOSAL_PHRASES, proposalPrompt, unaskedLine } from '../src/core/domain/proposal-lines';
import { LINES } from '../src/core/domain/spoken';

const shared = fileURLToPath(new URL('../../vectors/protocol.json', import.meta.url));
const kinds = (JSON.parse(readFileSync(shared, 'utf8')) as { values: Record<string, string[]> }).values['proposalKinds'] ?? [];

describe('a proposal worded by its kind', () => {
  it('has words for every kind the runtime proposes, and none it does not', () => {
    expect(kinds.length).toBeGreaterThan(0);
    expect(Object.keys(PROPOSAL_PHRASES).sort()).toEqual([...kinds].sort());
  });

  it('puts the kind before its own words on the key prompt', () => {
    expect(proposalPrompt({ proposalKind: 'lan', summary: 'Let paired phones reach this machine on the local network' })).toBe(
      'Opening this computer to your local network: Let paired phones reach this machine on the local network',
    );
  });

  it('names the kind it declined', () => {
    expect(unaskedLine({ proposalKind: 'skills-hub', summary: 'Accept a skill' })).toBe(
      'Something proposed a change to your skills, which you did not ask for. I have declined it.',
    );
  });

  it('falls back to its own words from an older daemon, or a kind this app does not know', () => {
    expect(proposalPrompt({ summary: 'keep GITHUB_TOKEN' })).toBe('keep GITHUB_TOKEN');
    expect(proposalPrompt({ proposalKind: 'something-new', summary: 'keep GITHUB_TOKEN' })).toBe('keep GITHUB_TOKEN');
    expect(unaskedLine({ summary: 'keep GITHUB_TOKEN' })).toBe(LINES.unasked);
    expect(unaskedLine({ proposalKind: 'something-new', summary: 'x' })).toBe(LINES.unasked);
  });
});
