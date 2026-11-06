import { describe, expect, it } from 'vitest';
import type { WorkspaceGraphView } from '../src/core/domain/memory-arms/arms-local';
import { BRAIN_HEADING, brainStats, heldReads, homeFilterOf, inViewLine, MEMORY_HOME_FILTERS, MEMORY_HOME_KEY, workspaceShows } from '../src/core/domain/memory-brain-lines';

type WorkspaceNode = WorkspaceGraphView['nodes'][number];
const node = (kind: string, status?: string): WorkspaceNode => ({ id: kind, kind, label: kind, ...(status === undefined ? {} : { status }) }) as unknown as WorkspaceNode;

describe('the brain overlay, in the Mac words', () => {
  it('names the whose memory chips in the Mac order, with computer for Mac', () => {
    expect(MEMORY_HOME_FILTERS.map((each) => each.label)).toEqual(['Everything', 'This computer', 'Workspace']);
    expect(MEMORY_HOME_KEY).toBe('memnox.memory.home');
  });

  it('reads a stored chip back, the Mac value included, and everything otherwise', () => {
    expect(homeFilterOf('workspace')).toBe('workspace');
    expect(homeFilterOf('thisMac')).toBe('thisComputer');
    expect(homeFilterOf(null)).toBe('everything');
    expect(homeFilterOf('nonsense')).toBe('everything');
  });

  it('writes the heading and the count in view as the Mac does', () => {
    expect(BRAIN_HEADING.overline).toBe('WHAT YOUR AGENTS KNOW');
    expect([BRAIN_HEADING.title, BRAIN_HEADING.titleQuiet]).toEqual(['Every memory.', 'Connected.']);
    expect([BRAIN_HEADING.memories, BRAIN_HEADING.sources, BRAIN_HEADING.connections]).toEqual(['MEMORIES', 'SOURCES', 'CONNECTIONS']);
    expect(inViewLine(1)).toBe('1 POINT IN VIEW');
    expect(inViewLine(12)).toBe('12 POINTS IN VIEW');
  });

  it('counts memories, the apps memory came through and every line', () => {
    const map = { nodes: [{ id: 'a', kind: 'memory' }, { id: 'b', kind: 'document' }], edges: [{ id: 'e', from: 'a', to: 'b', kind: 'cites' }] } as never;
    expect(brainStats(map, 3)).toEqual({ memories: 1, sources: 3, connections: 1 });
  });

  it('narrows the workspace decisions to the status chip and keeps what arrived under every chip', () => {
    expect(workspaceShows(node('decision', 'verified'), 'verified')).toBe(true);
    expect(workspaceShows(node('decision', 'verified'), 'candidate')).toBe(false);
    expect(workspaceShows(node('policy'), 'verified')).toBe(true);
    expect(workspaceShows(node('policy'), 'outdated')).toBe(false);
    expect(workspaceShows(node('document'), 'rejected')).toBe(true);
    expect(workspaceShows(node('decision', 'candidate'), undefined)).toBe(true);
  });

  it('draws this computer alone, the workspace alone, or both', () => {
    const workspace = { nodes: [node('decision', 'verified'), node('decision', 'candidate')], links: [] } as unknown as WorkspaceGraphView;
    const reads = { items: [], skills: [{ name: 'tidy' }], workspace };
    expect(heldReads(reads, 'thisComputer', 'verified')).toEqual({ items: [], skills: [{ name: 'tidy' }] });
    const alone = heldReads(reads, 'workspace', 'verified');
    expect(Object.keys(alone)).toEqual(['workspace']);
    expect(alone.workspace?.nodes).toHaveLength(1);
    expect(heldReads(reads, 'everything', undefined).workspace?.nodes).toHaveLength(2);
  });
});
