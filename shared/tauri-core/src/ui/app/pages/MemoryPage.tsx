import type { MemoryEvidenceView, MemoryItemView, MemorySourceView } from '@memnox/core/wire';
import { BookOpen, Brain, FileText, Link2, List, Network, Plus, RefreshCw, Trash2 } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { MemoryOutcome } from '../../../core/application/memory';
import type { WidthClass } from '../../../core/domain/destinations';
import {
  MEMORY_FILTERS,
  MEMORY_SCOPES,
  confidenceLine,
  decidedLine,
  evidenceLine,
  evidenceTarget,
  filePressLine,
  keyLine,
  kindWord,
  lastReadLine,
  moreLine,
  originLine,
  readSummaryLine,
  searchModeLine,
  sourceCountsLine,
  sourceKindLabel,
  statusWord,
  TAINTED_LINE,
  trustWord,
  type MemoryScopeName,
  type MemoryStatusName,
} from '../../../core/domain/memory-lines';
import { KitButton, SearchField } from '../../settings/kit';
import { openOrCopy } from '../../settings/host';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { AddMemorySourceDialog } from './MemorySourceDialog';
import { MemoryMapView } from './MemoryMap';
import { memoryMapIds, MEMORY_MAP_NODE, type MemoryMapNode } from '../../../core/domain/memory-map';
import { CardGrid, EmptyState, Inspector, Panel, ReadFailed, Row, ScopeChip, Section, StatusWord } from '../widgets';
import { memoryScope } from '../../../core/domain/scope-lines';
import { useInspectorHost, usePicked } from '../inspector-host';

const CHIP = 'mx-focus cursor-pointer inline-flex h-8 items-center rounded-lg border px-3 text-body-sm';
const chip = (on: boolean) => `${CHIP} ${on ? 'border-primary/45 bg-primary/[0.07] font-medium text-foreground' : 'border-panel-edge bg-card text-muted hover:bg-hover hover:text-foreground'}`;

/** Whether memory is read as a list or drawn as a map, remembered for the next visit. */
type MemoryView = 'list' | 'map';
const VIEW_KEY = 'memnox.memory.view';
const VIEWS: readonly { view: MemoryView; label: string; icon: typeof List }[] = [
  { view: 'list', label: 'List', icon: List },
  { view: 'map', label: 'Map', icon: Network },
];

/** How long typing rests before the search is asked, so each key is not a request. */
const SEARCH_REST_MS = 300;

/** A press's outcome as the line under it says it. */
export function memoryNote(outcome: MemoryOutcome): string {
  return outcome.kind === 'failed' ? outcome.why : outcome.note;
}

/**
 * What this computer learned, read three ways from one record: the list by status and scope, one fact with
 * the evidence it was read from, and the sources it came out of. A statement is shown whole, as written.
 */
