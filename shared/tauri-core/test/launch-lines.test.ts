import { describe, expect, it } from 'vitest';
import { folderProblem, isAbsoluteFolder, launchedLine } from '../src/core/domain/launch-lines';

describe('launching an agent in a folder', () => {
  it('takes a whole path on either system and says what is wrong with another', () => {
    expect(isAbsoluteFolder('/code/memnox')).toBe(true);
    expect(isAbsoluteFolder('C:\\code\\memnox')).toBe(true);
    expect(isAbsoluteFolder('\\\\share\\code')).toBe(true);
    expect(folderProblem('code/memnox')).toBe('Give the whole path, from the top of the drive.');
    expect(folderProblem(' ')).toBe('Choose the folder it opens in.');
    expect(folderProblem('/code')).toBeUndefined();
  });

  it('says where it opened and what it typed', () => {
    expect(launchedLine({ agent: 'claude-code', workingDirectory: '/code/app', line: 'claude' }, 'Claude Code')).toBe('Opened Claude Code in /code/app, typing claude.');
  });
});
