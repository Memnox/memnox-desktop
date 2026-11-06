import type { MemoryReadSummary, MemorySourceInput, MemorySourceView } from '@memnox/core/wire';
import { isAbsoluteFolder } from './launch-lines';
import { readSummaryLine, sourceInputOf, type MemorySourceKindName, type SourceForm } from './memory-lines';
import { counted } from './project-lines';

/**
 * The rules of the Add source dialog's path, ported from the Mac's `MemoryImport`: what may be picked, how a typed or
 * dropped path is read, what the look on disk says before adding, and how the first read is said after. Which notes
 * count mirrors the runtime's folder sources only to preview them; the runtime's own read is what counts.
 */

/** What a kind's location may be, which decides what the system's dialog lets the person pick and what a drop takes. */
export interface SourcePick {
  readonly folders: boolean;
  /** Extensions of the files it reads one by one, lowercased without the dot; empty when only a folder will do. */
  readonly fileExtensions: readonly string[];
  /** Names it reads whatever their extension, such as CLAUDE.md. */
  readonly fileNames: readonly string[];
  /** Takes a zip, which is unzipped beside itself before it is added. */
  readonly archives: boolean;
}

/** What a path is on this disk. */
export type PathKind = 'missing' | 'folder' | 'file' | 'other';

/** One path as the app found it on disk; the host makes every outside read, so the rules here stay pure. */
export interface PathLook {
  readonly path: string;
  readonly kind: PathKind;
  readonly readable: boolean;
  /** For a folder: the files under it its kind reads, relative to it, as far as the look went. */
  readonly found: readonly string[];
  /** The look stopped at its bound, so more may be there. */
  readonly cut: boolean;
}

/** What the dialog says under the path before anything is added. */
export interface ImportPreview {
  readonly headline: string;
  readonly names: readonly string[];
  readonly more: number;
  readonly note: string | undefined;
}

export type ImportCheck = { kind: 'nothing' } | { kind: 'problem'; why: string } | { kind: 'ready'; preview: ImportPreview };

/** How one source of an import ended: its first read, or why it was not added. */
export interface ImportResult {
  readonly name: string;
  readonly summary?: MemoryReadSummary;
  readonly failure?: string;
}

export const MARKDOWN_EXTENSIONS = ['md', 'markdown', 'mdc'];
export const INSTRUCTION_NAMES = ['CLAUDE.md', 'AGENTS.md', 'GEMINI.md', '.cursorrules'];
export const CURSOR_RULES = '.cursor/rules';
export const SKIPPED_FOLDERS = ['node_modules'];
export const ZIP_EXTENSION = 'zip';
/** Names shown under the headline, enough to recognise the notes without a scroll. */
export const SHOWN_NAMES = 5;

const NOTION_NOTE = 'A third party wrote it, so it is read as untrusted.';

/** The words of the dialog around the path, the same as the Mac's sheet. */
export const ImportLines = {
  dropHint: 'Drop files or a folder here, or paste a path, one a line.',
  instructionsHint: 'Reads CLAUDE.md, AGENTS.md, GEMINI.md and .cursor/rules in it.',
  notionHint: 'The zip Notion sent, or the folder it unzipped into. A third party wrote it, so it is read as untrusted.',
  formFooter: 'Your own agent reads it. Nothing it finds counts until you confirm it in Learn.',
  workingFooter: 'The new source is in the list already.',
  finishedNote: 'What your agent found waits in Learn, where you confirm it. Each source is read again when a file in it changes.',
  pageNote: 'Added. What your agent found waits in Learn.',
  unzipping: 'Unzipping the Notion export.',
  choose: 'Choose',
  addAnother: 'Add another',
  done: 'Done',
  read: 'Read',
  notRead: 'Not read',
} as const;

