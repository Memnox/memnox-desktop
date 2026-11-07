import type { CommunityIndexView, IndexEntryView, IndexNeedsView } from '@memnox/core/wire';
import { ArrowLeft, Download, Globe, RefreshCw, Store } from 'lucide-react';
import { useEffect, useState } from 'react';
import { SETTING_SOURCE, type IndexOutcome, type IndexSourceOutcome } from '../../../core/application/community-index';
import type { WidthClass } from '../../../core/domain/destinations';
import {
  canInstall,
  DiscoverLines,
  categoriesOf,
  INDEX_ADDRESS_WANTED,
  inCategory,
  indexKindWord,
  indexSourceLine,
  indexStateLine,
  isIndexAddress,
  needsGroups,
  needsSummaryLine,
  installedLine,
  installWaitsLine,
  latestLine,
  publisherLine,
  supportedAgentsLine,
  warningsCountLine,
  yankedLine,
} from '../../../core/domain/index-lines';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { agentLabel } from '../../../core/domain/mcp-hub-lines';
import { Facts } from './SkillsPage';
import { AgentLogos, Button, Card, CardGrid, Chip, ChipGroup, EmptyState, Input, Note, Panel, ReadFailed, Row, SearchInput, Section, StatusWord } from '../../kit';
import { PAGE_METRICS } from '../page-metrics';

/** Words go to the runtime this long after the last key, so each key is not a request. */
const SEARCH_REST_MS = 250;

/** The Mac's search and its address field, each grown to its width and no further. */
const SEARCH_WIDTH = PAGE_METRICS.discoverSearch;
const ADDRESS_WIDTH = PAGE_METRICS.discoverAddress;

/**
 * The community index under the Skills Hub. Install never makes anything live: the runtime checks the
 * digest, a skill then waits in My Skills for acceptance, and a pack's rules each wait on the island.
 */
export function DiscoverPage({ parts, width }: { parts: SettingsParts; width: WidthClass }) {
  const { index } = parts;
  useObserved(index);
  useEffect(() => {
    void index.refresh();
  }, []);
  const [query, setQuery] = useState(index.filter.query);
  const [category, setCategory] = useState<string | undefined>(undefined);
  const [opened, open] = useState<string | undefined>(undefined);
  const [note, setNote] = useState<string | undefined>(undefined);
  const said = (outcome: IndexOutcome | IndexSourceOutcome) => setNote(outcome.kind === 'failed' ? outcome.why : outcome.note);
  // Words go to the runtime a moment after the last key, so each key is not a request.
  useEffect(() => {
    if (query === index.filter.query) return;
    const handle = setTimeout(() => void index.refresh({ ...index.filter, query }), SEARCH_REST_MS);
    return () => clearTimeout(handle);
  }, [query]);

  const view = index.index;
  if (view === undefined) return index.unreadable ? <ReadFailed what={DiscoverLines.readWhat} retry={() => void index.refresh()} /> : null;
  const picked = view.entries.find((entry) => entry.id === opened);
  const status = note !== undefined && <Note>{note}</Note>;
  if (picked !== undefined) {
    return (
      <>
        {status}
        <Listing parts={parts} entry={picked} width={width} back={() => open(undefined)} said={said} />
      </>
    );
  }
  const categories = categoriesOf(view.entries);
  const shown = inCategory(view.entries, category);
  return (
    <div className="flex flex-col gap-5">
      {status}
      <div className="flex flex-wrap items-center gap-2.5">
        <div className="w-full flex-1" style={{ maxWidth: SEARCH_WIDTH }}>
          <SearchInput value={query} placeholder={DiscoverLines.search} onChange={setQuery} />
        </div>
        <span className="flex-1" />
        <Button icon={RefreshCw} disabled={index.busy === 'refresh'} onClick={() => void index.refresh(index.filter, true)} title={DiscoverLines.refreshHelp}>
          {DiscoverLines.refresh}
        </Button>
      </div>
      <ChipGroup label={DiscoverLines.kind}>
        {DiscoverLines.kinds.map((kind) => (
          <Chip key={kind.id} on={index.filter.kind === kind.id} pick={() => void index.refresh({ ...index.filter, kind: kind.id })}>
            {kind.title}
          </Chip>
        ))}
        {categories.length > 0 && <span aria-hidden className="mx-1 h-4 w-px bg-panel-edge" />}
        {categories.length > 0 && (
          <Chip on={category === undefined} pick={() => setCategory(undefined)}>
            {DiscoverLines.everyCategory}
          </Chip>
        )}
        {categories.map((each) => (
          <Chip key={each} on={category === each} pick={() => setCategory(each)}>
            {each}
          </Chip>
        ))}
      </ChipGroup>
      <p className="text-footnote text-muted">{indexStateLine(view, Date.now())}</p>
      {shown.length === 0 ? (
        <EmptyState icon={Store} title={DiscoverLines.emptyTitle} body={DiscoverLines.emptyBody} />
      ) : (
        <CardGrid>
          {shown.map((entry) => (
            <ListingCard key={entry.id} entry={entry} view={() => open(entry.id)} />
          ))}
        </CardGrid>
      )}
      <p className="text-footnote text-muted">{`${installWaitsLine('skill', parts.words.keyTitle)} ${installWaitsLine('rule_pack', parts.words.keyTitle)}`}</p>
      <ListingsSource parts={parts} view={view} said={said} />
    </div>
  );
}