export function MemoryPage({ parts, width }: { parts: SettingsParts; width: WidthClass }) {
  const { memory } = parts;
  useObserved(memory);
  const [status, setStatus] = useState<MemoryStatusName>('verified');
  const [scope, setScope] = useState<MemoryScopeName | undefined>(undefined);
  const [query, setQuery] = useState('');
  const [chosen, choose] = usePicked();
  const linked = useInspectorHost().item;
  const [note, setNote] = useState<string | undefined>(undefined);
  const [view, setView] = useState<MemoryView>(() => (localStorage.getItem(VIEW_KEY) === 'map' ? 'map' : 'list'));
  // A document or a source picked on the map, which is not an item and so is not the picked id.
  const [place, setPlace] = useState<MemoryMapNode | undefined>(undefined);
  const show = (next: MemoryView) => {
    localStorage.setItem(VIEW_KEY, next);
    setView(next);
  };
  const pickNode = (node: MemoryMapNode | undefined) => {
    setPlace(node === undefined || node.item !== undefined ? undefined : node);
    choose(node === undefined ? undefined : node.item);
  };
  useEffect(() => {
    void memory.refreshSources();
    // An item a link names reopens whatever its status became, on the list that now holds it.
    if (linked !== undefined)
      void memory.reveal(linked).then((found) => {
        if (found !== undefined && MEMORY_FILTERS.some((each) => each.status === found)) setStatus(found);
      });
  }, []);
  // A signature on the island settles a rule, so the list is read again.
  useEffect(() => parts.host.onHomeStale?.(() => void memory.show(memory.filter)), []);
  useEffect(() => {
    const handle = setTimeout(() => void memory.show({ status, ...(scope === undefined ? {} : { scope }), ...(query.trim() === '' ? {} : { query }) }), query === '' ? 0 : SEARCH_REST_MS);
    return () => clearTimeout(handle);
  }, [status, scope, query]);

  const listed = memory.facts;
  const picked = listed?.items.find((item) => item.id === chosen);
  return (
    <div className="flex min-h-0">
      <div className="flex min-w-0 flex-1 flex-col gap-7">
        {note !== undefined && (
          <p role="status" className="rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote text-foreground">
            {note}
          </p>
        )}
        <Section title="What your agents know">
          <div className="flex flex-wrap items-center gap-2">
            <div className="w-full max-w-[300px] min-w-[180px] flex-1">
              <SearchField value={query} placeholder="Search memory" onChange={setQuery} />
            </div>
            <span className="flex-1" />
            <div className="inline-flex items-center gap-1 rounded-lg border border-panel-edge bg-card p-1" role="group" aria-label="Show memory as">
              {VIEWS.map((each) => (
                <button
                  key={each.view}
                  type="button"
                  aria-pressed={view === each.view}
                  onClick={() => show(each.view)}
                  className={`mx-focus inline-flex h-7 cursor-pointer items-center gap-1.5 rounded-md px-3 text-body-sm transition-colors ${view === each.view ? 'bg-active font-medium text-foreground' : 'text-muted hover:text-foreground'}`}
                >
                  <each.icon size={14} aria-hidden />
                  {each.label}
                </button>
              ))}
            </div>
            <div className="flex gap-1.5" role="group" aria-label="Scope">
              <button type="button" className={chip(scope === undefined)} aria-pressed={scope === undefined} onClick={() => setScope(undefined)}>
                Both
              </button>
              {MEMORY_SCOPES.map((each) => (
                <button key={each.scope} type="button" className={chip(scope === each.scope)} aria-pressed={scope === each.scope} onClick={() => setScope(each.scope)}>
                  {each.label}
                </button>
              ))}
            </div>
          </div>
          {query.trim() === '' ? (
            <div className="flex flex-wrap gap-1.5" role="group" aria-label="Status">
              {MEMORY_FILTERS.map((each) => (
                <button key={each.status} type="button" className={chip(status === each.status)} aria-pressed={status === each.status} onClick={() => setStatus(each.status)}>
                  {each.label}
                </button>
              ))}
            </div>
          ) : (
            <p className="text-footnote text-muted">
              {memory.search === undefined ? 'Searching every status for these words.' : `${searchModeLine(memory.search.mode)}, over every status.`}
              {memory.search?.note !== undefined && <span className="block">{memory.search.note}</span>}
            </p>
          )}
          {memory.unreadable.facts && <ReadFailed what="what was learned" retry={() => void memory.show(memory.filter)} />}
          {listed !== undefined && listed.items.length === 0 && (
            <EmptyState icon={Brain} title={query.trim() === '' ? `Nothing ${statusWord(status).word.toLowerCase()} here` : 'Nothing learned says that'} body="Add a source below and Memnox reads it with your own agent. What it finds waits in Learn until you confirm it." />
          )}
          {listed !== undefined && listed.items.length > 0 && view === 'map' && (
            <MemoryMapView items={listed.items} sources={memory.sources ?? []} selected={place?.id ?? chosen} select={pickNode} />
          )}
          {listed !== undefined && listed.items.length > 0 && view === 'list' && (
            <Panel>
              {listed.items.map((item) => (
                <Row
                  key={item.id}
                  chosen={item.id === chosen}
                  onClick={() => choose(item.id)}
                  title={<span className="whitespace-pre-wrap">{item.statement}</span>}
                  caption={`${kindWord(item.kind)} · ${item.evidence.length === 1 ? '1 piece of evidence' : `${item.evidence.length} pieces of evidence`}`}
                  trailing={
                    <>
                      <ScopeChip scope={memoryScope(item)} />
                      {item.tainted && <StatusWord tone="attention">Untrusted source</StatusWord>}
                      <StatusWord tone={statusWord(item.status).tone}>{statusWord(item.status).word}</StatusWord>
                    </>
                  }
                />
              ))}
            </Panel>
          )}
          {listed !== undefined && moreLine(listed.more) !== undefined && <p className="text-footnote text-muted">{moreLine(listed.more)}</p>}
        </Section>
        <MemorySources parts={parts} said={setNote} />
      </div>
      {place !== undefined && (
        <Inspector title={place.kind === MEMORY_MAP_NODE.DOCUMENT ? 'Document' : 'Source'} width={width} close={() => setPlace(undefined)}>
          <PlaceDetail parts={parts} place={place} items={listed?.items ?? []} open={(id) => pickNode({ ...place, item: id })} />
        </Inspector>
      )}
      {picked !== undefined && (
        <Inspector title={kindWord(picked.kind)} width={width} close={() => choose(undefined)} item={picked.id}>
          <FactDetail
            parts={parts}
            item={picked}
            forget={() =>
              void memory.forget(picked.id).then((outcome) => {
                setNote(memoryNote(outcome));
                if (outcome.kind !== 'failed') choose(undefined);
              })
            }
          />
        </Inspector>
      )}
    </div>
  );
}