export function pickOf(kind: MemorySourceKindName): SourcePick {
  switch (kind) {
    case 'obsidian':
      return { folders: true, fileExtensions: [], fileNames: [], archives: false };
    case 'markdown':
      return { folders: true, fileExtensions: MARKDOWN_EXTENSIONS, fileNames: [], archives: false };
    case 'instructions':
      return { folders: true, fileExtensions: ['mdc'], fileNames: INSTRUCTION_NAMES, archives: false };
    case 'notion-export':
      return { folders: true, fileExtensions: MARKDOWN_EXTENSIONS, fileNames: [], archives: true };
    default:
      return { folders: false, fileExtensions: [], fileNames: [], archives: false };
  }
}

export function picksFiles(pick: SourcePick): boolean {
  return pick.fileExtensions.length > 0 || pick.fileNames.length > 0 || pick.archives;
}

/** The extensions the system's dialog lets through, a name such as .cursorrules counted by what follows its dot. */
export function panelExtensions(pick: SourcePick): string[] {
  const named = pick.fileNames.map((name) => name.split('.').filter((part) => part !== '').at(-1)?.toLowerCase() ?? name);
  return [...new Set([...pick.fileExtensions, ...named, ...(pick.archives ? [ZIP_EXTENSION] : [])])];
}

/** The words over the path field, saying what it takes. */
export function fieldLabel(kind: MemorySourceKindName): string {
  switch (kind) {
    case 'obsidian':
      return 'The vault folder, from the top of the drive';
    case 'markdown':
      return 'The notes or the folder, from the top of the drive';
    case 'instructions':
      return 'The repository, or its CLAUDE.md or AGENTS.md';
    case 'notion-export':
      return 'The export, as its zip or the folder it unzipped into';
    default:
      return 'Where it is read from';
  }
}

/** The Mac's placeholders with the home this computer keeps, so the example looks like a real path here. */
export function placeholder(kind: MemorySourceKindName, home = '/home/you'): string {
  if (kind === 'instructions') return `${home}/code/project`;
  if (kind === 'notion-export') return `${home}/Downloads/Export.zip`;
  return `${home}/notes`;
}

/** What the system's dialog says over its list, so the person knows a file may be picked as well as a folder. */
export function panelMessage(kind: MemorySourceKindName): string {
  switch (kind) {
    case 'obsidian':
      return 'Choose the folder of your Obsidian vault.';
    case 'markdown':
      return 'Choose Markdown files, or a folder of them. Hold Control to choose several.';
    case 'instructions':
      return 'Choose a repository, or its CLAUDE.md, AGENTS.md, GEMINI.md or a Cursor rule.';
    case 'notion-export':
      return 'Choose the zip Notion sent, or the folder it unzipped into.';
    default:
      return '';
  }
}

export function lastPart(path: string): string {
  return path.split(/[\\/]/).filter((part) => part !== '').at(-1) ?? path;
}

function extensionOf(name: string): string {
  const base = lastPart(name);
  const dot = base.lastIndexOf('.');
  return dot <= 0 ? '' : base.slice(dot + 1).toLowerCase();
}

/** Whether a file of this name is one the kind reads when picked on its own. */
export function readsFile(name: string, kind: MemorySourceKindName): boolean {
  const pick = pickOf(kind);
  return pick.fileNames.includes(lastPart(name)) || pick.fileExtensions.includes(extensionOf(name));
}

export function isZip(path: string): boolean {
  return extensionOf(path) === ZIP_EXTENSION;
}

/** Whether a file found under a folder is one the walk reads: Markdown, never under a dot folder or node_modules. */
export function counts(relativePath: string, kind: MemorySourceKindName): boolean {
  const parts = relativePath.split('/').filter((part) => part !== '');
  const last = parts.at(-1);
  if (last === undefined) return false;
  if (kind === 'instructions') {
    if (parts.length === 1) return INSTRUCTION_NAMES.includes(last);
    return parts.slice(0, -1).join('/') === CURSOR_RULES && MARKDOWN_EXTENSIONS.includes(extensionOf(last));
  }
  if (parts.some((part) => part.startsWith('.') || SKIPPED_FOLDERS.includes(part))) return false;
  return MARKDOWN_EXTENSIONS.includes(extensionOf(last));
}

