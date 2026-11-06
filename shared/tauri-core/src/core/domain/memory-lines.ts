import type { MemoryEvidenceView, MemoryItemView, MemoryReadSummary, MemorySearchMode, MemorySourceCounts, MemorySourceInput, MemorySourceView } from '@memnox/core/wire';
import { isAbsoluteFolder } from './launch-lines';
import { agentLabel } from './mcp-hub-lines';
import { counted } from './project-lines';
import { ago } from './session-text';

/**
 * Memory as a person reads it. A statement is shown as it was written, never trimmed or reworded, and a
 * confidence is always the extractor's own: only a person's confirm makes a fact verified.
 */

export type MemoryStatusName = MemoryItemView['status'];
export type MemoryScopeName = MemoryItemView['scope'];
export type MemorySourceKindName = MemorySourceView['kind'];
type Tone = 'good' | 'attention' | 'bad' | 'quiet';

/** The status chips over the list, in the order a person settles them. */
export const MEMORY_FILTERS: readonly { status: MemoryStatusName; label: string }[] = [
  { status: 'verified', label: 'Verified' },
  { status: 'candidate', label: 'Candidate' },
  { status: 'conflicting', label: 'Conflicting' },
  { status: 'outdated', label: 'Outdated' },
  { status: 'rejected', label: 'Rejected' },
];

/** The two scopes memory keeps, as the scope switch names them. */
export const MEMORY_SCOPES: readonly { scope: MemoryScopeName; label: string }[] = [
  { scope: 'personal', label: 'Personal' },
  { scope: 'project', label: 'Project' },
];

const STATUS_WORDS: Record<MemoryStatusName, { word: string; tone: Tone }> = {
  verified: { word: 'Verified', tone: 'good' },
  candidate: { word: 'Waiting to be confirmed', tone: 'attention' },
  conflicting: { word: 'Conflicts with another fact', tone: 'bad' },
  outdated: { word: 'Outdated', tone: 'quiet' },
  rejected: { word: 'Rejected', tone: 'quiet' },
  superseded: { word: 'Restated by a newer fact', tone: 'quiet' },
};

export function statusWord(status: MemoryStatusName): { word: string; tone: Tone } {
  return STATUS_WORDS[status];
}

const KIND_WORDS: Record<MemoryItemView['kind'], string> = { fact: 'Fact', convention: 'Convention', rule: 'Rule' };

export function kindWord(kind: MemoryItemView['kind']): string {
  return KIND_WORDS[kind];
}

/** The kinds the Add source dialog offers, each with what its location is. */
export const SOURCE_KINDS: readonly { kind: MemorySourceKindName; label: string; place: 'folder' | 'repository' | 'secret' | 'server' }[] = [
  { kind: 'obsidian', label: 'Obsidian vault', place: 'folder' },
  { kind: 'markdown', label: 'Markdown folder', place: 'folder' },
  { kind: 'instructions', label: 'Agent instruction files', place: 'repository' },
  { kind: 'notion-export', label: 'Notion export', place: 'folder' },
  { kind: 'supermemory', label: 'Supermemory', place: 'secret' },
  { kind: 'mcp', label: 'MCP memory server', place: 'server' },
];

export function sourceKindLabel(kind: MemorySourceKindName): string {
  return SOURCE_KINDS.find((each) => each.kind === kind)?.label ?? kind;
}

/** Trust said in words beside its tone, since a colour alone says nothing. */
export function trustWord(trust: MemorySourceView['trust']): { word: string; tone: Tone } {
  if (trust === 'trusted') return { word: 'Trusted: your own files', tone: 'good' };
  return { word: 'Untrusted: written outside your own files', tone: 'attention' };
}

const COUNT_WORDS: readonly [keyof MemorySourceCounts, string][] = [
  ['verified', 'verified'],
  ['candidate', 'to confirm'],
  ['conflicting', 'conflicting'],
  ['outdated', 'outdated'],
  ['rejected', 'rejected'],
];

/** "3 verified, 2 to confirm": what a source taught, counted by where each item stands, zeros left out. */
export function sourceCountsLine(counts: MemorySourceCounts): string {
  const parts = COUNT_WORDS.filter(([key]) => counts[key] > 0).map(([key, word]) => `${counts[key]} ${word}`);
  return parts.length === 0 ? 'Taught nothing yet' : parts.join(', ');
}

/** When it was last read, and whether it is read again on its own or only when asked. */
export function lastReadLine(source: Pick<MemorySourceView, 'lastReadAt' | 'watched'>, now: number): string {
  const when = ago(source.lastReadAt, now);
  const read = when === undefined ? 'Not read yet' : `Read ${when}`;
  return `${read}. ${source.watched ? 'Read again when a file in it changes.' : 'Read when you ask.'}`;
}

