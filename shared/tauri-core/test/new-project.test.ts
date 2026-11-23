import { describe, expect, it } from 'vitest';
import { knowLines, newProjectName, rememberedLine } from '../src/core/domain/new-project';

describe('a new project', () => {
  it('is named after its folder where the name was skipped', () => {
    expect(newProjectName('  ', '/work/acme-site')).toBe('acme-site');
    expect(newProjectName(' Website ', 'C:\\work\\acme-site')).toBe('Website');
    expect(newProjectName('', 'C:\\work\\acme-site\\')).toBe('acme-site');
  });

  it('keeps what agents should know one thing per line', () => {
    expect(knowLines('Refunds over 500 go to finance.\r\n\n  No email on Sunday. \n')).toEqual(['Refunds over 500 go to finance.', 'No email on Sunday.']);
    expect(rememberedLine(1)).toBe('Agents here will know that from now on.');
    expect(rememberedLine(3)).toBe('Agents here will know those 3 things from now on.');
  });
});