/** The paths in what was typed, pasted or dropped: one a line, quotes and a file link undone, `~` as home. */
export function pathsOf(text: string, home: string | undefined): string[] {
  const seen = new Set<string>();
  const paths: string[] = [];
  for (const line of text.split(/\r?\n/)) {
    let path = line.trim();
    for (const quote of ['"', "'"]) if (path.length > 1 && path.startsWith(quote) && path.endsWith(quote)) path = path.slice(1, -1);
    if (path.startsWith('file://')) {
      try {
        // The core has no URL, so the link is undone by hand: an empty or localhost host, then the path.
        const rest = path.slice('file://'.length).replace(/^localhost\//, '/');
        const local = decodeURIComponent(rest);
        path = /^\/[A-Za-z]:\//.test(local) ? local.slice(1) : local;
      } catch {
        // A link that does not parse is left as typed, and the look says what is wrong with it.
      }
    }
    if (home !== undefined && (path === '~' || path.startsWith('~/'))) path = home + path.slice(1);
    // A trailing slash names the same folder, so the runtime is sent one spelling of it.
    while (path.length > 1 && (path.endsWith('/') || path.endsWith('\\')) && !/^[A-Za-z]:[\\/]$/.test(path)) path = path.slice(0, -1);
    if (path === '' || seen.has(path)) continue;
    seen.add(path);
    paths.push(path);
  }
  return paths;
}

/** The paths again as the field holds them, one a line. */
export function fieldOf(paths: readonly string[]): string {
  return paths.join('\n');
}

/** What stops a path from being added, or what will be read from it. */
export function checkOf(looks: readonly PathLook[], kind: MemorySourceKindName, computer: string): ImportCheck {
  if (looks.length === 0) return { kind: 'nothing' };
  for (const look of looks) {
    const why = problemOf(look, kind, computer);
    if (why !== undefined) return { kind: 'problem', why };
  }
  return { kind: 'ready', preview: previewOf(looks, kind) };
}

function problemOf(look: PathLook, kind: MemorySourceKindName, computer: string): string | undefined {
  const name = lastPart(look.path);
  if (!isAbsoluteFolder(look.path)) return 'Give the whole path, from the top of the drive.';
  if (look.kind === 'missing') return `${look.path} is not on this ${computer}.`;
  if (look.kind === 'other') return `${name} is neither a folder nor a file.`;
  if (!look.readable) return `Memnox cannot open ${name}. Pick it with Choose, so your system lets Memnox read it.`;
  if (look.kind === 'folder') {
    if (look.found.length === 0) return kind === 'instructions' ? `No CLAUDE.md, AGENTS.md, GEMINI.md or Cursor rules in ${name}.` : `No Markdown files in ${name}.`;
    return undefined;
  }
  const pick = pickOf(kind);
  if (!picksFiles(pick)) return 'An Obsidian vault is a folder: choose the vault rather than one note.';
  if (pick.archives && isZip(look.path)) return undefined;
  if (readsFile(look.path, kind)) return undefined;
  if (kind === 'instructions') return `${name} is not an instruction file. Choose CLAUDE.md, AGENTS.md, GEMINI.md, a Cursor rule, or the repository.`;
  return `${name} is not Markdown. Choose a .md or .markdown file, or a folder.`;
}

function previewOf(looks: readonly PathLook[], kind: MemorySourceKindName): ImportPreview {
  const [one, many] = kind === 'instructions' ? ['instruction file', 'instruction files'] : ['Markdown file', 'Markdown files'];
  const only = looks.length === 1 ? looks[0] : undefined;
  if (only !== undefined && only.kind === 'folder') {
    return {
      headline: `${only.cut ? 'At least ' : ''}${counted(only.found.length, one, many)} in ${lastPart(only.path)}`,
      names: only.found.slice(0, SHOWN_NAMES),
      more: Math.max(0, only.found.length - SHOWN_NAMES),
      note: kind === 'notion-export' ? NOTION_NOTE : undefined,
    };
  }
  if (only !== undefined && isZip(only.path)) {
    return { headline: `A Notion export zip, ${lastPart(only.path)}`, names: [], more: 0, note: `It is unzipped into a folder beside it, and that folder is read. ${NOTION_NOTE}` };
  }
  const files = looks.filter((look) => look.kind === 'file').length;
  const folders = looks.length - files;
  const parts = [...(files > 0 ? [counted(files, one, many)] : []), ...(folders > 0 ? [counted(folders, 'folder', 'folders')] : [])];
  const names = looks.map((look) => lastPart(look.path));
  return {
    headline: `${parts.join(' and ')} chosen`,
    names: names.slice(0, SHOWN_NAMES),
    more: Math.max(0, names.length - SHOWN_NAMES),
    note: looks.length > 1 ? 'Each is added as its own source, and read now.' : undefined,
  };
}

/** The sources the runtime lists now that it did not before, which an add just made. */
export function addedSources(before: readonly string[], after: readonly MemorySourceView[]): MemorySourceView[] {
  const known = new Set(before);
  return after.filter((source) => !known.has(source.id));
}

/** One source per path, the name kept only when a single path is added, since one name cannot fit several. */
export function inputsOf(form: SourceForm, home: string | undefined): MemorySourceInput[] {
  const paths = pathsOf(form.location, home);
  if (paths.length <= 1) return [sourceInputOf({ ...form, location: paths[0] ?? form.location })];
  return paths.map((path) => sourceInputOf({ ...form, location: path, name: '' }));
}

const KNOWN_SKIPS = ['too-large', 'unreadable', 'past-limit'] as const;

function listed(documents: readonly string[]): string {
  const shown = documents.slice(0, SHOWN_NAMES).join(', ');
  const more = documents.length - SHOWN_NAMES;
  return more > 0 ? `${shown} and ${more} more` : shown;
}

/** What a read passed over, said by reason, or undefined when it read everything it holds. */
export function skippedLine(skipped: MemoryReadSummary['skipped']): string | undefined {
  if (skipped === undefined || skipped.length === 0) return undefined;
  const parts: string[] = [];
  const large = skipped.filter((each) => each.reason === 'too-large').map((each) => each.document);
  if (large.length > 0) parts.push(`${counted(large.length, 'file', 'files')} too large to be notes (${listed(large)})`);
  const unreadable = skipped.filter((each) => each.reason === 'unreadable').map((each) => each.document);
  if (unreadable.length > 0) parts.push(`${counted(unreadable.length, 'file', 'files')} that could not be opened (${listed(unreadable)})`);
  // A newer runtime may name a reason this app has no words for yet.
  const other = skipped.filter((each) => !(KNOWN_SKIPS as readonly string[]).includes(each.reason)).length;
  if (other > 0) parts.push(`${counted(other, 'file', 'files')} for a reason this app does not know yet`);
  let line = parts.length === 0 ? '' : `Passed over ${parts.join(' and ')}.`;
  if (skipped.some((each) => each.reason === 'past-limit')) line += `${line === '' ? '' : ' '}Stopped at the most notes one source reads, so the rest were not read.`;
  return line;
}

/** The result of one source's first read as the dialog says it. */
export function resultLine(result: ImportResult): string {
  if (result.failure !== undefined) return `${result.name} was not added: ${result.failure}`;
  if (result.summary === undefined) return `${result.name} was added. Memnox is reading it now.`;
  return readSummaryLine(result.summary);
}

/** Said while the first read runs, since the person's agent can take a minute over many notes. */
export function readingLine(name: string, step: number, total: number): string {
  const place = total > 1 ? ` (${step} of ${total})` : '';
  return `Your agent is reading ${name}${place}. This can take a minute, and closing this keeps it reading.`;
}

/** Said while one source of the import is sent to the runtime. */
export function addingLine(name: string): string {
  return `Adding ${name}.`;
}