/** Whether a source that needs a key can be read, never the key itself. */
export function keyLine(source: Pick<MemorySourceView, 'keyHeld'>): string | undefined {
  if (source.keyHeld === undefined) return undefined;
  return source.keyHeld ? 'Its key is kept by this computer.' : 'Its key is not set on this computer, so it cannot be read.';
}

/** One read, said so an empty read and a failed one are told apart. */
export function readSummaryLine(summary: MemoryReadSummary): string {
  if (summary.error !== undefined) return `The read failed: ${summary.error}`;
  const found = `Read ${counted(summary.documents, 'document', 'documents')} and ${counted(summary.passages, 'passage', 'passages')}`;
  const parts = [
    `${summary.added} added`,
    `${summary.merged} merged into what was known`,
    summary.droppedCitations > 0 ? `${counted(summary.droppedCitations, 'citation', 'citations')} dropped for naming no passage` : undefined,
    summary.rejectedBefore > 0 ? `${summary.rejectedBefore} you rejected before, not proposed again` : undefined,
    summary.outdated > 0 ? `${summary.outdated} now outdated` : undefined,
  ].filter((part): part is string => part !== undefined);
  return `${found}: ${parts.join(', ')}. ${extractorLine(summary.extractor)}`;
}

/** Whether the person's own agent read the passages, and what to do when none could. */
export function extractorLine(state: MemoryReadSummary['extractor']): string {
  switch (state) {
    case 'answered':
      return 'Your agent read the new passages.';
    case 'unavailable':
      return 'No agent on this computer could read the new passages, so they wait for the next read. Sign in to Claude Code and read again.';
    case 'unreadable':
      return 'Your agent answered in a shape Memnox could not read, so nothing was learned from these passages.';
    case 'idle':
      return 'Nothing new to read.';
  }
}

/** The extractor's own confidence, labelled as the extractor's so it never reads as a check. */
export function confidenceLine(confidence: number | undefined): string | undefined {
  if (confidence === undefined) return undefined;
  return `The extractor’s own confidence: ${Math.round(Math.min(1, Math.max(0, confidence)) * 100)}%`;
}

/** Who put it in the queue: an agent through memnox_suggest, the extractor reading a source, or a person. */
export function originLine(item: Pick<MemoryItemView, 'origin' | 'suggestedBy'>): string {
  if (item.origin === 'agent') return `Suggested by ${item.suggestedBy === undefined ? 'an agent' : agentLabel(item.suggestedBy)} through memnox_suggest`;
  if (item.origin === 'person') return 'Written by a person';
  return 'Read out of a source by your agent';
}

export const TAINTED_LINE = 'Read from an untrusted source';

/** The earlier item a candidate restates, quoted whole. */
export function duplicateLine(duplicate: { statement: string }): string {
  return `Restates “${duplicate.statement}”`;
}

/** Where one piece of evidence sits, and whether it still says what it did. */
export function evidenceLine(evidence: Pick<MemoryEvidenceView, 'ref' | 'source' | 'stale'>): string {
  return `${evidence.ref} in ${evidence.source}${evidence.stale ? ', changed since it was read' : ''}`;
}

/** Where a press on evidence goes: a secure link to the browser, otherwise the file, joined onto its source's folder. */
export type EvidenceTarget = { kind: 'link'; url: string } | { kind: 'file'; path: string };

export function evidenceTarget(evidence: Pick<MemoryEvidenceView, 'document' | 'source' | 'url'>, sources: readonly Pick<MemorySourceView, 'id' | 'name' | 'location'>[]): EvidenceTarget {
  if (evidence.url !== undefined && evidence.url.startsWith('https://')) return { kind: 'link', url: evidence.url };
  const source = sources.find((one) => one.name === evidence.source || one.id === evidence.source);
  if (source === undefined || isAbsoluteFolder(evidence.document)) return { kind: 'file', path: evidence.document };
  // A Windows folder written with backslashes keeps them, so the path reads as the person's own.
  const separator = source.location.includes('\\') && !source.location.includes('/') ? '\\' : '/';
  return { kind: 'file', path: `${source.location.replace(/[\\/]+$/, '')}${separator}${evidence.document}` };
}

/** What a press on a local file came to: opened in its own app, or its path copied when it could not be. */
export function filePressLine(opened: boolean): string {
  return opened ? 'Opened' : 'Path copied';
}

