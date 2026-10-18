import { describe, expect, it } from 'vitest';
import { excerpt, landed, proofCard, unheard } from '../src/core/domain/evidence';

describe('evidence', () => {
  it('counts words as landed only when they show once more than before, however they wrapped', () => {
    expect(landed('run the tests', '> ', '> run the\n tests')).toBe(true);
    expect(landed('run the tests', '> run the tests', '> run the tests')).toBe(false);
    expect(landed('   ', '', 'anything')).toBe(false);
  });

  it('shows the line the words went to with two above it', () => {
    expect(excerpt('a\nb\nc\nd\nrun the tests\ne', 'run the tests')).toBe('c\nd\nrun the tests');
    expect(excerpt('', 'x')).toBe('');
  });

  it('speaks for itself only when the daemon never heard', () => {
    expect(unheard('verified', 'no')).toBeUndefined();
    expect(unheard('waiting', 'no')).toBe('I kept it for its next prompt rather than take your window.');
    expect(unheard('clipboard', 'on the clipboard')).toBe('on the clipboard');
    expect(proofCard({ checked: 'the terminal' })).toBe('Checked the terminal.');
    expect(proofCard({ checked: 'the terminal', seen: 'ok' })).toBe('Checked the terminal:\nok');
  });
});
