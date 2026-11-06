import type { CommunityIndexView, IndexEntryView, IndexNeedsView } from '@memnox/core/wire';
import { ArrowLeft, Download, Globe, RefreshCw, Store } from 'lucide-react';
import { useEffect, useState } from 'react';
import { SETTING_SOURCE, type IndexOutcome, type IndexSourceOutcome } from '../../../core/application/community-index';
import type { WidthClass } from '../../../core/domain/destinations';
import {
  canInstall,
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
  type IndexKindFilter,
} from '../../../core/domain/index-lines';
import { KitButton, KitField, SearchField } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { CardGrid, EmptyState, Panel, ReadFailed, Row, Section, StatusWord } from '../widgets';
import { agentLabel } from '../../../core/domain/mcp-hub-lines';
import { AgentLogos } from '../../kit/logos';
import { Facts } from './SkillsPage';

const KINDS: readonly { id: IndexKindFilter; title: string }[] = [
  { id: 'all', title: 'Everything' },
  { id: 'skill', title: 'Skills' },
  { id: 'rule_pack', title: 'Rule packs' },
];

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
    const handle = setTimeout(() => void index.refresh({ ...index.filter, query }), 250);
    return () => clearTimeout(handle);
  }, [query]);

  const view = index.index;
  if (view === undefined) return index.unreadable ? <ReadFailed what="the community index" retry={() => void index.refresh()} /> : null;
  const picked = view.entries.find((entry) => entry.id === opened);
  const status = note !== undefined && (
    <p role="status" className="rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote text-foreground">
      {note}
    </p>
  );
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
        <div className="w-full max-w-[320px] min-w-[180px] flex-1">
          <SearchField value={query} placeholder="Search skills and rule packs" onChange={setQuery} />
        </div>
        <span className="flex-1" />
        <KitButton icon={RefreshCw} disabled={index.busy === 'refresh'} onClick={() => void index.refresh(index.filter, true)} title="Read the index again now">
          Refresh
        </KitButton>
      </div>
      <div className="flex flex-wrap items-center gap-1.5" role="tablist" aria-label="Kind">
        {KINDS.map((kind) => (
          <Chip key={kind.id} on={index.filter.kind === kind.id} pick={() => void index.refresh({ ...index.filter, kind: kind.id })}>
            {kind.title}
          </Chip>
        ))}
        {categories.length > 0 && <span aria-hidden className="mx-1 h-4 w-px bg-panel-edge" />}
        {categories.length > 0 && (
          <Chip on={category === undefined} pick={() => setCategory(undefined)}>
            Every category
          </Chip>
        )}
        {categories.map((each) => (
          <Chip key={each} on={category === each} pick={() => setCategory(each)}>
            {each}
          </Chip>
        ))}
      </div>
      <p className="text-footnote text-muted">{indexStateLine(view, Date.now())}</p>
      {shown.length === 0 ? (
        <EmptyState icon={Store} title="Nothing in the index matches" body="Try fewer words, another kind or every category, or read the index again with Refresh." />
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
    <Section title="Where listings come from" trailing={view.marketplace ? <StatusWord tone="good">Memnox marketplace</StatusWord> : <StatusWord tone="attention">An index you named</StatusWord>}>
      <div className="flex flex-col gap-3 rounded-xl border border-panel-edge bg-card p-3.5">
        <p className="text-footnote text-foreground">{indexSourceLine(view)}</p>
        <div className="flex flex-wrap items-center gap-2">
          <KitField value={address} placeholder="https://example.com/index.json" onChange={setAddress} onSubmit={propose} className="max-w-[360px] flex-1" />
          <KitButton icon={Globe} disabled={!usable || busy} onClick={propose}>
            Propose this index
          </KitButton>
        </div>
        {typed && !usable && <p className="text-footnote text-warm">{INDEX_ADDRESS_WANTED}</p>}
        <p className="text-footnote text-muted">{`Another index decides what can be installed here, so naming one waits on the island for your signature with ${parts.words.keyTitle}.`}</p>
        <div>
          <KitButton disabled={view.marketplace || busy} onClick={() => void index.setSource().then(said)}>
            Use the Memnox marketplace
          </KitButton>
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
              <dd key={item} className="font-mono text-micro break-all text-foreground">
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

function Chip({ on, pick, children }: { on: boolean; pick: () => void; children: string }) {
  return (
    <button
      type="button"
      role="tab"
      aria-selected={on}
      onClick={pick}
      className={`mx-focus cursor-pointer inline-flex h-8 items-center rounded-lg border px-3 text-body-sm ${on ? 'border-primary/45 bg-primary/[0.07] font-medium text-foreground' : 'border-panel-edge bg-card text-muted hover:bg-hover hover:text-foreground'}`}
    >
      {children}
    </button>
  );
}

function ListingCard({ entry, view }: { entry: IndexEntryView; view: () => void }) {
  const installed = installedLine(entry);
  const warnings = warningsCountLine(entry.warnings);
  return (
    <article className="flex flex-col gap-3 rounded-xl border border-panel-edge bg-card p-4">
      <div className="flex min-w-0 flex-col gap-0.5">
        <span className="truncate text-headline font-semibold text-foreground">{entry.name}</span>
        <span className="truncate text-footnote text-muted">{`${indexKindWord(entry.kind)} · ${publisherLine(entry.publisher)}`}</span>
      </div>
      <p className="line-clamp-2 text-footnote text-foreground">{entry.description}</p>
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5">
        {entry.unsafe ? <StatusWord tone="bad">Marked unsafe</StatusWord> : <span className="text-footnote text-muted">{latestLine(entry)}</span>}
        {installed !== undefined && <StatusWord tone="good">{installed}</StatusWord>}
        <AgentsLine agents={entry.agents} />
      </div>
      <p className="truncate text-footnote text-muted">{needsSummaryLine(entry.needs)}</p>
      {warnings !== undefined && <StatusWord tone="attention">{warnings}</StatusWord>}
      <div className="flex flex-wrap gap-2 border-t border-panel-edge pt-3">
        <KitButton onClick={view}>View listing</KitButton>
      </div>
    </article>
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
        <KitButton icon={ArrowLeft} onClick={back}>
          Discover
        </KitButton>
        <span className="min-w-0 flex-1 truncate text-headline font-semibold text-foreground">{entry.name}</span>
        <span className="text-footnote text-muted">{indexKindWord(entry.kind)}</span>
      </div>
      <div className={twoColumns ? 'grid grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)] gap-6' : 'flex flex-col gap-6'}>
        <div className="flex min-w-0 flex-col gap-6">
          <p className="text-body text-foreground">{entry.description}</p>
          <Facts
            facts={[
              ['Publisher', entry.publisher.name],
              ['Category', entry.category ?? 'None given'],
              ['License', entry.license ?? 'None given'],
              ['Agents', <AgentsLine agents={entry.agents} className="" />],
              ...(installed === undefined ? [] : [['Here', installed] as const]),
            ]}
          />
          <Section title="What it needs">
            <Needs needs={entry.needs} />
          </Section>
          <Section title="Versions">
            <Panel>
              {entry.latest !== undefined && <Row title={`v${entry.latest.version}`} caption="The newest version not marked unsafe" trailing={<StatusWord tone="good">Latest</StatusWord>} />}
              {entry.yanked.map((version) => (
                <Row key={version} title={`v${version}`} caption="Marked unsafe since it was published, so it is never installed" trailing={<StatusWord tone="bad">Unsafe</StatusWord>} />
              ))}
            </Panel>
            {yanked !== undefined && <p className="text-footnote text-muted">{yanked}</p>}
          </Section>
        </div>
        <div className="flex min-w-0 flex-col gap-6">
          <div className="flex flex-col gap-2.5 rounded-xl border border-panel-edge bg-card p-3.5">
            <Warnings warnings={entry.warnings} />
            <p className="text-footnote text-muted">{needsSummaryLine(entry.needs)}</p>
            {canInstall(entry) ? (
              <div>
                <KitButton kind="primary" icon={Download} disabled={index.busy === entry.name} onClick={() => void index.install(entry.name, entry.latest?.version).then(said)}>
                  {index.busy === entry.name ? 'Installing' : `Install ${latestLine(entry)}`}
                </KitButton>
              </div>
            ) : (
              <StatusWord tone="bad">Every version is marked unsafe, so there is nothing to install</StatusWord>
            )}
            <p className="text-footnote text-muted">{installWaitsLine(entry.kind, parts.words.keyTitle)}</p>
            <p className="text-footnote text-muted">The runtime checks what it downloads against the digest below before it writes anything.</p>
          </div>
          {entry.latest !== undefined && <Facts facts={[['Digest', entry.latest.digest]]} mono />}
        </div>
      </div>
    </div>
  );
}
