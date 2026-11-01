import type { MemoryItemView, MemorySourceView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { Memory } from '../src/core/application/memory';
import { RequestIds } from '../src/core/application/request-ids';
import { AGENTS_HUB_ID, MEMORY_INDEX, armsModel } from '../src/core/domain/memory-arms/arms-model';
import { LOCAL_ARMS_IDS, localArmsInput } from '../src/core/domain/memory-arms/arms-local';
import {
  keepList,
  layerCards,
  planDiff,
  planSummary,
  sessionCostLines,
  valueLines,
  workspaceGraphLine,
  type MemoryLayersPlan,
  type MemoryLayersView,
  type ProjectLayersView,
} from '../src/core/domain/memory-layers-lines';
import { ScriptedDaemon } from './doubles';

const project = (extra: Partial<ProjectLayersView> = {}): ProjectLayersView => ({
  name: 'acme',
  path: '/r/acme',
  agents: ['claude-code'],
  index: { path: 'MEMORY.md', present: false, lines: 0, unlinked: 0 },
  routers: [],
  skills: [],
  keep: [],
  ...extra,
});

const cost = (extra: Record<string, unknown>) => ({ days: 30, sessions: 1, turns: 2, coldReloads: 1, reloadedTokens: 10, warmHours: 4, unpricedModels: [], prices: [], ...extra });

describe('the Layers view, as the Mac words it', () => {
  it('numbers the three layers and says how each stands', () => {
    const cards = layerCards(
      project({
        index: { path: 'MEMORY.md', present: true, lines: 12, unlinked: 3 },
        routers: [{ agent: 'claude-code', path: 'CLAUDE.md', present: true, lines: 40, chars: 900, departments: ['macos', 'linux'], routed: 1 }],
        skills: [{ name: 'orders', path: '.claude/skills/orders/SKILL.md', liveData: true }],
      }),
    );
    expect(cards.map((card) => card.number)).toEqual([1, 2, 3]);
    expect(cards.map((card) => card.role)).toEqual(['every chat', 'the router', 'live data']);
    expect(cards[0]?.state).toBe('12 lines, 3 lines linked to no file');
    expect(cards[1]?.state).toBe('Routes 1 of 2 departments');
    expect(cards[2]?.state).toBe('1 skill, 1 say where live data is');
    expect(cards.map((card) => card.settled)).toEqual([false, false, true]);
  });

  it('says a layer is not written yet rather than drawing an empty number', () => {
    const cards = layerCards(project());
    expect(cards[0]?.state).toBe('Not written yet');
    expect(cards[1]?.file).toBe('CLAUDE.md');
    expect(cards[2]?.state).toBe('No SKILL.md in this project');
  });

  it('draws the value line only with measured numbers', () => {
    expect(valueLines(undefined)).toEqual([]);
    expect(valueLines({})).toEqual([]);
    const lines = valueLines({ searchMedianMs: 11.6, searches: 40, contextTokensSaved: 12_500 });
    expect(lines.map((line) => line.title)).toEqual(['Faster to find', 'Cheaper to find']);
    expect(lines[0]?.figure).toBe('12 ms');
    expect(lines[0]?.detail).toBe('median over the last 40 searches');
    expect(lines[1]?.figure).toBe('12,500 tokens');
  });

  it('counts cold reloads and gives money only where every model was priced', () => {
    expect(sessionCostLines(cost({ sessions: 4, turns: 90, coldReloads: 3, reloadedTokens: 1_200_000, reloadCostUsd: 6, warmSavingUsd: 4.25 }))).toEqual([
      '3 cold reloads in 30 days, over 4 chats',
      '1,200,000 tokens written into the cache again',
      'Reloading cost $6.00 at API prices',
      'Keeping chats warm 4h would have saved $4.25',
    ]);
    expect(sessionCostLines(cost({ unpricedModels: ['mystery'] })).at(-1)).toBe('No price is known for mystery, so no total is given');
    expect(sessionCostLines(cost({ reloadCostUsd: 0.01, warmSavingUsd: -0.5 })).at(-1)).toBe('Keeping chats warm 4h would have cost more than it saved');
  });

  it('diffs before and after in order', () => {
    const diff = planDiff(['a', 'b', 'c'], ['a', 'c', 'd']);
    expect(diff.map((line) => line.mark)).toEqual(['same', 'removed', 'same', 'added']);
    expect(diff.map((line) => line.text)).toEqual(['a', 'b', 'c', 'd']);
    expect(planDiff([], ['x']).map((line) => line.mark)).toEqual(['added']);
  });

  it('says what confirming would write, and reads a keep list one line each', () => {
    const file = (changed: boolean) => ({ path: 'MEMORY.md', layer: 'index' as const, whole: false, before: [], after: [], changed });
    expect(planSummary({ project: '/r', digest: 'd', files: [file(false)] })).toBe('Everything is already as the map would write it.');
    expect(planSummary({ project: '/r', digest: 'd', files: [file(true), file(false)] })).toBe('Writes 1 file, 1 already as planned. Only what sits inside Memnox\'s fenced blocks changes.');
    expect(keepList(' the release branch\n\n  tests first ')).toEqual(['the release branch', 'tests first']);
  });

  it('says what a saved or partial workspace picture leaves out, and nothing for a whole live one', () => {
    expect(workspaceGraphLine({ source: 'live', withheld: 0, truncated: false })).toBeUndefined();
    expect(workspaceGraphLine({ source: 'saved', fallback: 'not-joined', withheld: 0, truncated: false })).toBe('This computer is not in a workspace, so only what it keeps itself is drawn.');
    expect(workspaceGraphLine({ source: 'live', withheld: 1200, truncated: true })).toBe("1,200 kept back by this computer's clearance, cut at the most the cloud draws at once.");
  });
});

describe('the layers as the runtime reads and writes them', () => {
  const view: MemoryLayersView = { projects: [project()], value: {} };
  const plan: MemoryLayersPlan = { project: '/r/acme', digest: 'abc', files: [{ path: 'MEMORY.md', layer: 'index', whole: true, before: [], after: ['# Memory'], changed: true }] };

  it('previews without writing, and writes only the plan shown, by its digest', async () => {
    const daemon = new ScriptedDaemon({
      'memory-layers': (request) => [{ id: request.id, ok: true, memoryLayers: view }],
      'session-cost': (request) => [{ id: request.id, ok: true, sessionCost: cost({}) }],
      'memory-layers-plan': (request) => [{ id: request.id, ok: true, memoryLayersPlan: plan }],
      'memory-layers-apply': (request) => [{ id: request.id, ok: true, memoryLayersApplied: { written: ['MEMORY.md'], unchanged: [] }, memoryLayers: view }],
    });
    const memory = new Memory(daemon, new RequestIds());
    await memory.refreshLayers();
    expect(memory.layers).toEqual(view);
    expect(memory.sessionCost?.coldReloads).toBe(1);
    expect(await memory.previewLayers('/r/acme', ['tests first'])).toBeUndefined();
    expect(memory.plan).toEqual(plan);
    expect(daemon.sent('memory-layers-apply')).toEqual([]);
    expect(await memory.confirmLayers()).toEqual({ kind: 'done', note: 'Wrote MEMORY.md.' });
    expect(daemon.sent('memory-layers-apply')[0]).toMatchObject({ memoryLayersProject: '/r/acme', memoryKeep: ['tests first'], memoryLayersDigest: 'abc' });
    expect(memory.plan).toBeUndefined();
  });

  it('says a runtime that cannot read the layers, and a confirm with no plan shown', async () => {
    const memory = new Memory(new ScriptedDaemon(), new RequestIds());
    await memory.refreshLayers();
    expect(memory.layersUnreadable).toBe(true);
    expect(await memory.previewLayers('/r/acme', [])).toBe('The runtime is not answering.');
    expect(await memory.confirmLayers()).toEqual({ kind: 'failed', why: 'There is no plan to confirm.' });
  });

  it('reads every status at once for the brain', async () => {
    const daemon = new ScriptedDaemon({
      'memory-facts': (request) => [{ id: request.id, ok: true, memoryFacts: { items: request.memoryStatus === 'verified' ? [fact('one')] : [], more: 0 } }],
    });
    const memory = new Memory(daemon, new RequestIds());
    await memory.refreshEverything();
    expect(memory.everything?.map((item) => item.id)).toEqual(['one']);
    expect(daemon.sent('memory-facts').map((request) => request.memoryStatus)).toEqual(['verified', 'candidate', 'conflicting', 'outdated', 'rejected', 'superseded']);
  });
});

function fact(id: string, extra: Partial<MemoryItemView> = {}): MemoryItemView {
  return {
    id,
    kind: 'fact',
    statement: `Fact ${id}`,
    subject: 'releases',
    status: 'verified',
    scope: 'personal',
    origin: 'extracted',
    tainted: false,
    evidence: [{ ref: 'notes/ops.md#Releases', document: 'notes/ops.md', source: 'Notes', stale: false }],
    createdAt: '2026-10-30T10:00:00Z',
    ...extra,
  };
}

const notes: MemorySourceView = {
  id: 'src_1',
  kind: 'markdown',
  name: 'Notes',
  location: '/notes',
  trust: 'trusted',
  scope: 'personal',
  watched: true,
  counts: { candidate: 0, verified: 1, conflicting: 0, outdated: 0, rejected: 0 },
};

describe('the brain built from this computer', () => {
  it('joins each fact to the document its evidence names, in the area of its source', () => {
    const { map, input } = localArmsInput({ items: [fact('one'), fact('two', { status: 'candidate' })], sources: [notes] });
    const document = LOCAL_ARMS_IDS.document('Notes', 'notes/ops.md');
    expect(map.nodes.map((node) => node.id)).toEqual([LOCAL_ARMS_IDS.fact('one'), document, LOCAL_ARMS_IDS.fact('two')]);
    expect(map.edges.map((edge) => [edge.from, edge.to])).toEqual([
      [LOCAL_ARMS_IDS.fact('one'), document],
      [LOCAL_ARMS_IDS.fact('two'), document],
    ]);
    expect(map.nodes.find((node) => node.id === LOCAL_ARMS_IDS.fact('two'))?.status).toBe('recent');
    expect(input.timeOf(LOCAL_ARMS_IDS.fact('one'))).toBe(Date.parse('2026-10-30T10:00:00Z'));
    const model = armsModel(input);
    expect(model.sectors.map((sector) => sector.label)).toEqual(['Notes']);
    expect(model.memories).toBe(2);
  });

  it('puts a project\'s CLAUDE.md at the centre and its MEMORY.md as an area of its own', () => {
    const layers: MemoryLayersView = {
      projects: [
        project({
          index: { path: 'MEMORY.md', present: true, lines: 3, unlinked: 0 },
          routers: [{ agent: 'claude-code', path: 'CLAUDE.md', present: true, lines: 10, chars: 100, departments: [], routed: 0 }],
        }),
      ],
      value: {},
    };
    const { input } = localArmsInput({ layers, skills: [{ name: 'release' }], rules: [{ name: 'no-force-push', effect: 'deny' }], servers: [{ name: 'linear' }] });
    const model = armsModel(input);
    const core = model.items.find((item) => item.id === AGENTS_HUB_ID);
    expect(core?.label).toBe('CLAUDE.md');
    expect(model.sectors.some((sector) => sector.key === MEMORY_INDEX)).toBe(true);
    expect(model.items.filter((item) => item.layer === 'skill' && item.hub !== true).map((item) => item.label)).toEqual(['release']);
    expect(model.items.filter((item) => item.layer === 'rule').map((item) => item.effect)).toEqual(['deny']);
    expect(model.items.filter((item) => item.layer === 'app').map((item) => item.label)).toEqual(['linear']);
  });

  it('draws nothing for nothing', () => {
    expect(armsModel(localArmsInput({}).input).empty).toBe(true);
  });

  it('folds the workspace graph in, its tools as the areas and its decisions as memory', () => {
    const { map, input } = localArmsInput({
      workspace: {
        nodes: [
          { id: 'slack', kind: 'source', label: 'Slack', tool: 'slack', weight: 2 },
          { id: 'd1', kind: 'decision', label: 'Ship Tuesdays', statement: 'Ship on Tuesdays', tool: 'slack', weight: 1 },
          { id: 'p1', kind: 'person', label: 'Ada', weight: 1 },
        ],
        links: [
          { from: 'slack', to: 'd1', kind: 'carries' },
          { from: 'p1', to: 'd1', kind: 'said' },
        ],
        withheld: 0,
        truncated: false,
        source: 'saved',
        fallback: 'not-joined',
      },
    });
    expect(map.nodes.map((node) => node.kind)).toEqual(['memory', 'person']);
    expect(map.edges.map((edge) => edge.kind)).toEqual(['said']);
    expect(input.apps).toEqual([{ slug: 'slack', name: 'Slack' }]);
    expect(armsModel(input).sectors.map((sector) => sector.label)).toContain('Slack');
  });
});
