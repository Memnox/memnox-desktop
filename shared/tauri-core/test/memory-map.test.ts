import type { MemoryEvidenceView, MemoryItemView, MemorySourceView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { carriedWith, documentLabel, edgeId, MEMORY_LINK, memoryMap, memoryMapIds, walkOrder } from '../src/core/domain/memory-map';
import { AT_REST, fitted, zoomedAt } from '../src/core/domain/surface-camera';
import { FORCES, step, type Body } from '../src/core/domain/surface-forces';
import { between, seeded } from '../src/core/domain/surface-geometry';

const evidence = (document: string, stale = false, source = 'Vault'): MemoryEvidenceView => ({ ref: `${document}#Top`, document, heading: 'Top', source, stale });

const item = (id: string, more: Partial<MemoryItemView> = {}): MemoryItemView => ({
  id,
  kind: 'fact',
  statement: `Statement ${id}`,
  subject: 'subject',
  status: 'verified',
  scope: 'personal',
  origin: 'extracted',
  tainted: false,
  evidence: [],
  createdAt: '2026-10-20T09:00:00Z',
  ...more,
});

const vault: MemorySourceView = { id: 'src_vault', kind: 'obsidian', name: 'Vault', location: '/vault', trust: 'trusted', scope: 'personal', watched: true, counts: { candidate: 0, verified: 1, conflicting: 0, outdated: 0, rejected: 0 } };
const label = (kind: MemorySourceView['kind']) => (kind === 'obsidian' ? 'Obsidian vault' : kind);

describe('the memory map', () => {
  it('draws a fact, the document it cites and the source that holds it, each line a field', () => {
    const map = memoryMap([item('mem_1', { evidence: [evidence('ops/releases.md')] })], [vault], label);
    const doc = memoryMapIds.document('Vault', 'ops/releases.md');
    const src = memoryMapIds.source('Vault');
    expect(map.nodes.map((node) => [node.id, node.kind]).sort()).toEqual([
      [doc, 'document'],
      ['mem_1', 'memory'],
      [src, 'source'],
    ]);
    expect(map.edges.map((edge) => edge.kind).sort()).toEqual([MEMORY_LINK.CITES, MEMORY_LINK.HELD_IN]);
    expect(map.nodes.find((node) => node.id === src)?.detail).toBe('Obsidian vault');
    expect(map.nodes.find((node) => node.id === doc)?.label).toBe('releases.md');
  });

  it('hangs a fact that cites nothing off nothing', () => {
    const map = memoryMap([item('mem_2')], [], label);
    expect(map.nodes.map((node) => node.id)).toEqual(['mem_2']);
    expect(map.edges).toEqual([]);
  });

  it('draws one line to a document cited twice, stale only when both passages changed', () => {
    const doc = memoryMapIds.document('Vault', 'a.md');
    const both = memoryMap([item('m', { evidence: [evidence('a.md', true), evidence('a.md', true)] })], [], label);
    const one = memoryMap([item('m', { evidence: [evidence('a.md', true), evidence('a.md', false)] })], [], label);
    expect(both.edges.filter((edge) => edge.to === doc)).toEqual([{ id: edgeId('m', doc, MEMORY_LINK.CITES), from: 'm', to: doc, kind: MEMORY_LINK.CITES, stale: true }]);
    expect(one.edges.find((edge) => edge.to === doc)?.stale).toBe(false);
  });

  it('shares one document between the facts that cite it, and carries them when it is dragged', () => {
    const map = memoryMap([item('a', { evidence: [evidence('x.md')] }), item('b', { evidence: [evidence('x.md')] })], [], label);
    expect(map.nodes.filter((node) => node.kind === 'document')).toHaveLength(1);
    expect(carriedWith(map, memoryMapIds.document('Vault', 'x.md')).sort()).toEqual(['a', 'b']);
    expect(carriedWith(map, 'a')).toEqual([]);
  });

  it('draws the rule a fact governs, and a restatement only where both facts are listed', () => {
    const rule = { effect: 'ask' as const, actions: ['git.push'], reason: 'protected', sentence: 'Ask before any agent pushes to main.' };
    const map = memoryMap([item('r', { kind: 'rule', rule }), item('d', { duplicateOf: { id: 'r', statement: 'x' } }), item('e', { duplicateOf: { id: 'gone', statement: 'y' } })], [], label);
    expect(map.nodes.find((node) => node.id === memoryMapIds.rule('r'))).toMatchObject({ kind: 'rule', label: rule.sentence, detail: 'ask', item: 'r' });
    expect(map.edges.map((edge) => [edge.from, edge.to, edge.kind])).toEqual([
      ['r', memoryMapIds.rule('r'), MEMORY_LINK.GOVERNS],
      ['d', 'r', MEMORY_LINK.RESTATES],
    ]);
  });

  it('seeds the same picture from the same record, whatever order it arrives in', () => {
    const items = [item('a', { evidence: [evidence('x.md')] }), item('b'), item('c', { evidence: [evidence('y.md')] })];
    expect(memoryMap(items, [], label)).toEqual(memoryMap([...items].reverse(), [], label));
  });

  it('walks facts first, then rules, documents and sources', () => {
    const map = memoryMap([item('a', { evidence: [evidence('x.md')] })], [], label);
    expect(walkOrder(map)).toEqual(['a', memoryMapIds.document('Vault', 'x.md'), memoryMapIds.source('Vault')]);
  });

  it('says a document by its last part', () => {
    expect(documentLabel('ops/releases.md')).toBe('releases.md');
    expect(documentLabel('C:\\notes\\a.md')).toBe('a.md');
    expect(documentLabel('Staging-4f2a.md')).toBe('Staging-4f2a.md');
  });
});

describe('the surface the map is drawn on', () => {
  it('settles to a stop rather than shivering, and never moves a pinned node', () => {
    const map = memoryMap([item('a', { evidence: [evidence('x.md')] }), item('b', { evidence: [evidence('x.md')] }), item('c')], [], label);
    const bodies: Body[] = seeded(map.nodes).map((node) => ({ id: node.id, x: node.x, y: node.y, vx: 0, vy: 0 }));
    const pinned = bodies[0] as Body;
    const at = { x: pinned.x, y: pinned.y };
    const nodes = new Map(map.nodes.map((node) => [node.id, node] as const));
    let heat = 1;
    let fastest = Infinity;
    for (let round = 0; round < 400; round += 1) {
      fastest = step(bodies, nodes, map.edges, 1, FORCES, pinned.id, heat);
      heat -= heat * 0.035;
    }
    expect(fastest).toBeLessThan(0.5);
    expect({ x: pinned.x, y: pinned.y }).toEqual(at);
  });

  it('stops a line at the edge of each card rather than its middle', () => {
    const card = { id: 'a', x: 0, y: 0, depth: 0.5, width: 100, height: 40, label: 'a' };
    const other = { ...card, id: 'b', x: 300 };
    const line = between(card, other, 1);
    expect(line).not.toBeNull();
    expect(line?.x1).toBeGreaterThan(50);
    expect(line?.x2).toBeLessThan(250);
  });

  it('zooms about the pointer and fits the whole drawing no closer than life size', () => {
    const size = { width: 800, height: 600 };
    const zoomed = zoomedAt(AT_REST, 2, { x: 400, y: 300 }, size);
    expect(zoomed).toEqual({ k: 2, x: 0, y: 0 });
    const one = [{ id: 'a', x: 0, y: 0, depth: 0.5, width: 40, label: 'a' }];
    expect(fitted(one, size, 1).k).toBe(1);
  });
});
