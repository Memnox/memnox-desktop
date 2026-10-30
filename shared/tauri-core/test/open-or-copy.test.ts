import { describe, expect, it } from 'vitest';
import { openOrCopy } from '../src/ui/settings/host';

describe('opening a local file', () => {
  it('opens it where the computer can, and copies its whole path where it cannot', async () => {
    const copied: string[] = [];
    const copy = async (text: string) => void copied.push(text);
    expect(await openOrCopy({ openFile: async () => true, copy }, '/home/sam/a.md')).toBe(true);
    expect(copied).toEqual([]);
    expect(await openOrCopy({ openFile: async () => false, copy }, '/home/sam/run.sh')).toBe(false);
    expect(await openOrCopy({ copy }, '/home/sam/b.md')).toBe(false);
    expect(copied).toEqual(['/home/sam/run.sh', '/home/sam/b.md']);
  });
});