/** Who settled it and when, for a verified or rejected item. */
export function decidedLine(item: Pick<MemoryItemView, 'decidedAt' | 'decidedBy' | 'status'>, now: number): string | undefined {
  const when = ago(item.decidedAt, now);
  if (when === undefined) return undefined;
  const verb = item.status === 'rejected' ? 'Rejected' : 'Confirmed';
  return `${verb}${item.decidedBy === undefined ? '' : ` by ${item.decidedBy}`} ${when}`;
}

/** The queue as Learn shows it, oldest first, so nothing waits behind what came after it. */
export function oldestFirst(items: readonly MemoryItemView[]): MemoryItemView[] {
  return [...items].sort((a, b) => a.createdAt.localeCompare(b.createdAt));
}

/** "1 thing to confirm in Learn", the row Home shows while the queue holds anything. */
export function learnWaitingLine(count: number): string {
  return `${counted(count, 'thing', 'things')} to confirm in Learn`;
}

/** A cut list never reads as whole. */
export function moreLine(more: number): string | undefined {
  return more > 0 ? `${more} more not shown` : undefined;
}

/** How a search was answered, said under the box so keyword alone never passes for both. */
export function searchModeLine(mode: MemorySearchMode): string {
  return mode === 'semantic' ? 'Searched by meaning, and by keyword' : 'Searched by keyword';
}

/** The command that turns search by meaning on, a CLI setting rather than one this window keeps. */
export const EMBEDDING_COMMAND = 'memnox config set embeddingModel <model>';
export const MEANING_SEARCH_TITLE = 'Search memory by meaning';
/** What Settings says about it, the command shown after these words. */
export const MEANING_SEARCH_LINE =
  'Memory is searched by keyword. To search it by meaning as well, with an embedding model running on this computer such as nomic-embed-text in Ollama, run this in a terminal:';

/** What a confirm did: a fact is verified at once, a rule waits for its signature on the island. */
export function confirmedLine(kind: MemoryItemView['kind'], proposed: boolean, keyTitle: string): string {
  if (proposed || kind === 'rule') return `The rule waits for your signature on the island. Confirm it with ${keyTitle} and it holds.`;
  return `Confirmed. The ${kind} is verified now, and your agents are handed it.`;
}

/** The Add source form as it is typed, every field a string. */
export interface SourceForm {
  readonly kind: MemorySourceKindName;
  readonly location: string;
  readonly name: string;
  readonly scope: MemoryScopeName;
  readonly secret: string;
  readonly server: string;
  readonly tool: string;
}

export function emptySourceForm(kind: MemorySourceKindName): SourceForm {
  return { kind, location: '', name: '', scope: 'personal', secret: kind === 'supermemory' ? 'SUPERMEMORY_API_KEY' : '', server: '', tool: '' };
}

/** What stops the form from being sent, said before it goes. */
export function sourceFormProblem(form: SourceForm): string | undefined {
  const place = SOURCE_KINDS.find((each) => each.kind === form.kind)?.place;
  if (place === 'folder' || place === 'repository') {
    if (form.location.trim() === '') return place === 'repository' ? 'Choose the repository whose instruction files it reads.' : 'Choose the folder it reads.';
    return isAbsoluteFolder(form.location.trim()) ? undefined : 'Give the whole path, from the top of the drive.';
  }
  if (place === 'secret') return form.secret.trim() === '' ? 'Name the secret that holds the key.' : undefined;
  if (form.server.trim() === '') return 'Choose the hub server it reads.';
  return form.tool.trim() === '' ? 'Choose the tool that reads its memory.' : undefined;
}

/** The form as the wire carries it: a key by its secret's name only, never its value. */
export function sourceInputOf(form: SourceForm): MemorySourceInput {
  const place = SOURCE_KINDS.find((each) => each.kind === form.kind)?.place;
  const name = form.name.trim();
  return {
    kind: form.kind,
    scope: form.scope,
    ...(name === '' ? {} : { name }),
    ...(place === 'folder' || place === 'repository' ? { location: form.location.trim() } : {}),
    ...(place === 'secret' ? { secret: form.secret.trim() } : {}),
    ...(place === 'server' ? { server: form.server.trim(), tool: form.tool.trim() } : {}),
  };
}

/** How memory is drawn: the graph of it, the list, or the three layers any agent reads. */
export type MemoryView = 'graph' | 'list' | 'layers';

/**
 * Which view the one Memory page draws: the map when it opens, the view the person switched to after that, and the
 * list for a popped out item, where its details are drawn. A view this runtime does not offer falls back to the map.
 */
export function memoryViewShown(chosen: MemoryView | undefined, offered: readonly MemoryView[], linked: boolean): MemoryView {
  if (chosen !== undefined && offered.includes(chosen)) return chosen;
  return linked ? 'list' : 'graph';
}
