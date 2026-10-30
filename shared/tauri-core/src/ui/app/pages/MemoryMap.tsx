import type { MemoryItemView, MemorySourceView } from '@memnox/core/wire';
import { BookOpen, FileText, Gavel } from 'lucide-react';
import { useMemo } from 'react';
import { MEMORY_LINK, MEMORY_MAP_NODE, MEMORY_MAP_PX, carriedWith, memoryMap, walkOrder, type MemoryLinkKind, type MemoryMapEdge, type MemoryMapNode } from '../../../core/domain/memory-map';
import { kindWord, sourceKindLabel, statusWord } from '../../../core/domain/memory-lines';
import { EFFECT_WORDS, effectTone, isEffect } from '../../../core/domain/studio-lines';
import { SurfaceCanvas, type EdgeInk } from '../surface/SurfaceCanvas';
import type { Tone } from '../widgets';

/** Each tone as the ink a mark wears, the same colours the pills use. */
const TONE_INK: Record<Tone, string> = {
  good: 'var(--mx-success)',
  attention: 'var(--mx-warm)',
  bad: 'var(--mx-destructive)',
  quiet: 'var(--mx-faint)',
};

/** A line's colour, its dash and the words for it; each is a field on the record, as the console's legend says. */
const LINK_INK: Record<MemoryLinkKind, { label: string; meaning: string; stroke: string; dash?: string }> = {
  [MEMORY_LINK.CITES]: { label: 'Cites', meaning: 'Its evidence is a passage of this document', stroke: 'var(--mx-warm)' },
  [MEMORY_LINK.HELD_IN]: { label: 'Read from', meaning: 'The document was read out of this source', stroke: 'var(--mx-muted)' },
  [MEMORY_LINK.GOVERNS]: { label: 'Governs', meaning: 'Confirming it raises this rule', stroke: 'var(--color-primary)' },
  [MEMORY_LINK.RESTATES]: { label: 'Restates', meaning: 'Says again what an earlier fact said', stroke: 'var(--mx-violet)', dash: '5 4' },
};

/** A passage that changed since it was read is drawn broken, as the list strikes it through. */
const STALE_DASH = '2 5';
/** Facts no agent is told any more stay on the map, faintly, because the history is the point. */
const QUIET_STATUSES: ReadonlySet<MemoryItemView['status']> = new Set(['outdated', 'rejected', 'superseded']);

function inkFor(edge: MemoryMapEdge, lit: boolean): EdgeInk {
  const ink = LINK_INK[edge.kind];
  const dash = edge.stale === true ? STALE_DASH : ink.dash;
  return { stroke: ink.stroke, width: lit ? 2 : 1.5, opacity: lit ? 1 : 0.7, arrow: edge.kind !== MEMORY_LINK.HELD_IN, ...(dash === undefined ? {} : { dash }) };
}

/**
 * The memory listed above, drawn as a map: each fact beside the document its evidence cites, each
 * document in its source, and each rule a fact governs. Picking a node opens it in the details.
 */
export function MemoryMapView({
  items,
  sources,
  selected,
  select,
}: {
  items: readonly MemoryItemView[];
  sources: readonly MemorySourceView[];
  selected: string | undefined;
  select: (node: MemoryMapNode | undefined) => void;
}) {
  const map = useMemo(() => memoryMap(items, sources, sourceKindLabel), [items, sources]);
  const order = useMemo(() => walkOrder(map), [map]);
  return (
    <SurfaceCanvas
      label="Memory map"
      nodes={map.nodes}
      edges={map.edges}
      order={order}
      selected={selected}
      onSelect={(id) => select(id === undefined ? undefined : map.nodes.find((node) => node.id === id))}
      inkFor={inkFor}
      carries={(id) => carriedWith(map, id)}
      mark={(node, state) => <Mark node={node} selected={state.selected} />}
      legend={<Legend />}
    />
  );
}

function Mark({ node, selected }: { node: MemoryMapNode; selected: boolean }) {
  switch (node.kind) {
    case MEMORY_MAP_NODE.MEMORY:
      return <MemoryCard node={node} selected={selected} />;
    case MEMORY_MAP_NODE.DOCUMENT:
      return <DocumentCard node={node} selected={selected} />;
    case MEMORY_MAP_NODE.RULE:
      return <RuleCard node={node} selected={selected} />;
    case MEMORY_MAP_NODE.SOURCE:
      return <SourceDisc node={node} selected={selected} />;
  }
}

const CARD = 'relative flex flex-col justify-center overflow-hidden rounded-xl border bg-card text-left shadow-[0_8px_24px_rgb(0_0_0/0.1)] transition-colors';
const PICKED = 'border-foreground ring-2 ring-primary/40';

