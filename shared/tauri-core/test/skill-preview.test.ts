import { describe, expect, it } from 'vitest';
import { FOUND_UNREADABLE, searchCountLine, skillDocument } from '../src/core/domain/skill-search';
import { acceptedLine, removeLines } from '../src/core/domain/skills-lines';

describe('the Skills page words the Mac says too', () => {
  it('counts what a search leaves in the hub and on this computer', () => {
    expect(searchCountLine({ shown: 2, total: 5 }, { shown: 1, total: 3 })).toBe('2 of 5 in the hub, 1 of 3 found on this computer');
    expect(searchCountLine({ shown: 5, total: 5 }, { shown: 0, total: 0 })).toBe('5 in the hub, 0 found on this computer');
  });

  it('writes the day a version was accepted rather than the raw moment', () => {
    expect(acceptedLine('2026-11-06T09:30:00.000Z', 'en-GB')).toBe('Accepted 6 Nov 2026');
    expect(acceptedLine(undefined)).toBe('Never accepted');
    expect(acceptedLine('soon')).toBe('Accepted soon');
  });

  it('asks before a skill is removed', () => {
    expect(removeLines('release-notes')).toEqual({
      lead: 'Takes release-notes out of the hub and out of every agent it was given to, with every version kept of it.',
      title: 'Remove release-notes?',
      message: 'It leaves the hub and every agent it was given to, and every version kept of it goes too.',
      confirm: 'Remove skill',
    });
  });

  it('reads a SKILL.md front matter apart from its body, as the Mac reader does', () => {
    const document = skillDocument('---\nname: "notes"\ndescription: Writes notes\n  nested: no\ntools:\n---\n# Notes\r\nDo it.');
    expect(document.fields).toEqual([
      { key: 'name', value: 'notes' },
      { key: 'description', value: 'Writes notes' },
    ]);
    expect(document.body).toBe('# Notes\nDo it.');
    expect(skillDocument('# Plain').fields).toEqual([]);
    expect(FOUND_UNREADABLE).toBe('Its SKILL.md could not be read here, so import it and read it in the hub.');
  });
});
