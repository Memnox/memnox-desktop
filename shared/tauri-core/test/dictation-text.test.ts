import { describe, expect, it } from 'vitest';
import { cleanedDictation, CURSOR_HINT_LIMIT, cursorHints, dictationFamily, familyStyle, fitted, liveDictation, liveRevision } from '../src/core/domain/dictation-text';

/** What was said, written the way the person would have typed it; the Mac's own cases. */
describe('dictation text', () => {
  it('drops hesitations, takes back what was scratched and keeps breaks said out loud', () => {
    expect(cleanedDictation('so um I think we should uh ship it on friday')).toBe('So I think we should ship it on friday.');
    expect(cleanedDictation('Um, can you look at this?')).toBe('Can you look at this?');
    expect(cleanedDictation("Let's meet on Monday. Let's meet on Tuesday scratch that let's meet on Wednesday")).toBe("Let's meet on Monday. Let's meet on Wednesday.");
    expect(cleanedDictation('hi Sam new paragraph the build is green new line thanks')).toBe('Hi Sam\n\nThe build is green\nThanks.');
  });

  it('spells names their way and lays out items counted off as a list', () => {
    expect(cleanedDictation('move it to post gres and push to git hub for wako AI', { dictionary: ['Postgres', 'GitHub', 'WakoAI'] })).toBe('Move it to Postgres and push to GitHub for WakoAI.');
    expect(cleanedDictation('I need three things first fix the login, second ship the docs and third tell Sam')).toBe('I need three things:\n- Fix the login\n- Ship the docs\n- Tell Sam');
    expect(cleanedDictation('the first build failed')).toBe('The first build failed.');
    expect(cleanedDictation('open server.py in the editor')).toBe('Open server.py in the editor.');
  });

  it('writes a chat message without a full stop, by the app in front', () => {
    expect(cleanedDictation('on my way', { style: familyStyle(dictationFamily('slack')) })).toBe('On my way');
    expect(cleanedDictation('are you there?', { style: familyStyle(dictationFamily('Teams.exe')) })).toBe('Are you there?');
    expect(dictationFamily('outlook')).toBe('email');
    expect(dictationFamily('code')).toBe('prompt');
    expect(dictationFamily('chrome', 'Inbox (3) - Gmail')).toBe('email');
    expect(dictationFamily('chrome', 'Weather')).toBe('general');
  });

  it('fits the words to the cursor', () => {
    expect(fitted('Then ship it.', 'we test it and', undefined)).toBe(' then ship it.');
    expect(fitted('Ship it.', undefined, 'tomorrow')).toBe('Ship it ');
    expect(fitted('I agree.', 'Yes,', undefined)).toBe(' I agree.');
  });

  it('holds back the word still being said, and never lists or closes while speaking', () => {
    expect(liveDictation('send the report to', false)).toBe('Send the report');
    expect(liveDictation('send the report to ', false)).toBe('Send the report to');
    expect(liveDictation('send', false)).toBe('');
    expect(liveDictation('send the report to Sam', true)).toBe('Send the report to Sam');
    expect(liveDictation('um so uh we ship today', true)).toBe('So we ship today');
    const live = liveDictation('first buy milk second call Sam third ship it', true);
    expect(live.includes('\n- ')).toBe(false);
    expect(live.endsWith('.')).toBe(false);
    expect(liveDictation('ask post gres about it', true, { dictionary: ['Postgres'] })).toBe('Ask Postgres about it');
  });

  it('retypes only the changed end, by whole characters', () => {
    expect(liveRevision('Send the repo', 'Send the report')).toEqual({ kept: 'Send the repo', removed: '', added: 'rt' });
    expect(liveRevision('We need to sea it', 'We need to see it')).toEqual({ kept: 'We need to se', removed: 'a it', added: 'e it' });
    expect(liveRevision('Zoëy', 'Zoey')).toMatchObject({ removed: 'ëy', added: 'ey' });
  });

  it('hints the names and codes around the cursor, capped', () => {
    expect(cursorHints('Thanks for the update on ORB-12, I asked Pacilinja and the Postgres team.', 'The deploy is fine')).toEqual(['ORB-12', 'Pacilinja', 'Postgres']);
    const many = Array.from({ length: 40 }, (_, index) => `Name${index + 1}`).join(' ');
    expect(cursorHints(many, undefined)).toHaveLength(CURSOR_HINT_LIMIT);
  });
});