/** One fact whole: its words as written, where it stands, who settled it, and every passage it was read from. */
function FactDetail({ parts, item, forget }: { parts: SettingsParts; item: MemoryItemView; forget: () => void }) {
  const { memory } = parts;
  const [sure, setSure] = useState(false);
  const decided = decidedLine(item, Date.now());
  const confidence = confidenceLine(item.extractorConfidence);
  return (
    <div className="flex flex-col gap-4">
      <p className="whitespace-pre-wrap text-body text-foreground">{item.statement}</p>
      <div className="flex flex-wrap gap-3">
        <StatusWord tone={statusWord(item.status).tone}>{statusWord(item.status).word}</StatusWord>
        {item.tainted && <StatusWord tone="attention">{TAINTED_LINE}</StatusWord>}
      </div>
      {item.rule !== undefined && <p className="text-footnote text-foreground">{`What it governs: ${item.rule.sentence}`}</p>}
      <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-footnote">
        <dt className="text-muted">About</dt>
        <dd className="min-w-0 break-words text-foreground">{item.subject}</dd>
        <dt className="text-muted">Kept</dt>
        <dd className="text-foreground">{item.scope === 'project' ? `With the project${item.project === undefined ? '' : ` ${item.project}`}` : 'In your personal memory'}</dd>
        <dt className="text-muted">From</dt>
        <dd className="text-foreground">{originLine(item)}</dd>
        {confidence !== undefined && (
          <>
            <dt className="text-muted">Extractor</dt>
            <dd className="text-foreground">{confidence}</dd>
          </>
        )}
        {decided !== undefined && (
          <>
            <dt className="text-muted">Settled</dt>
            <dd className="text-foreground">{decided}</dd>
          </>
        )}
      </dl>
      <Evidence parts={parts} evidence={item.evidence} />
      <div className="flex flex-wrap items-center gap-2 border-t border-panel-edge pt-3">
        {sure ? (
          <>
            <span className="flex-1 text-footnote text-muted">Forgetting deletes it and its evidence for good.</span>
            <KitButton onClick={() => setSure(false)}>Keep it</KitButton>
            <KitButton icon={Trash2} disabled={memory.busy === item.id} onClick={forget}>
              Forget
            </KitButton>
          </>
        ) : (
          <KitButton icon={Trash2} onClick={() => setSure(true)}>
            Forget
          </KitButton>
        )}
      </div>
    </div>
  );
}

