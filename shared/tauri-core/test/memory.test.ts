import type { MemoryItemView, MemoryReadSummary, MemorySourceView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { Memory } from '../src/core/application/memory';
import { RequestIds } from '../src/core/application/request-ids';
import {
  confidenceLine,
  confirmedLine,
  decidedLine,
  duplicateLine,
  emptySourceForm,
  evidenceLine,
  evidenceTarget,
  filePressLine,
  extractorLine,
  keyLine,
  lastReadLine,
  learnWaitingLine,
  moreLine,
  oldestFirst,
  originLine,
  readSummaryLine,
  sourceCountsLine,
  sourceFormProblem,
  sourceInputOf,
  statusWord,
  trustWord,
} from '../src/core/domain/memory-lines';
import { ScriptedDaemon } from './doubles';

const NOW = Date.parse('2026-10-30T12:00:00Z');

const item = (id: string, extra: Partial<MemoryItemView> = {}): MemoryItemView => ({
  id,
  kind: 'fact',
  statement: '  Releases ship on Tuesdays, never Fridays.  ',
  subject: 'releases',
  status: 'candidate',
  scope: 'personal',
  origin: 'extracted',
  tainted: false,
  evidence: [{ ref: 'notes/ops.md#Releases', document: 'notes/ops.md', heading: 'Releases', source: 'Vault', stale: false }],
  createdAt: '2026-10-29T10:00:00Z',
  ...extra,
});

const source: MemorySourceView = {
  id: 'src_1',
  kind: 'obsidian',
  name: 'Vault',
  location: '/home/sam/vault',
  trust: 'trusted',
  scope: 'personal',
  watched: true,
  counts: { candidate: 2, verified: 3, conflicting: 0, outdated: 1, rejected: 0 },
};

const summary: MemoryReadSummary = { sourceId: 'src_1', documents: 4, passages: 12, added: 3, merged: 2, rejectedBefore: 0, droppedCitations: 1, discarded: 0, outdated: 0, extractor: 'answered' };

describe('the wording of memory', () => {
  it('says each status and trust in words beside a tone', () => {
    expect(statusWord('verified')).toEqual({ word: 'Verified', tone: 'good' });
    expect(statusWord('conflicting').tone).toBe('bad');
    expect(trustWord('trusted').word).toBe('Trusted: your own files');
    expect(trustWord('tainted').word).toBe('Untrusted: written outside your own files');
  });

  it('counts what a source taught, leaving zeros out, never a score', () => {
    expect(sourceCountsLine(source.counts)).toBe('3 verified, 2 to confirm, 1 outdated');
    expect(sourceCountsLine({ candidate: 0, verified: 0, conflicting: 0, outdated: 0, rejected: 0 })).toBe('Taught nothing yet');
  });

  it('says when a source was read and whether it is watched, and a key only by whether it is held', () => {
    expect(lastReadLine({ ...source, lastReadAt: '2026-10-30T10:00:00Z' }, NOW)).toBe('Read 2 h ago. Read again when a file in it changes.');
    expect(lastReadLine({ watched: false }, NOW)).toBe('Not read yet. Read when you ask.');
    expect(keyLine({ keyHeld: false })).toBe('Its key is not set on this computer, so it cannot be read.');
    expect(keyLine({})).toBeUndefined();
  });

  it('says a read so an empty one and a failed one are told apart', () => {
    expect(readSummaryLine(summary)).toBe('Read 4 documents and 12 passages: 3 added, 2 merged into what was known, 1 citation dropped for naming no passage. Your agent read the new passages.');
    expect(readSummaryLine({ ...summary, error: 'the folder is gone' })).toBe('The read failed: the folder is gone');
    expect(extractorLine('unavailable')).toBe('No agent on this computer could read the new passages, so they wait for the next read. Sign in to Claude Code and read again.');
  });

  it('labels a confidence as the extractor’s own and names who suggested an item', () => {
    expect(confidenceLine(0.823)).toBe('The extractor’s own confidence: 82%');
    expect(confidenceLine(undefined)).toBeUndefined();
    expect(originLine({ origin: 'agent', suggestedBy: 'claude-code' })).toBe('Suggested by Claude Code through memnox_suggest');
    expect(originLine({ origin: 'extracted' })).toBe('Read out of a source by your agent');
  });

  it('quotes a duplicate and marks stale evidence', () => {
    expect(duplicateLine({ statement: 'Ship on Tuesdays.' })).toBe('Restates “Ship on Tuesdays.”');
    expect(evidenceLine({ ref: 'notes/ops.md#Releases', source: 'Vault', stale: true })).toBe('notes/ops.md#Releases in Vault, changed since it was read');
    expect(decidedLine({ status: 'verified', decidedBy: 'Sam', decidedAt: '2026-10-28T12:00:00Z' }, NOW)).toBe('Confirmed by Sam 2 d ago');
  });

  it('orders the queue oldest first and counts it for Home', () => {
    const queue = oldestFirst([item('b', { createdAt: '2026-10-30T00:00:00Z' }), item('a')]);
    expect(queue.map((each) => each.id)).toEqual(['a', 'b']);
    expect(learnWaitingLine(1)).toBe('1 thing to confirm in Learn');
    expect(learnWaitingLine(4)).toBe('4 things to confirm in Learn');
    expect(moreLine(0)).toBeUndefined();
    expect(moreLine(7)).toBe('7 more not shown');
  });

  it('says a confirmed rule waits on the island', () => {
    expect(confirmedLine('rule', true, 'Windows Hello')).toBe('The rule waits for your signature on the island. Confirm it with Windows Hello and it holds.');
    expect(confirmedLine('fact', false, 'Windows Hello')).toBe('Confirmed. The fact is verified now, and your agents are handed it.');
  });

  it('checks the Add source form and sends a key by its name only', () => {
    expect(sourceFormProblem(emptySourceForm('obsidian'))).toBe('Choose the folder it reads.');
    expect(sourceFormProblem({ ...emptySourceForm('markdown'), location: 'notes' })).toBe('Give the whole path, from the top of the drive.');
    expect(sourceFormProblem({ ...emptySourceForm('mcp'), server: 'memory' })).toBe('Choose the tool that reads its memory.');
    expect(sourceFormProblem(emptySourceForm('supermemory'))).toBeUndefined();
    expect(sourceInputOf({ ...emptySourceForm('supermemory'), location: '/ignored' })).toEqual({ kind: 'supermemory', scope: 'personal', secret: 'SUPERMEMORY_API_KEY' });
    expect(sourceInputOf({ ...emptySourceForm('instructions'), location: ' /code/app ', name: 'App', scope: 'project' })).toEqual({ kind: 'instructions', scope: 'project', name: 'App', location: '/code/app' });
    expect(sourceInputOf({ ...emptySourceForm('mcp'), server: 'memory', tool: 'search' })).toEqual({ kind: 'mcp', scope: 'personal', server: 'memory', tool: 'search' });
  });
});

describe('the memory use case', () => {
  it('reads sources and the queue, and says when the runtime does not answer', async () => {
    const memory = new Memory(
      new ScriptedDaemon({
        'memory-sources': (request) => [{ id: request.id, ok: true, memorySources: [source] }],
        'memory-learn': (request) => [{ id: request.id, ok: true, memoryLearn: { items: [item('a')], more: 0 } }],
      }),
      new RequestIds(),
    );
    await memory.refreshSources();
    await memory.refreshLearn();
    expect(memory.sources).toEqual([source]);
    expect(memory.learn?.items[0]?.statement).toBe('  Releases ship on Tuesdays, never Fridays.  ');
    const down = new Memory(new ScriptedDaemon(), new RequestIds());
    await down.refreshLearn();
    expect(down.unreadable.learn).toBe(true);
  });

  it('lists by status and scope, and searches when words are typed', async () => {
    const daemon = new ScriptedDaemon({
      'memory-facts': (request) => [{ id: request.id, ok: true, memoryFacts: { items: [item('v', { status: 'verified' })], more: 2 } }],
      'memory-search': (request) => [{ id: request.id, ok: true, memoryFacts: { items: [], more: 0 } }],
    });
    const memory = new Memory(daemon, new RequestIds());
    await memory.show({ status: 'outdated', scope: 'project' });
    expect(daemon.sent('memory-facts')[0]).toMatchObject({ memoryStatus: 'outdated', memoryScope: 'project' });
    expect(memory.facts?.more).toBe(2);
    await memory.show({ status: 'verified', query: ' tuesday ' });
    expect(daemon.sent('memory-search')[0]).toMatchObject({ memoryQuery: 'tuesday' });
    expect(memory.facts?.items).toEqual([]);
  });

  it('reads a source now and keeps the summary under its card', async () => {
    const daemon = new ScriptedDaemon({ 'memory-source-read': (request) => [{ id: request.id, ok: true, memorySources: [source], memoryRead: { ...summary, extractor: 'unavailable' } }] });
    const memory = new Memory(daemon, new RequestIds());
    const outcome = await memory.readNow('src_1');
    expect(outcome.kind).toBe('done');
    expect(memory.lastRead('src_1')?.extractor).toBe('unavailable');
  });

  it('confirms a rule as a proposal on the island and passes a refusal on in the runtime’s words', async () => {
    const daemon = new ScriptedDaemon({
      'memory-confirm': (request) => [{ id: request.id, ok: true, proposed: 'prp_1', memoryItem: item('r', { kind: 'rule' }), memoryLearn: { items: [], more: 0 } }],
      'memory-reject': (request) => [{ id: request.id, ok: false, error: 'No memory x.' }],
    });
    const memory = new Memory(daemon, new RequestIds());
    expect(await memory.confirm('r', 'Windows Hello')).toEqual({ kind: 'proposed', id: 'prp_1', note: 'The rule waits for your signature on the island. Confirm it with Windows Hello and it holds.' });
    expect(memory.learn?.items).toEqual([]);
    expect(await memory.reject('x')).toEqual({ kind: 'failed', why: 'No memory x.' });
  });

  it('sends an edit verbatim and forgets an item out of the list', async () => {
    const daemon = new ScriptedDaemon({
      'memory-edit': (request) => [{ id: request.id, ok: true }],
      'memory-facts': (request) => [{ id: request.id, ok: true, memoryFacts: { items: [item('v'), item('w')], more: 0 } }],
      'memory-forget': (request) => [{ id: request.id, ok: true }],
    });
    const memory = new Memory(daemon, new RequestIds());
    await memory.edit('a', ' Ship on Tuesdays ');
    expect(daemon.sent('memory-edit')[0]).toMatchObject({ memoryItemId: 'a', memoryEdit: { statement: ' Ship on Tuesdays ' } });
    await memory.show({ status: 'verified' });
    await memory.forget('v');
    expect(memory.facts?.items.map((each) => each.id)).toEqual(['w']);
  });
});

describe('a press on evidence', () => {
  const sources = [
    { id: 'src_1', name: 'Vault', location: '/home/sam/vault/' },
    { id: 'src_2', name: 'Notes', location: 'C:\\Users\\sam\\notes' },
  ];

  it('sends a secure link to the browser and nothing else', () => {
    expect(evidenceTarget({ document: 'a.md', source: 'Vault', url: 'https://www.notion.so/acme/a' }, sources)).toEqual({ kind: 'link', url: 'https://www.notion.so/acme/a' });
    expect(evidenceTarget({ document: 'a.md', source: 'Vault', url: 'file:///etc/passwd' }, sources)).toEqual({ kind: 'file', path: '/home/sam/vault/a.md' });
  });

  it('joins a file onto its source, in the separator the source is written in', () => {
    expect(evidenceTarget({ document: 'ops/releases.md', source: 'src_1' }, sources)).toEqual({ kind: 'file', path: '/home/sam/vault/ops/releases.md' });
    expect(evidenceTarget({ document: 'releases.md', source: 'Notes' }, sources)).toEqual({ kind: 'file', path: 'C:\\Users\\sam\\notes\\releases.md' });
    expect(evidenceTarget({ document: '/srv/whole.md', source: 'Vault' }, sources)).toEqual({ kind: 'file', path: '/srv/whole.md' });
    expect(evidenceTarget({ document: 'loose.md', source: 'Gone' }, sources)).toEqual({ kind: 'file', path: 'loose.md' });
  });

  it('says whether the file opened or its path was copied', () => {
    expect(filePressLine(true)).toBe('Opened');
    expect(filePressLine(false)).toBe('Path copied');
  });
});
