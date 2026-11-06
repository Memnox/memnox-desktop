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
  MemoryPageLines,
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
import { choiceKey, choiceOfKey, memoryChoices, memoryOwner, MEMORY_CHOICE_KEY, MEMORY_EVERYWHERE_NOTE, shownMemory, type MemoryProjectChoice } from '../../../core/domain/project-context';
import { SEPARATOR } from '../../../core/domain/session-text';
import { useShellChoices } from '../shell-choices';
import { openOrCopy } from '../../settings/host';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { AddMemorySourceDialog } from './MemorySourceDialog';
import { MemoryBrain, WorkspaceFoot } from './MemoryBrain';
import { homeFilterOf, MEMORY_HOME_FILTERS, MEMORY_HOME_KEY, type MemoryHomeFilter } from '../../../core/domain/memory-brain-lines';
import { MemoryLayersView } from './MemoryLayers';
import { Inspector, ScopeChip } from '../widgets';
import { memoryScope } from '../../../core/domain/scope-lines';
import { useInspectorHost, usePicked } from '../inspector-host';
import { Button, Card, CardGrid, Chip, ChipGroup, EmptyState, ErrorLine, Note, Panel, PRESS_DIP, Pressable, ReadFailed, Row, SearchInput, Section, Select, StatusWord } from '../../kit';

/** How long typing rests before the search is asked, so each key is not a request. */
const SEARCH_REST_MS = 300;

/** The project filter's width, the Mac's `KitMenu` width, so a long project name is cut rather than pushing the chips. */
const PROJECT_FILTER_WIDTH = 200;

/** The agent's logo before an origin line, as tall as the line. */
const ORIGIN_LOGO = 16;

/** A passage's file or link glyph, a point over the footnote beside it. */
const EVIDENCE_GLYPH = 13;

/** The book on a source card, a point over its 15 title. */
const SOURCE_GLYPH = 16;

