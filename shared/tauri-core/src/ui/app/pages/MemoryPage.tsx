import type { MemoryEvidenceView, MemoryItemView, MemorySourceView } from '@memnox/core/wire';
import { BookOpen, Brain, Library, FileText, Link2, Plus, RefreshCw, Trash2 } from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';
import type { MemoryOutcome } from '../../../core/application/memory';
import type { Route, WidthClass } from '../../../core/domain/destinations';
import { LOCAL_ARMS_IDS } from '../../../core/domain/memory-arms/arms-local';
import {
  MEMORY_FILTERS,
  MEMORY_SCOPES,
  confidenceLine,
  FACTS_EMPTY_DETAIL,
  rowCaption,
  SOURCES_LINK,
  decidedLine,
  evidenceLine,
  evidenceTarget,
  filePressLine,
  keyLine,
  kindWord,
  memoryViewOf,
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
import { agentLabel } from '../../../core/domain/mcp-hub-lines';
import { BrandLogo } from '../../kit/logos';
import { KitButton, SearchField, SelectMenu } from '../../settings/kit';
import { choiceKey, choiceOfKey, memoryChoices, memoryOwner, MEMORY_CHOICE_KEY, MEMORY_EVERYWHERE_NOTE, shownMemory, type MemoryProjectChoice } from '../../../core/domain/project-context';
import { SEPARATOR } from '../../../core/domain/session-text';
import { useShellChoices } from '../shell-choices';
import { openOrCopy } from '../../settings/host';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { AddMemorySourceDialog } from './MemorySourceDialog';
import { MemoryBrain } from './MemoryBrain';
import { MemoryLayersView } from './MemoryLayers';
import { CardGrid, EmptyState, Inspector, Panel, ReadFailed, Row, ScopeChip, Section, StatusWord } from '../widgets';
import { memoryScope } from '../../../core/domain/scope-lines';
import { useInspectorHost, usePicked } from '../inspector-host';

const CHIP = 'mx-focus cursor-pointer inline-flex h-8 items-center rounded-lg border px-3 text-body-sm';
const chip = (on: boolean) => `${CHIP} ${on ? 'border-primary/45 bg-primary/[0.07] font-medium text-foreground' : 'border-panel-edge bg-card text-muted hover:bg-hover hover:text-foreground'}`;

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
export function MemoryPage({ parts, tab, width, go }: { parts: SettingsParts; /** The Memory row's tab: the map, the list or the layers. */ tab: string | undefined; width: WidthClass; go?: (route: Route) => void }) {
  const { memory, support, projects } = parts;
  useObserved(memory, support, projects);
  // Which project's memory shows, remembered between openings: every project's, what no project owns, or one project's.
  const [projectChoice, setProjectChoice] = useState<MemoryProjectChoice>(() => choiceOfKey(localStorage.getItem(MEMORY_CHOICE_KEY)));
  const chooseProject = (choice: MemoryProjectChoice) => {
    localStorage.setItem(MEMORY_CHOICE_KEY, choiceKey(choice));
    setProjectChoice(choice);
  };
  const readsProjects = support.supports('projects') === true;
  useEffect(() => {
    if (readsProjects && projects.projects === undefined) void projects.refresh();
  }, [readsProjects]);
  const localProjects = projects.projects ?? [];
  const chosenProject = projectChoice.kind === 'project' ? localProjects.find((each) => each.id === projectChoice.id) : undefined;
  // Kept the same between draws, so the brain is laid out again only when the filter or the projects change.
  const brainShown = useCallback((items: readonly MemoryItemView[]) => shownMemory(items, projectChoice, projects.projects ?? []), [choiceKey(projectChoice), projects.projects]);
  const projectFilter =
    localProjects.length === 0 ? null : (
      <SelectMenu
        value={choiceKey(projectChoice)}
        label="Whose memory"
        width={200}
        options={memoryChoices(localProjects).map((each) => ({ value: choiceKey(each.choice), label: each.title }))}
        onChange={(key) => chooseProject(choiceOfKey(key))}
      />
    );
  const { connected } = useShellChoices();
  const [status, setStatus] = useState<MemoryStatusName>('verified');
  const [scope, setScope] = useState<MemoryScopeName | undefined>(undefined);
  const [query, setQuery] = useState('');
  const [chosen, choose] = usePicked();
  const linked = useInspectorHost().item;
  const [note, setNote] = useState<string | undefined>(undefined);
  // The row's strip is the only switch between the map, the list and the layers, as on the Mac.
  const view = memoryViewOf(tab);
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
  // The facts the project filter leaves, which the list draws.
  const narrowed = listed === undefined ? [] : shownMemory(listed.items, projectChoice, localProjects);
  const picked = listed?.items.find((item) => item.id === chosen);
  const forget = (id: string, after: () => void) =>
    void memory.forget(id).then((outcome) => {
      setNote(memoryNote(outcome));
      if (outcome.kind !== 'failed') after();
    });

  if (view === 'graph' || view === 'layers') {
    return (
      <div className="flex flex-col gap-4">
        {note !== undefined && (
          <p role="status" className="rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote text-foreground">
            {note}
          </p>
        )}
        {view === 'graph' && projectFilter !== null && <div className="flex flex-wrap items-center gap-2">{projectFilter}</div>}
        {view === 'graph' ? (
          <MemoryBrain
            parts={parts}
            shown={brainShown}
            {...(go === undefined ? {} : { go })}
            nodeCard={(id, close) => <BrainNode parts={parts} id={id} forget={(item) => forget(item, close)} />}
          />
        ) : (
          <MemoryLayersView parts={parts} {...(chosenProject === undefined ? {} : { project: chosenProject.path })} />
        )}
        {view === 'graph' && go !== undefined && <SourcesLink go={go} />}
      </div>
    );
  }
  return (
    <div className="flex min-h-0">
      <div className="flex min-w-0 flex-1 flex-col gap-7">
        {note !== undefined && (
          <p role="status" className="rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote text-foreground">
            {note}
          </p>
        )}
        <Section title="What your agents know">
          {/* The search, the project, the status and the scope on one row where they fit, in the Mac's order. */}
          <div className="flex flex-wrap items-center gap-3">
            <div className="w-full max-w-[300px] min-w-[180px] flex-1">
              <SearchField value={query} placeholder="Search memory" onChange={setQuery} />
            </div>
            {projectFilter}
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
            <span className="flex-1" />
            {/* Whose a fact is matters only once there is an organization beside the person. */}
            {connected && (
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
            )}
          </div>
          {memory.unreadable.facts && <ReadFailed what="what was learned" retry={() => void memory.show(memory.filter)} />}
          {projectChoice.kind === 'shared' && <p className="text-footnote text-muted">{MEMORY_EVERYWHERE_NOTE}</p>}
          {listed !== undefined && narrowed.length === 0 && (
            <EmptyState icon={Brain} title={query.trim() === '' ? `Nothing ${statusWord(status).word.toLowerCase()} here` : 'Nothing learned says that'} body={FACTS_EMPTY_DETAIL} />
          )}
          {narrowed.length > 0 && (
            <Panel>
              {narrowed.map((item) => (
                <Row
                  key={item.id}
                  chosen={item.id === chosen}
                  onClick={() => choose(item.id)}
                  title={<span className="whitespace-pre-wrap">{item.statement}</span>}
                  caption={[rowCaption(item), memoryOwner(item, localProjects)].join(SEPARATOR)}
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
        {go !== undefined && <SourcesLink go={go} />}
      </div>
      {picked !== undefined && (
        <Inspector title={kindWord(picked.kind)} width={width} close={() => choose(undefined)} item={picked.id}>
          <FactDetail parts={parts} item={picked} forget={() => forget(picked.id, () => choose(undefined))} />
        </Inspector>
      )}
    </div>
  );
}

/** Where the files went: a quiet line that takes the person to them under Connected tools. */
function SourcesLink({ go }: { go: (route: Route) => void }) {
  return (
    <button type="button" onClick={() => go({ destination: 'workspaces', tab: 'sources' })} className="mx-focus inline-flex w-fit cursor-pointer items-center gap-1.5 text-footnote text-primary hover:underline">
      <Library size={14} aria-hidden />
      {SOURCES_LINK}
    </button>
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
        <dd className="text-foreground">
          <OriginLine item={item} />
        </dd>
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

/** Where an item came from, with the suggesting agent's logo ahead of the line when an agent suggested it. */
export function OriginLine({ item, className }: { item: Pick<MemoryItemView, 'origin' | 'suggestedBy'>; className?: string }) {
  const agent = item.origin === 'agent' ? item.suggestedBy : undefined;
  return (
    <span className={`inline-flex items-center gap-1.5 ${className ?? ''}`}>
      {agent !== undefined && <BrandLogo agent={agent} name={agentLabel(agent)} size={16} />}
      {originLine(item)}
    </span>
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
 * What the brain's card holds for a node this page knows: a fact whole with its evidence, or a document with the
 * facts that cite it, each fact a press that opens it in its place. A workspace node says what the cloud handed down.
 */
function BrainNode({ parts, id, forget }: { parts: SettingsParts; id: string; forget: (item: string) => void }) {
  const { memory } = parts;
  const [open, setOpen] = useState<string | undefined>(undefined);
  const items = memory.everything ?? [];
  const shown = open ?? id;
  const fact = items.find((item) => LOCAL_ARMS_IDS.fact(item.id) === shown);
  if (fact !== undefined) return <FactDetail parts={parts} item={fact} forget={() => forget(fact.id)} />;
  const cites = (each: MemoryEvidenceView) => LOCAL_ARMS_IDS.document(each.source, each.document) === shown;
  const citing = items.filter((item) => item.evidence.some(cites));
  const evidence = items.flatMap((item) => item.evidence).find(cites);
  if (evidence !== undefined) {
    return (
      <div className="flex flex-col gap-4">
        <p className="text-meta text-muted">{`In ${evidence.source}`}</p>
        <Evidence parts={parts} evidence={[evidence]} />
        <div className="flex flex-col gap-1.5">
          <span className="text-label font-medium tracking-[0.14em] text-muted uppercase">Facts citing it</span>
          <Panel>
            {citing.map((item) => (
              <Row key={item.id} title={item.statement} caption={statusWord(item.status).word} onClick={() => setOpen(LOCAL_ARMS_IDS.fact(item.id))} />
            ))}
          </Panel>
        </div>
      </div>
    );
  }
  const node = memory.workspaceGraph?.nodes.find((each) => LOCAL_ARMS_IDS.workspace(each.id) === shown);
  if (node === undefined) return null;
  return (
    <div className="flex flex-col gap-2">
      {node.statement !== undefined && <p className="whitespace-pre-wrap text-body-sm text-foreground">{node.statement}</p>}
      {node.excerpt !== undefined && <p className="whitespace-pre-wrap text-body-sm text-muted">{node.excerpt}</p>}
      {node.saidBy !== undefined && <p className="text-meta text-muted">{`Said by ${node.saidBy}`}</p>}
      {node.status === 'candidate' && <StatusWord tone="attention">Not confirmed by anybody yet</StatusWord>}
      {node.untrusted === true && <StatusWord tone="attention">{TAINTED_LINE}</StatusWord>}
      {node.href !== undefined && (
        <button type="button" className="mx-focus w-fit cursor-pointer text-body-sm font-medium text-primary hover:underline" onClick={() => parts.host.openPage(node.href as string)}>
          Open where it lives
        </button>
      )}
    </div>
  );
}

/**
 * The Sources tab under Inputs, as the Mac places it: where memory is read from, apart from what was read, with the
 * line a press leaves above it.
 */
export function MemorySourcesPage({ parts }: { parts: SettingsParts }) {
  const [note, setNote] = useState<string | undefined>(undefined);
  useEffect(() => void parts.memory.refreshSources(), []);
  return (
    <div className="flex flex-col gap-5">
      {note !== undefined && (
        <p role="status" className="rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote text-foreground">
          {note}
        </p>
      )}
      <MemorySources parts={parts} said={setNote} />
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
