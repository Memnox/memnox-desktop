import { describe, expect, it } from 'vitest';
import { afterConfirm, caption, toolWord, withShortPaths } from '../src/core/domain/spoken';

describe('what the voice says', () => {
  it('says a path by its last part', () => {
    expect(withShortPaths('edit /Users/ana/code/app.ts, then ~/notes/todo.md.')).toBe('edit app.ts, then todo.md.');
    expect(withShortPaths('and/or /src')).toBe('and/or /src');
  });

  it('names a tool the way a person reads it', () => {
    expect(toolWord('mcp__memnox-operator__sessions')).toBe('sessions');
    expect(toolWord(undefined)).toBe('the machine');
  });

  it('cuts a caption at a word', () => {
    expect(caption('fix the login page and its tests', 14)).toBe('fix the login…');
  });

  it('never calls a command still running done', () => {
    expect(afterConfirm('confirmed', 'started')).toContain('under way');
    expect(afterConfirm('declined', undefined)).toBe('Very well. I have left it as it was.');
  });
});