/** Where listings come from: another index is only proposed and signed on the island, the marketplace again is at once. */
function ListingsSource({ parts, view, said }: { parts: SettingsParts; view: CommunityIndexView; said: (outcome: IndexSourceOutcome) => void }) {
  const { index } = parts;
  const [address, setAddress] = useState('');
  const typed = address.trim() !== '';
  const usable = isIndexAddress(address);
  const busy = index.busy === SETTING_SOURCE;
  const propose = () => {
    if (!usable || busy) return;
    void index.setSource(address).then((outcome) => {
      said(outcome);
      if (outcome.kind !== 'failed') setAddress('');
    });
  };
  return (
    <Section title={DiscoverLines.sourceTitle} trailing={view.marketplace ? <StatusWord tone="good">{DiscoverLines.marketplace}</StatusWord> : <StatusWord tone="attention">{DiscoverLines.named}</StatusWord>}>
      <div className="flex flex-col gap-3 rounded-card border border-panel-edge bg-card p-3.5">
        <p className="text-footnote text-foreground">{indexSourceLine(view)}</p>
        <div className="flex flex-wrap items-center gap-2">
          <Input value={address} placeholder={DiscoverLines.addressPlaceholder} onValue={setAddress} onSubmit={propose} className="flex-1" style={{ maxWidth: ADDRESS_WIDTH }} />
          <Button icon={Globe} disabled={!usable || busy} onClick={propose}>
            {DiscoverLines.propose}
          </Button>
        </div>
        {typed && !usable && <p className="text-footnote text-warm">{INDEX_ADDRESS_WANTED}</p>}
        <p className="text-footnote text-muted">{DiscoverLines.proposeWaits(parts.words.keyTitle)}</p>
        <div>
          <Button disabled={view.marketplace || busy} onClick={() => void index.setSource().then(said)}>
            {DiscoverLines.useMarketplace}
          </Button>
        </div>
      </div>
    </Section>
  );
}

/** What a listing needs in one line, the paths, hosts, commands, servers and tools themselves on open. */
function Needs({ needs }: { needs: IndexNeedsView | undefined }) {
  const groups = needsGroups(needs);
  const summary = <span className="text-footnote text-foreground">{needsSummaryLine(needs)}</span>;
  if (groups.length === 0) return summary;
  return (
    <details>
      <summary className="mx-focus cursor-pointer text-footnote text-foreground">{needsSummaryLine(needs)}</summary>
      <dl className="mt-2.5 flex flex-col gap-2.5">
        {groups.map((group) => (
          <div key={group.title} className="flex flex-col gap-1">
            <dt className="text-footnote font-semibold text-foreground">
              {group.title} <span className="font-normal text-muted">{group.caption}</span>
            </dt>
            {group.items.map((item) => (
              <dd key={item} className="font-code text-micro break-all text-foreground">
                {item}
              </dd>
            ))}
          </div>
        ))}
      </dl>
    </details>
  );
}

/** What to know before installing, each sentence in amber beside its words, since colour alone says nothing. */
function Warnings({ warnings }: { warnings: readonly string[] }) {
  const count = warningsCountLine(warnings);
  if (count === undefined) return null;
  return (
    <div className="flex flex-col gap-1.5">
      <StatusWord tone="attention">{count}</StatusWord>
      <ul className="flex flex-col gap-1 pl-3">
        {warnings.map((warning) => (
          <li key={warning} className="list-disc text-footnote text-warm">
            {warning}
          </li>
        ))}
      </ul>
    </div>
  );
}

