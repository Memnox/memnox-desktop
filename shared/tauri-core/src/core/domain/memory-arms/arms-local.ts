import type { DaemonResponse, MemoryItemView, MemorySourceView } from '@memnox/core/wire';
import { systemName, type MemoryMap, type MemoryMapEdge, type MemoryMapNode, type MemoryStatus } from './arms-node';
import type { ArmsInput } from './arms-model';
import type { MemoryLayersView } from '../memory-layers-lines';

/**
 * The brain map's record built from what this computer's daemon answered: the facts memory holds with the documents
 * their evidence cites, the instruction and MEMORY.md files each project's layers name, the workspace's own graph as
 * this machine last pulled it, and the skills, rules and servers beside them. **Every line is a field on a record**:
 * a fact joins the document its evidence names, a workspace link is the cloud's own, and nothing is guessed from words.
 */

export type WorkspaceGraphView = NonNullable<DaemonResponse['workspaceGraph']>;

export interface LocalArmsReads {
  readonly items?: readonly MemoryItemView[];
  readonly sources?: readonly MemorySourceView[];
  readonly layers?: MemoryLayersView;
  readonly workspace?: WorkspaceGraphView;
  readonly skills?: readonly { readonly name: string; readonly description?: string }[];
  readonly rules?: readonly { readonly name: string; readonly effect?: string }[];
  /** The MCP servers the hub holds, drawn as tiles round the outside as the Mac draws them. */
  readonly servers?: readonly { readonly name: string; readonly description?: string }[];
}

/** The area a source's facts are drawn in, by what kind of source it is. */
const AREA_OF_KIND: Readonly<Record<MemorySourceView['kind'], string>> = {
  obsidian: 'obsidian',
  markdown: 'notes',
  instructions: 'instructions',
  'notion-export': 'notion',
  supermemory: 'supermemory',
  mcp: 'mcp',
  'app-calls': 'apps',
  'mcp-calls': 'mcp',
};

/** A local status in the four the map draws: settled, recent, worth acting on, and no longer told. */
const STATUS_OF: Readonly<Record<MemoryItemView['status'], MemoryStatus>> = {
  verified: 'settled',
  candidate: 'recent',
  conflicting: 'expiring',
  outdated: 'forgotten',
  rejected: 'forgotten',
  superseded: 'forgotten',
};

export const LOCAL_ARMS_IDS = {
  fact: (id: string) => `fact:${id}`,
  document: (source: string, document: string) => `doc:${source}/${document}`,
  layer: (project: string, path: string) => `layer:${project}/${path}`,
  workspace: (id: string) => `wsm:${id}`,
} as const;

/** The area a source's facts sit in: a connected app by its own slug, anything else by its kind. */
export function areaOfSource(source: Pick<MemorySourceView, 'kind' | 'name'> | undefined): string | undefined {
  if (source === undefined) return undefined;
  if (source.kind === 'app-calls') return source.name.trim().toLowerCase().replace(/\s+/g, '') || AREA_OF_KIND['app-calls'];
  return AREA_OF_KIND[source.kind];
}

function sourceOf(sources: readonly MemorySourceView[], named: string): MemorySourceView | undefined {
  return sources.find((source) => source.name === named || source.id === named);
}

function timeOfItem(item: MemoryItemView): number | undefined {
  const at = Date.parse(item.decidedAt ?? item.createdAt);
  return Number.isFinite(at) ? at : undefined;
}

/** The workspace's kinds in the map's own: a decision or candidate is a memory, a tool is the area, a bot is an app. */
function workspaceKind(kind: string): MemoryMapNode['kind'] | undefined {
  switch (kind) {
    case 'decision':
    case 'candidate':
      return 'memory';
    case 'document':
      return 'document';
    case 'passage':
      return 'passage';
    case 'conversation':
      return 'conversation';
    case 'person':
    case 'bot':
      return 'person';
    case 'group':
      return 'group';
    case 'policy':
      return 'policy';
    default:
      // A source is a tool, which the map wears as the area and the tile rather than a node of its own.
      return undefined;
  }
}