/** A fact written on the map, its status a rail down the left, since the card's border tells it from the ground. */
function MemoryCard({ node, selected }: { node: MemoryMapNode; selected: boolean }) {
  const status = node.status === undefined ? undefined : statusWord(node.status);
  const ink = TONE_INK[status === undefined ? 'quiet' : status.tone];
  const quiet = node.status !== undefined && QUIET_STATUSES.has(node.status);
  return (
    <span
      className={`${CARD} pr-2.5 pl-3.5 ${selected ? PICKED : 'hover:border-foreground'} ${quiet ? 'opacity-60' : ''}`}
      style={{ width: MEMORY_MAP_PX.memory.width, height: MEMORY_MAP_PX.memory.height, ...(selected ? {} : { borderColor: `color-mix(in oklab, ${ink} 45%, var(--mx-border))` }) }}
    >
      <span aria-hidden className="absolute inset-y-0 left-0 w-1" style={{ background: ink }} />
      <span className="flex items-center gap-1.5">
        <span className="min-w-0 truncate text-[10px] tracking-[0.12em] uppercase" style={{ color: ink }}>
          {node.memoryKind === undefined ? 'Memory' : kindWord(node.memoryKind)}
        </span>
        {node.tainted === true && <span className="shrink-0 text-[10px] text-warm">Untrusted</span>}
      </span>
      <span className="line-clamp-2 text-label leading-tight font-medium text-foreground">{node.label}</span>
    </span>
  );
}

function DocumentCard({ node, selected }: { node: MemoryMapNode; selected: boolean }) {
  return (
    <span className={`${CARD} px-3 ${selected ? PICKED : 'border-panel-edge hover:border-foreground'}`} style={{ width: MEMORY_MAP_PX.document.width, height: MEMORY_MAP_PX.document.height }}>
      <span className="flex items-center gap-1 text-[10px] text-warm">
        <FileText size={11} className="shrink-0" aria-hidden />
        <span className="truncate">{node.detail ?? 'Document'}</span>
      </span>
      <span className="truncate text-label font-medium text-foreground">{node.label}</span>
    </span>
  );
}

function RuleCard({ node, selected }: { node: MemoryMapNode; selected: boolean }) {
  const effect = node.detail;
  const known = effect !== undefined && isEffect(effect);
  const ink = TONE_INK[known ? effectTone(effect) : 'quiet'];
  return (
    <span
      className={`${CARD} px-3 ${selected ? PICKED : 'hover:border-foreground'}`}
      style={{ width: MEMORY_MAP_PX.rule.width, height: MEMORY_MAP_PX.rule.height, ...(selected ? {} : { borderColor: `color-mix(in oklab, ${ink} 45%, var(--mx-border))` }) }}
    >
      <span className="flex items-center gap-1 text-[10px] tracking-[0.12em] uppercase" style={{ color: ink }}>
        <Gavel size={11} className="shrink-0" aria-hidden />
        {known ? `Rule, ${EFFECT_WORDS[effect].title}` : 'Rule'}
      </span>
      <span className="line-clamp-2 text-label leading-tight font-medium text-foreground">{node.label}</span>
    </span>
  );
}

/** A source is a disc with its name hung below, since it is a place rather than a sentence. */
function SourceDisc({ node, selected }: { node: MemoryMapNode; selected: boolean }) {
  return (
    <span
      className={`flex items-center justify-center rounded-full border bg-background shadow-[0_8px_24px_rgb(0_0_0/0.1)] transition-colors ${selected ? PICKED : 'border-panel-edge hover:border-foreground'}`}
      style={{ width: MEMORY_MAP_PX.source, height: MEMORY_MAP_PX.source }}
    >
      <BookOpen size={18} className="text-primary" aria-hidden />
    </span>
  );
}

/** How to read the lines and the rails, folded so it never covers the drawing until asked. */
function Legend() {
  return (
    <details className="group rounded-lg border border-panel-edge bg-card shadow-[0_8px_24px_rgb(0_0_0/0.1)]">
      <summary className="mx-focus cursor-pointer list-none px-3 py-2 text-label font-medium tracking-[0.14em] text-muted uppercase select-none">How to read the map</summary>
      <div className="flex flex-col gap-3 px-3 pb-3">
        <ul className="flex flex-col gap-1.5">
          {Object.values(LINK_INK).map((ink) => (
            <li key={ink.label} className="flex items-start gap-2 text-meta">
              <svg width={22} height={8} className="mt-1.5 shrink-0" aria-hidden>
                <line x1={1} y1={4} x2={21} y2={4} stroke={ink.stroke} strokeWidth={2} strokeLinecap="round" {...(ink.dash === undefined ? {} : { strokeDasharray: ink.dash })} />
              </svg>
              <span>
                <span className="font-medium text-foreground">{ink.label}</span>
                <span className="text-muted">{`, ${ink.meaning.toLowerCase()}`}</span>
              </span>
            </li>
          ))}
          <li className="flex items-start gap-2 text-meta">
            <svg width={22} height={8} className="mt-1.5 shrink-0" aria-hidden>
              <line x1={1} y1={4} x2={21} y2={4} stroke="var(--mx-warm)" strokeWidth={2} strokeLinecap="round" strokeDasharray={STALE_DASH} />
            </svg>
            <span className="text-muted">Broken where the passage changed since it was read</span>
          </li>
        </ul>
        <p className="text-meta text-muted">The rail down a fact is where it stands: green verified, amber waiting, red in conflict, grey no longer told to agents. A fact citing nothing stands alone.</p>
      </div>
    </details>
  );
}