function ListingCard({ entry, view }: { entry: IndexEntryView; view: () => void }) {
  const installed = installedLine(entry);
  const warnings = warningsCountLine(entry.warnings);
  return (
    <Card as="article" className="flex flex-col gap-3">
      <div className="flex min-w-0 flex-col gap-0.5">
        <span className="truncate text-headline font-semibold text-foreground">{entry.name}</span>
        <span className="truncate text-footnote text-muted">{`${indexKindWord(entry.kind)} · ${publisherLine(entry.publisher)}`}</span>
      </div>
      <p className="line-clamp-2 text-footnote text-foreground">{entry.description}</p>
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5">
        {entry.unsafe ? <StatusWord tone="bad">{DiscoverLines.unsafe}</StatusWord> : <span className="text-footnote text-muted">{latestLine(entry)}</span>}
        {installed !== undefined && <StatusWord tone="good">{installed}</StatusWord>}
        <AgentsLine agents={entry.agents} />
      </div>
      <p className="truncate text-footnote text-muted">{needsSummaryLine(entry.needs)}</p>
      {warnings !== undefined && <StatusWord tone="attention">{warnings}</StatusWord>}
      <div className="flex flex-wrap gap-2 border-t border-panel-edge pt-3">
        <Button onClick={view}>{DiscoverLines.view}</Button>
      </div>
    </Card>
  );
}

/** The agents a listing supports, their logos ahead of the line that names them. */
function AgentsLine({ agents, className = 'text-footnote text-muted' }: { agents: readonly string[]; className?: string }) {
  return (
    <span className={`inline-flex items-center gap-1.5 ${className}`}>
      <AgentLogos agents={agents.map((agent) => ({ agent, name: agentLabel(agent) }))} />
      {supportedAgentsLine(agents)}
    </span>
  );
}

/** One listing on the whole page, with its digest and every version, the unsafe ones marked and never offered. */
function Listing({ parts, entry, width, back, said }: { parts: SettingsParts; entry: IndexEntryView; width: WidthClass; back: () => void; said: (outcome: IndexOutcome) => void }) {
  const { index } = parts;
  const twoColumns = width === 'wide' || width === 'medium';
  const yanked = yankedLine(entry.yanked);
  const installed = installedLine(entry);
  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-wrap items-center gap-2.5">
        <Button icon={ArrowLeft} onClick={back}>
          {DiscoverLines.back}
        </Button>
        <span className="min-w-0 flex-1 truncate text-headline font-semibold text-foreground">{entry.name}</span>
        <span className="text-footnote text-muted">{indexKindWord(entry.kind)}</span>
      </div>
      <div className={twoColumns ? 'grid grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)] gap-6' : 'flex flex-col gap-6'}>
        <div className="flex min-w-0 flex-col gap-6">
          <p className="text-body text-foreground">{entry.description}</p>
          <Facts
            facts={[
              [DiscoverLines.publisher, entry.publisher.name],
              [DiscoverLines.category, entry.category ?? DiscoverLines.noneGiven],
              [DiscoverLines.license, entry.license ?? DiscoverLines.noneGiven],
              [DiscoverLines.agents, <AgentsLine agents={entry.agents} className="" />],
              ...(installed === undefined ? [] : [[DiscoverLines.here, installed] as const]),
            ]}
          />
          <Section title={DiscoverLines.needs}>
            <Needs needs={entry.needs} />
          </Section>
          <Section title={DiscoverLines.versions}>
            <Panel>
              {entry.latest !== undefined && <Row title={`v${entry.latest.version}`} caption={DiscoverLines.newest} trailing={<StatusWord tone="good">{DiscoverLines.latest}</StatusWord>} />}
              {entry.yanked.map((version) => (
                <Row key={version} title={`v${version}`} caption={DiscoverLines.yankedCaption} trailing={<StatusWord tone="bad">{DiscoverLines.unsafeWord}</StatusWord>} />
              ))}
            </Panel>
            {yanked !== undefined && <p className="text-footnote text-muted">{yanked}</p>}
          </Section>
        </div>
        <div className="flex min-w-0 flex-col gap-6">
          <div className="flex flex-col gap-2.5 rounded-card border border-panel-edge bg-card p-3.5">
            <Warnings warnings={entry.warnings} />
            <p className="text-footnote text-muted">{needsSummaryLine(entry.needs)}</p>
            {canInstall(entry) ? (
              <div>
                <Button kind="primary" icon={Download} disabled={index.busy === entry.name} onClick={() => void index.install(entry.name, entry.latest?.version).then(said)}>
                  {index.busy === entry.name ? DiscoverLines.installing : DiscoverLines.install(latestLine(entry))}
                </Button>
              </div>
            ) : (
              <StatusWord tone="bad">{DiscoverLines.nothingToInstall}</StatusWord>
            )}
            <p className="text-footnote text-muted">{installWaitsLine(entry.kind, parts.words.keyTitle)}</p>
            <p className="text-footnote text-muted">{DiscoverLines.digestNote}</p>
          </div>
          {entry.latest !== undefined && <Facts facts={[[DiscoverLines.digest, entry.latest.digest]]} mono />}
        </div>
      </div>
    </div>
  );
}
