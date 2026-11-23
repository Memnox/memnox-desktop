import { describe, expect, it } from 'vitest';
import { endLead, PURPOSE } from '../src/core/domain/onboarding';

describe('the end preview', () => {
  it('previews the first ask only where Memnox stops', () => {
    expect(endLead('ask')).toContain('waits for you');
    expect(endLead('strict')).toContain('waits for you');
    expect(endLead('watch')).toContain('stops nothing');
    expect(PURPOSE).toContain('asks you before anything risky');
  });
});