/** Where the sources link leads: the Sources tab under Connected tools. */
const SOURCES_ROUTE: Route = { destination: 'workspaces', tab: 'sources' };

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
      <Select
        value={choiceKey(projectChoice)}
        label={MemoryPageLines.whoseMemory}
        width={PROJECT_FILTER_WIDTH}
        options={memoryChoices(localProjects).map((each) => ({ value: choiceKey(each.choice), label: each.title }))}
        onChange={(key) => chooseProject(choiceOfKey(key))}
      />
    );
  const { connected } = useShellChoices();
  const [status, setStatus] = useState<MemoryStatusName>('verified');
  const [scope, setScope] = useState<MemoryScopeName | undefined>(undefined);
  const [query, setQuery] = useState('');
  // Whose memory the brain draws, remembered for the next visit under the Mac's own key.
  const [home, setHome] = useState<MemoryHomeFilter>(() => homeFilterOf(localStorage.getItem(MEMORY_HOME_KEY)));
  const chooseHome = (filter: MemoryHomeFilter) => {
    localStorage.setItem(MEMORY_HOME_KEY, filter);
    setHome(filter);
  };
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

  const noteLine = note === undefined ? null : <Note>{note}</Note>;
  const searchLine = (
    <p className="text-footnote text-muted">
      {memory.search === undefined ? MemoryPageLines.searchingAll : MemoryPageLines.searchingMode(searchModeLine(memory.search.mode))}
      {memory.search?.note !== undefined && <span className="block">{memory.search.note}</span>}
    </p>
  );
  const statusChips = (
    <ChipGroup label={MemoryPageLines.status} role="group">
      {MEMORY_FILTERS.map((each) => (
        <Chip key={each.status} role="toggle" on={status === each.status} pick={() => setStatus(each.status)}>
          {each.label}
        </Chip>
      ))}
    </ChipGroup>
  );
  const scopeChips = (
    <ChipGroup label={MemoryPageLines.scope} role="group">
      <Chip role="toggle" on={scope === undefined} pick={() => setScope(undefined)}>
        {MemoryPageLines.both}
      </Chip>
      {MEMORY_SCOPES.map((each) => (
        <Chip key={each.scope} role="toggle" on={scope === each.scope} pick={() => setScope(each.scope)}>
          {each.label}
        </Chip>
      ))}
    </ChipGroup>
  );
  const searching = query.trim() !== '';
  const statusRow = searching ? searchLine : statusChips;
  // Whose a fact is matters only once there is an organization beside the person.
  const scopeRow = connected && scopeChips;

  if (view === 'graph') {
    // Only the brain draws the workspace, so only the brain has the chips for whose memory it draws.
    const homeRow = (
      <ChipGroup label={MemoryPageLines.whoseMemory} role="group">
        {MEMORY_HOME_FILTERS.map((each) => (
          <Chip key={each.filter} role="toggle" on={home === each.filter} pick={() => chooseHome(each.filter)}>
            {each.label}
          </Chip>
        ))}
      </ChipGroup>
    );
    const more = listed === undefined ? undefined : moreLine(listed.more);
    return (
      <MemoryBrain
        parts={parts}
        shown={brainShown}
        {...(listed === undefined ? {} : { facts: listed.items })}
        home={home}
        {...(searching ? {} : { status })}
        {...(go === undefined ? {} : { go })}
        nodeCard={(id, close) => <BrainNode parts={parts} id={id} forget={(item) => forget(item, close)} />}
        bar={
          <>
            {/* The project, the status, then whose memory and the scope, in the Mac's order, wrapping where they do not fit. */}
            <div className="flex flex-wrap items-center gap-2">
              {projectFilter}
              {statusRow}
              {homeRow}
              {scopeRow}
            </div>
            {noteLine}
            {memory.unreadable.facts && <ReadFailed what={MemoryPageLines.whatWasLearned} retry={() => void memory.show(memory.filter)} />}
          </>
        }
        foot={
          <>
            {more !== undefined && <p className="text-footnote text-muted">{more}</p>}
            <WorkspaceFoot parts={parts} home={home} {...(go === undefined ? {} : { go })} />
            {go !== undefined && <SourcesLink go={go} />}
          </>
        }
      />
    );
  }
  if (view === 'layers') {
    return (
      <div className="flex flex-col gap-4">
        {noteLine}
        <MemoryLayersView parts={parts} {...(chosenProject === undefined ? {} : { project: chosenProject.path })} />
      </div>
    );
  }
  return (
    <div className="flex min-h-0">
      <div className="flex min-w-0 flex-1 flex-col gap-7">
        {noteLine}
        <Section title={MemoryPageLines.knowTitle}>
          {/* The search, the project, the status and the scope on one row where they fit, in the Mac's order. */}
          <div className="flex flex-wrap items-center gap-3">
            <div className="w-app-memory-search max-w-full">
              <SearchInput value={query} placeholder={MemoryPageLines.searchPlaceholder} onChange={setQuery} />
            </div>
            {projectFilter}
            {statusRow}
            <span className="flex-1" />
            {scopeRow}
          </div>
          {memory.unreadable.facts && <ReadFailed what={MemoryPageLines.whatWasLearned} retry={() => void memory.show(memory.filter)} />}
          {projectChoice.kind === 'shared' && <p className="text-footnote text-muted">{MEMORY_EVERYWHERE_NOTE}</p>}
          {listed !== undefined && narrowed.length === 0 && (
            <EmptyState icon={Brain} title={searching ? MemoryPageLines.nothingSays : MemoryPageLines.nothingHere(statusWord(status).word)} body={FACTS_EMPTY_DETAIL} />
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
                      {item.tainted && <StatusWord tone="attention">{MemoryPageLines.untrusted}</StatusWord>}
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
    <Button kind="link" size="small" icon={Library} onClick={() => go(SOURCES_ROUTE)}>
      {SOURCES_LINK}
    </Button>
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
      {item.rule !== undefined && <p className="text-footnote text-foreground">{MemoryPageLines.governs(item.rule.sentence)}</p>}
      <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-footnote">
        <dt className="text-muted">{MemoryPageLines.about}</dt>
        <dd className="min-w-0 break-words text-foreground">{item.subject}</dd>
        <dt className="text-muted">{MemoryPageLines.kept}</dt>
        <dd className="text-foreground">{item.scope === 'project' ? MemoryPageLines.keptWithProject(item.project) : MemoryPageLines.keptPersonal}</dd>
        <dt className="text-muted">{MemoryPageLines.from}</dt>
        <dd className="text-foreground">
          <OriginLine item={item} />
        </dd>
        {confidence !== undefined && (
          <>
            <dt className="text-muted">{MemoryPageLines.extractor}</dt>
            <dd className="text-foreground">{confidence}</dd>
          </>
        )}
        {decided !== undefined && (
          <>
            <dt className="text-muted">{MemoryPageLines.settled}</dt>
            <dd className="text-foreground">{decided}</dd>
          </>
        )}
      </dl>
      <Evidence parts={parts} evidence={item.evidence} />
      <div className="flex flex-wrap items-center gap-2 border-t border-panel-edge pt-3">
        {sure ? (
          <>
            <span className="flex-1 text-footnote text-muted">{MemoryPageLines.forgetWarning}</span>
            <Button onClick={() => setSure(false)}>{MemoryPageLines.keepIt}</Button>
            <Button icon={Trash2} disabled={memory.busy === item.id} onClick={forget}>
              {MemoryPageLines.forget}
            </Button>
          </>
        ) : (
          <Button icon={Trash2} onClick={() => setSure(true)}>
            {MemoryPageLines.forget}
          </Button>
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
      {agent !== undefined && <BrandLogo agent={agent} name={agentLabel(agent)} size={ORIGIN_LOGO} />}
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
  if (evidence.length === 0) return <p className="text-footnote text-muted">{MemoryPageLines.noEvidence}</p>;
  const targetOf = (each: MemoryEvidenceView) => evidenceTarget(each, parts.memory.sources ?? []);
  const press = (each: MemoryEvidenceView) => {
    const target = targetOf(each);
    if (target.kind === 'link') return parts.host.openPage(target.url);
    void openOrCopy(parts.host, target.path).then((opened) => setPressed({ ref: each.ref, opened }));
  };
  const titleOf = (target: ReturnType<typeof targetOf>) => (target.kind === 'link' ? target.url : MemoryPageLines.openPath(target.path));
  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-footnote font-medium text-muted">{MemoryPageLines.evidence}</span>
      <ul className="flex flex-col gap-1">
        {evidence.map((each) => (
          <li key={`${each.source}:${each.ref}`}>
            <Pressable
              onClick={() => press(each)}
              title={titleOf(targetOf(each))}
              className={`mx-focus flex w-full cursor-pointer items-start gap-2 rounded-control px-1.5 py-1 text-left text-footnote hover:bg-hover ${PRESS_DIP}`}
            >
              {each.url === undefined ? <FileText size={EVIDENCE_GLYPH} className="mt-0.5 shrink-0 text-muted" aria-hidden /> : <Link2 size={EVIDENCE_GLYPH} className="mt-0.5 shrink-0 text-muted" aria-hidden />}
              <span className={`min-w-0 flex-1 break-words ${each.stale ? 'text-muted line-through decoration-faint' : 'text-primary'}`}>{evidenceLine(each)}</span>
              {each.stale && <StatusWord tone="quiet">{MemoryPageLines.stale}</StatusWord>}
              {pressed !== undefined && pressed.ref === each.ref && <span className="shrink-0 text-muted">{filePressLine(pressed.opened)}</span>}
            </Pressable>
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
        <p className="text-meta text-muted">{MemoryPageLines.inSource(evidence.source)}</p>
        <Evidence parts={parts} evidence={[evidence]} />
        <div className="flex flex-col gap-1.5">
          <span className="text-label font-medium tracking-[0.14em] text-muted uppercase">{MemoryPageLines.factsCiting}</span>
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
      {node.saidBy !== undefined && <p className="text-meta text-muted">{MemoryPageLines.saidBy(node.saidBy)}</p>}
      {node.status === 'candidate' && <StatusWord tone="attention">{MemoryPageLines.notConfirmed}</StatusWord>}
      {node.untrusted === true && <StatusWord tone="attention">{TAINTED_LINE}</StatusWord>}
      {node.href !== undefined && (
        <Button kind="link" onClick={() => parts.host.openPage(node.href as string)}>
          {MemoryPageLines.openWhereItLives}
        </Button>
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
      {note !== undefined && <Note>{note}</Note>}
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
    <Button kind="primary" icon={Plus} onClick={() => setAdding(true)}>
      {MemoryPageLines.addSource}
    </Button>
  );
  return (
    <Section title={MemoryPageLines.sourcesTitle} trailing={list !== undefined && list.length > 0 ? add : undefined}>
      {memory.unreadable.sources && <ReadFailed what={MemoryPageLines.theSources} retry={() => void memory.refreshSources()} />}
      {list !== undefined && list.length === 0 && (
        <EmptyState
          icon={BookOpen}
          title={MemoryPageLines.noSources}
          body={MemoryPageLines.noSourcesBody}
          action={add}
        />
      )}
      {list !== undefined && list.length > 0 && (
        <CardGrid min={SOURCE_CARD_MIN}>
          {list.map((source) => (
            <SourceCard key={source.id} parts={parts} source={source} said={said} />
          ))}
        </CardGrid>
      )}
      {adding && <AddMemorySourceDialog parts={parts} close={() => setAdding(false)} said={said} />}
    </Section>
  );
}

/** A source card is never narrower than this, so its buttons keep their whole labels, as the Mac's `cardWidth`. */
const SOURCE_CARD_MIN = 280;

function SourceCard({ parts, source, said }: { parts: SettingsParts; source: MemorySourceView; said: (note: string) => void }) {
  const { memory } = parts;
  const [sure, setSure] = useState(false);
  const trust = trustWord(source.trust);
  const key = keyLine(source);
  const read = memory.lastRead(source.id);
  const busy = memory.busy === source.id;
  return (
    <Card as="article" className="flex flex-col gap-2">
      <header className="flex items-center gap-2">
        <BookOpen size={SOURCE_GLYPH} className="text-muted" aria-hidden />
        <span className="min-w-0 flex-1 truncate text-body font-semibold text-foreground">{source.name}</span>
        <span className="text-footnote text-muted">{sourceKindLabel(source.kind)}</span>
      </header>
      <span className="truncate text-micro text-muted" title={source.location}>
        {source.location}
      </span>
      <StatusWord tone={trust.tone}>{trust.word}</StatusWord>
      <span className="text-footnote text-foreground">{sourceCountsLine(source.counts)}</span>
      <span className="text-footnote text-muted">{lastReadLine(source, Date.now())}</span>
      {key !== undefined && <span className={`text-footnote ${source.keyHeld === true ? 'text-muted' : 'text-warm'}`}>{key}</span>}
      {source.lastError !== undefined && <ErrorLine>{MemoryPageLines.lastReadFailed(source.lastError)}</ErrorLine>}
      {read !== undefined && <p className="text-footnote text-foreground">{readSummaryLine(read)}</p>}
      <div className="mt-auto flex flex-wrap items-center gap-2 pt-1">
        <Button icon={RefreshCw} disabled={busy} onClick={() => void memory.readNow(source.id).then((outcome) => outcome.kind === 'failed' && said(outcome.why))}>
          {busy ? MemoryPageLines.reading : MemoryPageLines.readNow}
        </Button>
        <span className="flex-1" />
        {sure ? (
          <>
            <Button onClick={() => setSure(false)}>{MemoryPageLines.keep}</Button>
            <Button kind="primary" icon={Trash2} disabled={busy} onClick={() => void memory.removeSource(source.id).then((outcome) => said(memoryNote(outcome)))}>
              {MemoryPageLines.remove}
            </Button>
          </>
        ) : (
          <Button icon={Trash2} onClick={() => setSure(true)}>
            {MemoryPageLines.remove}
          </Button>
        )}
      </div>
    </Card>
  );
}
