import { describe, expect, it } from 'vitest';
import { pronounced } from '../src/core/domain/pronounce';

describe('an email address said aloud', () => {
  it('reads it whole, with its ending, and keeps the full stop that ends the sentence', () => {
    expect(pronounced('Your Gmail is connected, as moiserushanika2006@gmail.com.')).toBe(
      'Your Gmail is connected, as moiserushanika2006 at gmail dot com.',
    );
    expect(pronounced('It goes to moise.r@memnox.com, asking him.')).toBe(
      'It goes to moise dot r at memnox dot com, asking him.',
    );
  });
});
