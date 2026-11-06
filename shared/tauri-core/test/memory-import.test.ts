import type { MemorySourceView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { addedSources, checkOf, counts, fieldLabel, fieldOf, inputsOf, panelExtensions, pathsOf, pickOf, picksFiles, readingLine, readsFile, resultLine, skippedLine, type PathLook } from '../src/core/domain/memory-import';
import { emptySourceForm } from '../src/core/domain/memory-lines';

const look = (path: string, kind: PathLook['kind'], extra: Partial<PathLook> = {}): PathLook => ({ path, kind, readable: true, found: [], cut: false, ...extra });
const check = (looks: PathLook[], kind: Parameters<typeof checkOf>[1]) => checkOf(looks, kind, 'computer');

/** The same cases as the Mac's `MemoryImportTests`, with this computer where the Mac says this Mac. */
describe('memory import', () => {
  it('lets a Markdown source take files and a vault only a folder', () => {
    expect(picksFiles(pickOf('markdown'))).toBe(true);
    expect(panelExtensions(pickOf('markdown'))).toEqual(['md', 'markdown', 'mdc']);
    expect(picksFiles(pickOf('obsidian'))).toBe(false);
    expect(panelExtensions(pickOf('instructions'))).toEqual(['mdc', 'md', 'cursorrules']);
    expect(panelExtensions(pickOf('notion-export'))).toEqual(['md', 'markdown', 'mdc', 'zip']);
    expect(readsFile('/repo/README.MARKDOWN', 'markdown')).toBe(true);
    expect(readsFile('/repo/README.md', 'instructions')).toBe(false);
    expect(fieldLabel('instructions')).toBe('The repository, or its CLAUDE.md or AGENTS.md');
  });

  it('reads paths typed, pasted or dropped, one a line', () => {
    const text = '  "/home/sam/notes/README.md"  \nfile:///home/sam/My%20Notes/\n~/vault/\n\n/home/sam/notes/README.md';
    expect(pathsOf(text, '/home/sam')).toEqual(['/home/sam/notes/README.md', '/home/sam/My Notes', '/home/sam/vault']);
    expect(pathsOf('file:///C:/Users/sam/notes', undefined)).toEqual(['C:/Users/sam/notes']);
    expect(pathsOf('   ', '/home/sam')).toEqual([]);
    expect(fieldOf(['/a', '/b'])).toBe('/a\n/b');
  });

  it('counts the notes the walk reads', () => {
    expect(counts('team/people.md', 'obsidian')).toBe(true);
    expect(counts('.obsidian/workspace.md', 'obsidian')).toBe(false);
    expect(counts('web/node_modules/pkg/README.md', 'markdown')).toBe(false);
    expect(counts('.cursor/rules/style.mdc', 'instructions')).toBe(true);
    expect(counts('docs/CLAUDE.md', 'instructions')).toBe(false);
  });

  it('says why a path will not do', () => {
    expect(check([], 'markdown')).toEqual({ kind: 'nothing' });
    expect(check([look('notes', 'folder')], 'markdown')).toEqual({ kind: 'problem', why: 'Give the whole path, from the top of the drive.' });
    expect(check([look('/gone', 'missing')], 'markdown')).toEqual({ kind: 'problem', why: '/gone is not on this computer.' });
    expect(check([look('/n/a.md', 'file')], 'obsidian')).toEqual({ kind: 'problem', why: 'An Obsidian vault is a folder: choose the vault rather than one note.' });
    expect(check([look('/n/a.txt', 'file')], 'markdown')).toEqual({ kind: 'problem', why: 'a.txt is not Markdown. Choose a .md or .markdown file, or a folder.' });
    expect(check([look('/code/app', 'folder')], 'instructions')).toEqual({ kind: 'problem', why: 'No CLAUDE.md, AGENTS.md, GEMINI.md or Cursor rules in app.' });
    expect(check([look('/n/empty', 'folder')], 'markdown')).toEqual({ kind: 'problem', why: 'No Markdown files in empty.' });
  });

  it('shows what will be read before adding', () => {
    const found = [1, 2, 3, 4, 5, 6, 7].map((n) => `note${n}.md`);
    expect(check([look('/home/sam/labvanced', 'folder', { found })], 'markdown')).toEqual({ kind: 'ready', preview: { headline: '7 Markdown files in labvanced', names: found.slice(0, 5), more: 2, note: undefined } });
    expect(check([look('/v', 'folder', { found: ['a.md'], cut: true })], 'obsidian')).toMatchObject({ preview: { headline: 'At least 1 Markdown file in v' } });
    expect(check([look('/l/devGuidelines.md', 'file'), look('/l/README.md', 'file')], 'markdown')).toMatchObject({ preview: { headline: '2 Markdown files chosen', note: 'Each is added as its own source, and read now.' } });
    expect(check([look('/d/Export.zip', 'file')], 'notion-export')).toMatchObject({ preview: { headline: 'A Notion export zip, Export.zip' } });
  });

  it('adds one source a path and keeps a name only for one', () => {
    expect(inputsOf({ ...emptySourceForm('markdown'), location: '~/notes/README.md', name: 'Readme' }, '/home/sam')).toEqual([{ kind: 'markdown', scope: 'personal', name: 'Readme', location: '/home/sam/notes/README.md' }]);
    const two = inputsOf({ ...emptySourceForm('markdown'), location: '/l/a.md\n/l/b.md', name: 'Ignored' }, '/home/sam');
    expect(two.map((each) => [each.location, each.name])).toEqual([['/l/a.md', undefined], ['/l/b.md', undefined]]);
  });

  it('finds the source an add made', () => {
    const old = { id: 'src_1' } as MemorySourceView;
    const made = { id: 'src_2' } as MemorySourceView;
    expect(addedSources(['src_1'], [old, made])).toEqual([made]);
  });

  it('says what a read passed over and why, and each first read', () => {
    expect(skippedLine(undefined)).toBeUndefined();
    expect(
      skippedLine([
        { document: 'dump.md', reason: 'too-large' },
        { document: 'gone.md', reason: 'unreadable' },
        { document: 'n501.md', reason: 'past-limit' },
      ]),
    ).toBe('Passed over 1 file too large to be notes (dump.md) and 1 file that could not be opened (gone.md). Stopped at the most notes one source reads, so the rest were not read.');
    expect(resultLine({ name: 'a.md', failure: 'a.md is not here.' })).toBe('a.md was not added: a.md is not here.');
    expect(resultLine({ name: 'a.md' })).toBe('a.md was added. Memnox is reading it now.');
    expect(readingLine('labvanced', 2, 3)).toBe('Your agent is reading labvanced (2 of 3). This can take a minute, and closing this keeps it reading.');
  });
});
