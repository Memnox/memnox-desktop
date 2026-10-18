import { describe, expect, it } from 'vitest';
import { GuideLines, GuideMemory, rowSpoken, WELCOME_ROWS } from '../src/core/domain/onboarding';

describe('the first run guide', () => {
  it('greets by name as the Mac does, and with no name at all', () => {
    expect(GuideLines.welcome('Moise')).toMatch(/^Hi Moise, I’m Memnox\./);
    expect(GuideLines.welcome(undefined)).toMatch(/^Hi, I’m Memnox\./);
    expect(GuideLines.welcome(undefined)).toContain('Click any line to see it on the island.');
    expect(GuideLines.ready('Moise', 'Ctrl Alt Space')).toBe('You’re all set Moise. Press Ctrl Alt Space and say what you need. When an agent needs you, I will ask right here in the island.');
  });

  it("names each system's own grants and key in the setup line", () => {
    expect(GuideLines.setup('windows')).toContain('Windows Hello so only you approve');
    expect(GuideLines.setup('linux')).toContain('your password so only you approve');
    for (const platform of ['windows', 'linux'] as const) expect(GuideLines.setup(platform)).toContain('I install the Memnox service in your home folder');
  });

  it('says a line for every part the welcome lists, with the key of this system', () => {
    for (const row of WELCOME_ROWS) expect(rowSpoken(row.id, 'windows').length).toBeGreaterThan(20);
    expect(rowSpoken('tools', 'windows')).toContain('send it with Windows Hello');
    expect(rowSpoken('tools', 'linux')).toContain('send it with your password');
  });

  it('introduces each step only once', () => {
    const memory = new GuideMemory();
    expect(memory.first('step-1')).toBe(true);
    expect(memory.first('step-1')).toBe(false);
    expect(memory.first('step-2')).toBe(true);
  });
});