/** The whole record and when each node was dated, from every read that answered. */
export function localMemoryMap(reads: LocalArmsReads): { map: MemoryMap; times: ReadonlyMap<string, number> } {
  const nodes = new Map<string, MemoryMapNode>();
  const edges: MemoryMapEdge[] = [];
  const times = new Map<string, number>();
  const sources = reads.sources ?? [];
  const link = (from: string, to: string, kind: string) => edges.push({ id: `${from}|${to}|${kind}`, from, to, kind });

  for (const project of reads.layers?.projects ?? []) {
    const index = project.index;
    if (index.present) {
      const id = LOCAL_ARMS_IDS.layer(project.path, index.path);
      nodes.set(id, { id, kind: 'document', label: `${project.name}/${index.path}`, detail: `${index.lines} lines read in every chat`, href: `${project.path}/${index.path}`, origin: 'uploaded', system: 'instructions' });
    }
    for (const router of project.routers) {
      if (!router.present) continue;
      const id = LOCAL_ARMS_IDS.layer(project.path, router.path);
      if (nodes.has(id)) continue;
      nodes.set(id, { id, kind: 'document', label: `${project.name}/${router.path}`, detail: `The router ${router.agent} reads`, href: `${project.path}/${router.path}`, origin: 'uploaded', system: 'instructions' });
    }
  }

  for (const item of reads.items ?? []) {
    const id = LOCAL_ARMS_IDS.fact(item.id);
    const first = item.evidence[0];
    const area = areaOfSource(first === undefined ? undefined : sourceOf(sources, first.source));
    nodes.set(id, {
      id,
      kind: 'memory',
      label: item.statement,
      statement: item.statement,
      status: STATUS_OF[item.status],
      detail: item.subject,
      ...(area === undefined ? {} : { system: area }),
    });
    const time = timeOfItem(item);
    if (time !== undefined) times.set(id, time);
    for (const evidence of item.evidence) {
      const source = sourceOf(sources, evidence.source);
      const documentId = LOCAL_ARMS_IDS.document(evidence.source, evidence.document);
      if (!nodes.has(documentId)) {
        const system = areaOfSource(source);
        nodes.set(documentId, {
          id: documentId,
          kind: 'document',
          label: evidence.document,
          detail: evidence.ref,
          ...(evidence.url === undefined ? {} : { href: evidence.url }),
          origin: evidence.url === undefined ? 'uploaded' : 'linked',
          ...(system === undefined ? {} : { system }),
        });
      }
      link(id, documentId, 'derives');
    }
    if (item.duplicateOf !== undefined) link(id, LOCAL_ARMS_IDS.fact(item.duplicateOf.id), 'updates');
  }

  const workspace = reads.workspace;
  if (workspace !== undefined) {
    const tools = new Map(workspace.nodes.filter((node) => node.kind === 'source').map((node) => [node.id, node.tool ?? node.label.toLowerCase()]));
    for (const node of workspace.nodes) {
      const kind = workspaceKind(node.kind);
      if (kind === undefined) continue;
      const id = LOCAL_ARMS_IDS.workspace(node.id);
      const status: MemoryStatus | undefined = node.kind === 'candidate' || node.status === 'candidate' ? 'recent' : kind === 'memory' ? 'settled' : undefined;
      nodes.set(id, {
        id,
        kind,
        label: node.statement ?? node.label,
        ...(node.statement === undefined ? {} : { statement: node.statement }),
        ...(status === undefined ? {} : { status }),
        ...(node.excerpt === undefined ? {} : { excerpt: node.excerpt }),
        ...(node.href === undefined ? {} : { href: node.href }),
        ...(node.tool === undefined ? {} : { system: node.tool }),
        ...(node.saidBy === undefined ? {} : { detail: `Said by ${node.saidBy}` }),
        ...(node.kind === 'bot' ? { app: true } : {}),
        ...(node.count === undefined ? {} : { repeats: node.count }),
        origin: 'connected',
      });
      const at = node.at === undefined ? Number.NaN : Date.parse(node.at);
      if (Number.isFinite(at)) times.set(id, at);
    }
    for (const line of workspace.links) {
      // A line from a tool is said by the area its node already sits in, so only lines between drawn nodes stay.
      if (tools.has(line.from) || tools.has(line.to)) continue;
      link(LOCAL_ARMS_IDS.workspace(line.from), LOCAL_ARMS_IDS.workspace(line.to), line.kind);
    }
  }

  const drawn = new Set(nodes.keys());
  return { map: { nodes: [...nodes.values()], edges: edges.filter((edge) => drawn.has(edge.from) && drawn.has(edge.to)) }, times };
}

/** The apps round the outside: each connected app memory reads, each tool the workspace pulled from, and each hub server. */
export function localApps(reads: LocalArmsReads, map: MemoryMap): { slug: string; name: string }[] {
  const apps = new Map<string, string>();
  for (const source of reads.sources ?? []) {
    if (source.kind !== 'app-calls') continue;
    const slug = areaOfSource(source);
    if (slug !== undefined) apps.set(slug, source.name);
  }
  for (const node of reads.workspace?.nodes ?? []) {
    if (node.kind !== 'source') continue;
    const slug = node.tool ?? node.label.toLowerCase();
    apps.set(slug, systemName(slug));
  }
  for (const server of reads.servers ?? []) apps.set(`mcp:${server.name}`, server.name);
  for (const node of map.nodes) {
    if (node.system === undefined || apps.has(node.system) || node.origin !== 'connected') continue;
    apps.set(node.system, systemName(node.system));
  }
  return [...apps.entries()].map(([slug, name]) => ({ slug, name }));
}

/** Everything the brain model reads, from the daemon's answers alone. */
export function localArmsInput(reads: LocalArmsReads): { input: ArmsInput; map: MemoryMap } {
  const { map, times } = localMemoryMap(reads);
  return {
    map,
    input: {
      nodes: map.nodes,
      edges: map.edges,
      skills: (reads.skills ?? []).map((skill) => ({ name: skill.name, ...(skill.description === undefined ? {} : { description: skill.description }) })),
      rules: (reads.rules ?? []).map((rule) => ({ name: rule.name, ...(rule.effect === undefined ? {} : { effect: rule.effect }) })),
      apps: localApps(reads, map),
      timeOf: (id) => times.get(id),
    },
  };
}