/**
 * Where an item was read from, each piece a press: a secure link opens in the browser, and a file opens in its own
 * app, or copies its whole path when it is gone or is not a document. A passage that changed since is marked.
 */
export function Evidence({ parts, evidence }: { parts: SettingsParts; evidence: readonly MemoryEvidenceView[] }) {
  const [pressed, setPressed] = useState<{ ref: string; opened: boolean } | undefined>(undefined);
  if (evidence.length === 0) return <p className="text-footnote text-muted">No evidence: an agent suggested it without citing a passage.</p>;
  const targetOf = (each: MemoryEvidenceView) => evidenceTarget(each, parts.memory.sources ?? []);
  const press = (each: MemoryEvidenceView) => {
    const target = targetOf(each);
    if (target.kind === 'link') return parts.host.openPage(target.url);
    void openOrCopy(parts.host, target.path).then((opened) => setPressed({ ref: each.ref, opened }));
  };
  const titleOf = (target: ReturnType<typeof targetOf>) => (target.kind === 'link' ? target.url : `Open ${target.path}`);
  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-footnote font-medium text-muted">Evidence</span>
      <ul className="flex flex-col gap-1">
        {evidence.map((each) => (
          <li key={`${each.source}:${each.ref}`}>
            <button
              type="button"
              onClick={() => press(each)}
              title={titleOf(targetOf(each))}
              className="mx-focus flex w-full cursor-pointer items-start gap-2 rounded-md px-1.5 py-1 text-left text-footnote hover:bg-hover"
            >
              {each.url === undefined ? <FileText size={13} className="mt-0.5 shrink-0 text-muted" aria-hidden /> : <Link2 size={13} className="mt-0.5 shrink-0 text-muted" aria-hidden />}
              <span className={`min-w-0 flex-1 break-words ${each.stale ? 'text-muted line-through decoration-faint' : 'text-primary'}`}>{evidenceLine(each)}</span>
              {each.stale && <StatusWord tone="quiet">Stale</StatusWord>}
              {pressed !== undefined && pressed.ref === each.ref && <span className="shrink-0 text-muted">{filePressLine(pressed.opened)}</span>}
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}

/**
 * A document or a source picked on the map: what it is, and the facts listed above that cite it, each a
 * press that opens the fact. A document opens where it lives, as the evidence under a fact does.
 */
function PlaceDetail({ parts, place, items, open }: { parts: SettingsParts; place: MemoryMapNode; items: readonly MemoryItemView[]; open: (id: string) => void }) {
  const document = place.kind === MEMORY_MAP_NODE.DOCUMENT;
  const cites = (each: MemoryEvidenceView) => (document ? memoryMapIds.document(each.source, each.document) === place.id : memoryMapIds.source(each.source) === place.id);
  const citing = items.filter((item) => item.evidence.some(cites));
  const evidence = items.flatMap((item) => item.evidence).filter(cites);
  const source = document ? undefined : (parts.memory.sources ?? []).find((each) => memoryMapIds.source(each.name) === place.id || memoryMapIds.source(each.id) === place.id);
  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-1">
        <p className="text-base font-medium break-words text-foreground">{place.label}</p>
        {place.detail !== undefined && <p className="text-meta text-muted">{document ? `In ${place.detail}` : place.detail}</p>}
      </div>
      {document && evidence[0] !== undefined && <Evidence parts={parts} evidence={[evidence[0]]} />}
      {source !== undefined && (
        <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-meta">
          <dt className="text-muted">Where</dt>
          <dd className="min-w-0 break-words text-foreground">{source.location}</dd>
          <dt className="text-muted">Trust</dt>
          <dd className="text-foreground">{trustWord(source.trust).word}</dd>
          <dt className="text-muted">Taught</dt>
          <dd className="text-foreground">{sourceCountsLine(source.counts)}</dd>
          <dt className="text-muted">Read</dt>
          <dd className="text-foreground">{lastReadLine(source, Date.now())}</dd>
        </dl>
      )}
      <div className="flex flex-col gap-1.5">
        <span className="text-label font-medium tracking-[0.14em] text-muted uppercase">{document ? 'Facts citing it' : 'Facts read from it'}</span>
        <Panel>
          {citing.map((item) => (
            <Row key={item.id} title={item.statement} caption={statusWord(item.status).word} onClick={() => open(item.id)} />
          ))}
        </Panel>
      </div>
    </div>
  );
}

/** The places memory is read from, one card each, and the dialog that adds another. */
function MemorySources({ parts, said }: { parts: SettingsParts; said: (note: string) => void }) {
  const { memory } = parts;
  const [adding, setAdding] = useState(false);
  const list = memory.sources;
  const add = (
    <KitButton kind="primary" icon={Plus} onClick={() => setAdding(true)}>
      Add source
    </KitButton>
  );
  return (
    <Section title="Memory sources" trailing={list !== undefined && list.length > 0 ? add : undefined}>
      {memory.unreadable.sources && <ReadFailed what="the memory sources" retry={() => void memory.refreshSources()} />}
      {list !== undefined && list.length === 0 && (
        <EmptyState
          icon={BookOpen}
          title="No memory sources yet"
          body="Point Memnox at an Obsidian vault, a folder of notes, your agents' instruction files, a Notion export, Supermemory or an MCP memory server. Your own agent reads it, and you confirm what it finds."
          action={add}
        />
      )}
      {list !== undefined && list.length > 0 && (
        <CardGrid>
          {list.map((source) => (
            <SourceCard key={source.id} parts={parts} source={source} said={said} />
          ))}
        </CardGrid>
      )}
      {adding && <AddMemorySourceDialog parts={parts} close={() => setAdding(false)} said={said} />}
    </Section>
  );
}

function SourceCard({ parts, source, said }: { parts: SettingsParts; source: MemorySourceView; said: (note: string) => void }) {
  const { memory } = parts;
  const [sure, setSure] = useState(false);
  const trust = trustWord(source.trust);
  const key = keyLine(source);
  const read = memory.lastRead(source.id);
  const busy = memory.busy === source.id;
  return (
    <article className="flex flex-col gap-2.5 rounded-xl border border-panel-edge bg-card p-4">
      <header className="flex items-center gap-2">
        <BookOpen size={16} className="text-muted" aria-hidden />
        <span className="min-w-0 flex-1 truncate text-body font-semibold text-foreground">{source.name}</span>
        <span className="text-footnote text-muted">{sourceKindLabel(source.kind)}</span>
      </header>
      <span className="truncate font-mono text-micro text-muted" title={source.location}>
        {source.location}
      </span>
      <StatusWord tone={trust.tone}>{trust.word}</StatusWord>
      <span className="text-footnote text-foreground">{sourceCountsLine(source.counts)}</span>
      <span className="text-footnote text-muted">{lastReadLine(source, Date.now())}</span>
      {key !== undefined && <span className={`text-footnote ${source.keyHeld === true ? 'text-muted' : 'text-warm'}`}>{key}</span>}
      {source.lastError !== undefined && (
        <p role="alert" className="text-footnote text-destructive">
          {`The last read failed: ${source.lastError}`}
        </p>
      )}
      {read !== undefined && <p className="text-footnote text-foreground">{readSummaryLine(read)}</p>}
      <div className="mt-auto flex flex-wrap items-center gap-2 pt-1">
        <KitButton icon={RefreshCw} disabled={busy} onClick={() => void memory.readNow(source.id).then((outcome) => outcome.kind === 'failed' && said(outcome.why))}>
          {busy ? 'Reading' : 'Read now'}
        </KitButton>
        <span className="flex-1" />
        {sure ? (
          <>
            <KitButton onClick={() => setSure(false)}>Keep</KitButton>
            <KitButton icon={Trash2} disabled={busy} onClick={() => void memory.removeSource(source.id).then((outcome) => said(memoryNote(outcome)))}>
              Remove
            </KitButton>
          </>
        ) : (
          <KitButton icon={Trash2} onClick={() => setSure(true)}>
            Remove
          </KitButton>
        )}
      </div>
    </article>
  );
}
