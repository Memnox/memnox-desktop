import type { McpHubServerView, McpHubView } from '@memnox/core/wire';
import { CircleCheck, Clock, Fingerprint, Folder, KeyRound, Plug, Plus, RefreshCw, TriangleAlert } from 'lucide-react';
import { useEffect, useState, type ReactNode } from 'react';
import { McpHub, type HubOutcome, type McpPress } from '../../../core/application/mcp-hub';
import type { Route, WidthClass } from '../../../core/domain/destinations';
import { agentLabel, agentsOnce, McpHubPageLines, BRING_IN, BRINGING_IN, SERVER_CARD_MIN, pressLine, transportWord, usedBy, callsLine, fromOrganization, headerLines, healthWords, launchLine, missingSecrets, ORGANIZATION_LINE, ORGANIZATION_WORD, GIVE_EVERYWHERE, PROJECT_ONLY_LINE, projectHelp, projectOnlyHelp, projectsFor, reachCaption, reachOf, secretsAcross, toolsLine, WORKSPACES_LINK } from '../../../core/domain/mcp-hub-lines';
import { ago } from '../../../core/domain/session-text';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { YourAppsPage } from '../../settings/pages/YourAppsPage';
import { AddServerDialog } from './AddServerDialog';
import { Inspector, ScopeChip } from '../widgets';
import { serverScope } from '../../../core/domain/scope-lines';
import { GoLink } from './HomePage';
import { usePicked } from '../inspector-host';
import { useShellChoices } from '../shell-choices';
import { inScope, NO_ORGANIZATION_ITEMS, ORGANIZATION_READ_ONLY } from '../../../core/domain/shell-lines';
import { BrandLogo, Button, CardGrid, Checkbox, EmptyState, Input, Note, Panel, Pressable, ReadFailed, Row, SearchInput, Section, Spinner, StatusWord, TruncatedText } from '../../kit';
import { PAGE_METRICS } from '../page-metrics';

/** The Mac's server search grows to its width and no further. */
const SEARCH_WIDTH = PAGE_METRICS.hubSearch;

/** A spinner beside 12 point words, smaller than a button's. */
const SMALL_SPINNER = 10;

/** Logos stacked on a card or heading a column, and the plug standing in for one. */
const SMALL_LOGO = 18;

/** An agent's logo at the head of a detail row. */
const ROW_LOGO = 22;

/** A key or a glyph at the head of a row, and the one beside a press's outcome. */
const ROW_GLYPH = 16;
const PRESS_GLYPH = 13;

/** The folder glyph on a project chip, as small as its words. */
const CHIP_GLYPH = 11;

/** A secret's field is as wide as a token's start needs. */
const SECRET_FIELD = 192;

/**
 * The MCP Hub: servers set up once and given to the agents the person chooses. Every config is written
 * by the runtime, a change that gives an agent more waits for a signature on the island, and a secret
 * is kept by this computer and never shown again.
 */
export function McpHubPage({ parts, tab, width, go }: { parts: SettingsParts; tab: string | undefined; width: WidthClass; go: (route: Route) => void }) {
  const { hub } = parts;
  useObserved(hub);
  useEffect(() => {
    if (tab !== 'apps') void hub.refresh();
  }, [tab]);
  // A signed proposal or a call through a hub server changes the stream, and the hub is read again.
  useEffect(() => parts.host.onHomeStale?.(() => void hub.refresh()), []);
  const [note, setNote] = useState<string | undefined>(undefined);
  const said = (outcome: HubOutcome) => setNote(noteOf(outcome, parts.words.keyTitle));
  // A server given in one project only is changed in that project's settings, which Workspaces shows.
  const workspaces = () => go({ destination: 'workspaces', tab: 'projects' });

  if (tab === 'apps') return <YourAppsPage parts={parts} />;
  const view = hub.hub;
  if (view === undefined) return hub.unreadable ? <ReadFailed what={McpHubPageLines.readWhat} retry={() => void hub.refresh()} /> : null;
  return (
    <>
      {note !== undefined && <Note>{note}</Note>}
      {tab === 'clients' && <Clients parts={parts} view={view} said={said} workspaces={workspaces} />}
      {tab === 'secrets' && <Secrets parts={parts} view={view} said={said} />}
      {(tab === 'servers' || tab === undefined) && <Servers parts={parts} view={view} width={width} said={said} noted={setNote} workspaces={workspaces} />}
    </>
  );
}

function noteOf(outcome: HubOutcome, keyTitle: string): string {
  if (outcome.kind === 'proposed') return McpHubPageLines.waiting(keyTitle);
  if (outcome.kind === 'failed') return outcome.why;
  return outcome.note;
}

function Servers({ parts, view, width, said, noted, workspaces }: { parts: SettingsParts; view: McpHubView; width: WidthClass; said: (outcome: HubOutcome) => void; noted: (line: string | undefined) => void; workspaces: () => void }) {
  const { hub } = parts;
  const [query, setQuery] = useState('');
  const [chosen, choose] = usePicked();
  const [adding, setAdding] = useState(false);
  const { scope, connected } = useShellChoices();
  const words = query.trim().toLowerCase();
  const scoped = inScope(view.servers, scope, fromOrganization);
  const shown = scoped.filter((server) => words === '' || `${server.name} ${server.description ?? ''}`.toLowerCase().includes(words));
  const picked = view.servers.find((server) => server.name === chosen);
  return (
    <div className="flex min-h-0">
      <div className="flex min-w-0 flex-1 flex-col gap-5">
        <div className="flex flex-wrap items-center gap-2.5">
          <div className="w-full flex-1" style={{ maxWidth: SEARCH_WIDTH }}>
            <SearchInput value={query} placeholder={McpHubPageLines.search} onChange={setQuery} />
          </div>
          <span className="flex-1" />
          <Button icon={RefreshCw} disabled={hub.busy === 'sync'} onClick={() => void hub.sync().then(said)} title={McpHubPageLines.syncHelp}>
            {McpHubPageLines.sync}
          </Button>
          <Button kind="primary" icon={Plus} onClick={() => setAdding(true)}>
            {McpHubPageLines.add}
          </Button>
        </div>
        {connected && scope === 'organization' && <p className="text-footnote text-muted">{scoped.length === 0 ? NO_ORGANIZATION_ITEMS : ORGANIZATION_READ_ONLY}</p>}
        {scoped.length === 0 ? (
          scope !== 'organization' && (
          <EmptyState
            icon={Plug}
            title={McpHubPageLines.emptyTitle}
            body={McpHubPageLines.emptyBody}
            action={<Button kind="primary" icon={Plus} onClick={() => setAdding(true)}>{McpHubPageLines.add}</Button>}
          />
          )
        ) : (
          <CardGrid min={SERVER_CARD_MIN}>
            {shown.map((server) => (
              <ServerCard key={server.name} parts={parts} server={server} chosen={server.name === chosen} pick={() => choose(server.name)} said={said} />
            ))}
          </CardGrid>
        )}
        <Found parts={parts} view={view} said={said} />
        <Drift view={view} />
      </div>
      {picked !== undefined && (
        <Inspector title={picked.name} width={width} close={() => choose(undefined)} item={picked.name}>
          <ServerDetail parts={parts} view={view} server={picked} said={said} removed={() => choose(undefined)} workspaces={workspaces} />
        </Inspector>
      )}
      {adding && <AddServerDialog parts={parts} agents={view.agents.map((each) => each.agent)} close={() => setAdding(false)} noted={noted} />}
    </div>
  );
}

/** Most logos a card stacks before the names beside them carry the rest. */
const LOGOS_SHOWN = 4;

/**
 * One server as the Mac's card draws it: the name with its transport pill and how it is reached in mono beneath,
 * how it stands with its tools and Test, then who has it by logo and name, Governed, and whose it is.
 */
function ServerCard({ parts, server, chosen, pick, said }: { parts: SettingsParts; server: McpHubServerView; chosen: boolean; pick: () => void; said: (outcome: HubOutcome) => void }) {
  const { hub } = parts;
  const health = hub.testOf(server.name) ?? server.health;
  const words = healthWords(health);
  const missing = missingSecrets(server);
  const agents = agentsOnce(server);
  const testing = hub.press(server.name)?.kind === 'working';
  return (
    <div
      role="button"
      tabIndex={0}
      onClick={pick}
      onKeyDown={(event) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          pick();
        }
      }}
      aria-pressed={chosen}
      className={`mx-focus flex cursor-pointer flex-col gap-3 rounded-card border bg-card p-4 text-left transition-colors hover:bg-hover ${chosen ? 'border-primary' : 'border-panel-edge'}`}
    >
      <div className="flex min-w-0 flex-col gap-1">
        <div className="flex items-baseline gap-2">
          <span className="min-w-0 flex-1 truncate text-headline font-semibold text-foreground">{server.name}</span>
          <StatusWord tone="quiet">{transportWord(server)}</StatusWord>
        </div>
        <MiddleCutLine text={launchLine(server)} title={[launchLine(server), ...(server.args ?? [])].join(' ')} />
        {server.description !== undefined && <span className="truncate text-footnote text-muted">{server.description}</span>}
      </div>
      <div className="border-t border-panel-edge" />
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5">
        {missing.length > 0 ? <StatusWord tone="bad">{McpHubPageLines.needsSecret}</StatusWord> : <StatusWord tone={words.tone}>{words.word}</StatusWord>}
        <span className="whitespace-nowrap text-meta text-faint">{toolsLine(health.tools?.length ?? server.toolCount)}</span>
        <span className="flex-1" />
        <Pressable
          disabled={testing}
          title={McpHubPageLines.testHelp}
          onClick={(event) => {
            event.stopPropagation();
            void hub.test(server.name).then(said);
          }}
          className="mx-focus inline-flex cursor-pointer items-center gap-1 text-meta font-medium text-primary hover:underline disabled:cursor-default disabled:no-underline"
        >
          {testing && <Spinner size={SMALL_SPINNER} />}
          {testing ? McpHubPageLines.testing : McpHubPageLines.test}
        </Pressable>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <span className="flex min-w-0 flex-1 items-center gap-2">
          {agents.length > 0 && (
            <span className="flex shrink-0 -space-x-1.5" aria-hidden>
              {agents.slice(0, LOGOS_SHOWN).map((agent) => (
                <BrandLogo key={agent} agent={agent} name={agentLabel(agent)} size={SMALL_LOGO} className="ring-2 ring-card" />
              ))}
            </span>
          )}
          <span className={`truncate text-meta ${agents.length === 0 ? 'text-faint' : 'text-muted'}`} title={usedBy(server)}>
            {usedBy(server)}
          </span>
        </span>
        {server.governed ? <StatusWord tone="good">{McpHubPageLines.governed}</StatusWord> : <StatusWord tone="attention">{McpHubPageLines.notGoverned}</StatusWord>}
        <ScopeChip scope={serverScope(server)} />
      </div>
      {(server.projects ?? []).length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {agents.flatMap((agent) => projectsFor(server, agent).map((project) => <ProjectChip key={`${agent}/${project.path}`} agent={agent} {...project} />))}
        </div>
      )}
    </div>
  );
}

/** A line in mono cut in its middle, as the Mac cuts it, so both ends of a long command or address read. */
function MiddleCutLine({ text, title }: { text: string; title: string }) {
  return (
    <span title={title} className="block min-w-0 overflow-hidden font-code text-footnote text-muted">
      <TruncatedText middle text={text} />
    </span>
  );
}

/** Where the last press on one row stands, in that row: asking the runtime, the island it waits on, or what it came to. */
function PressLine({ press, keyTitle }: { press: McpPress | undefined; keyTitle: string }) {
  if (press?.kind === 'working')
    return (
      <span className="flex items-center gap-1.5 text-meta text-muted">
        <Spinner size={SMALL_SPINNER} />
        {McpHubPageLines.asking}
      </span>
    );
  const line = pressLine(press, keyTitle);
  if (line === undefined) return null;
  const Icon = press?.kind === 'waiting' ? Fingerprint : line.tone === 'good' ? CircleCheck : line.tone === 'bad' ? TriangleAlert : Clock;
  const ink = line.tone === 'good' ? 'text-success' : line.tone === 'bad' ? 'text-destructive' : 'text-muted';
  return (
    <span role="status" className={`flex items-start gap-1.5 text-meta select-text ${ink}`}>
      <Icon size={PRESS_GLYPH} className="mt-0.5 shrink-0" aria-hidden />
      <span className="min-w-0 break-words">{line.text}</span>
    </span>
  );
}

function ServerDetail({ parts, view, server, said, removed, workspaces }: { parts: SettingsParts; view: McpHubView; server: McpHubServerView; said: (outcome: HubOutcome) => void; removed: () => void; workspaces: () => void }) {
  const { hub } = parts;
  const health = hub.testOf(server.name) ?? server.health;
  const words = healthWords(health);
  const tools = health.tools ?? server.tools ?? [];
  const missing = missingSecrets(server);
  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-1.5">
        <StatusWord tone={missing.length > 0 ? 'bad' : words.tone}>{missing.length > 0 ? McpHubPageLines.needs(missing) : words.word}</StatusWord>
        {health.checkedAt !== undefined && <span className="text-footnote text-muted">{McpHubPageLines.tested(ago(health.checkedAt, Date.now()))}</span>}
        {health.error !== undefined && <span className="text-footnote break-words text-destructive">{health.error}</span>}
        <span className="font-code text-micro break-all text-muted">{[launchLine(server), ...(server.args ?? [])].join(' ')}</span>
        <span className="text-footnote text-muted">{callsLine(server.callsThisWeek)}</span>
      </div>
      <Button disabled={hub.busy === server.name} onClick={() => void hub.test(server.name).then(said)}>
        {hub.busy === server.name ? McpHubPageLines.testing : McpHubPageLines.testConnection}
      </Button>

      {fromOrganization(server) ? (
        <Section title="Agents">
          <StatusWord tone="quiet">{ORGANIZATION_WORD}</StatusWord>
          {server.agents.length > 0 && (
            <Panel>
              {[...new Set(server.agents)].map((agent) => (
                <Row key={agent} leading={<BrandLogo agent={agent} name={agentLabel(agent)} size={ROW_LOGO} />} title={agentLabel(agent)} caption={reachCaption(server, agent)} trailing={<ProjectChips server={server} agent={agent} />} />
              ))}
            </Panel>
          )}
          <p className="text-footnote text-muted">{ORGANIZATION_LINE}</p>
        </Section>
      ) : (
        <Section title="Agents">
          <Panel>
            {view.agents.map(({ agent }) => {
              const reach = reachOf(server, agent);
              // Taking away removes only the everywhere assignment, so a project only one is offered Give alone.
              const on = reach === 'everywhere';
              const pair = McpHub.pair(server.name, agent);
              const press = hub.press(pair);
              return (
                <div key={agent}>
                  <Row
                    leading={<BrandLogo agent={agent} name={agentLabel(agent)} size={ROW_LOGO} />}
                    title={agentLabel(agent)}
                    caption={reachCaption(server, agent)}
                    trailing={
                      <>
                        <ProjectChips server={server} agent={agent} />
                        {reach === 'projects' && <GoLink onClick={workspaces}>{WORKSPACES_LINK}</GoLink>}
                        <Button
                          disabled={press?.kind === 'working'}
                          onClick={() => {
                            hub.clear(pair);
                            void hub.assign(server.name, agent, !on).then(said);
                          }}
                        >
                          {on ? McpHubPageLines.takeAway : reach === 'projects' ? GIVE_EVERYWHERE : McpHubPageLines.give}
                        </Button>
                      </>
                    }
                  />
                  {press !== undefined && press.kind !== 'working' && (
                    <div className="px-4 pb-3">
                      <PressLine press={press} keyTitle={parts.words.keyTitle} />
                    </div>
                  )}
                </div>
              );
            })}
          </Panel>
          <p className="text-footnote text-muted">{McpHubPageLines.givingWaits(parts.words.keyTitle)}</p>
          {(server.projects ?? []).length > 0 && <p className="text-footnote text-muted">{PROJECT_ONLY_LINE}</p>}
        </Section>
      )}

      {(server.headerNames ?? []).length > 0 && (
        <Section title={McpHubPageLines.headers}>
          <Panel>
            {headerLines(server).map((header) => (
              <Row
                key={header.name}
                title={<span className="font-code">{header.name}</span>}
                trailing={header.held === undefined ? undefined : <StatusWord tone={header.held ? 'good' : 'bad'}>{header.held ? McpHubPageLines.secretKept : McpHubPageLines.secretNotSet}</StatusWord>}
              />
            ))}
          </Panel>
          <p className="text-footnote text-muted">{McpHubPageLines.headersNote}</p>
        </Section>
      )}

      {Object.keys(server.secretsHeld).length > 0 && (
        <Section title={McpHubPageLines.credentials}>
          <Panel>
            {Object.entries(server.secretsHeld).map(([name, held]) => (
              <Row key={name} leading={<KeyRound size={ROW_GLYPH} className="text-muted" />} title={name} trailing={<StatusWord tone={held ? 'good' : 'bad'}>{held ? McpHubPageLines.keptHere : McpHubPageLines.notSet}</StatusWord>} />
            ))}
          </Panel>
          <p className="text-footnote text-muted">{McpHubPageLines.credentialsNote}</p>
        </Section>
      )}

      <Section title={McpHubPageLines.tools}>
        {tools.length === 0 ? (
          <p className="text-footnote text-muted">{McpHubPageLines.noTools}</p>
        ) : (
          <Panel>
            {tools.map((tool) => (
              <Row key={tool.name} title={<span className="font-code">{tool.name}</span>} caption={tool.description} />
            ))}
          </Panel>
        )}
      </Section>

      {/* Set apart at the end, away from the routine controls; an organization's server is removed in Memnox Cloud. */}
      {!fromOrganization(server) && (
        <div className="border-t border-panel-edge pt-4">
          <Button
            disabled={hub.busy === server.name}
            onClick={() =>
              void hub.removeServer(server.name).then((outcome) => {
                said(outcome);
                if (outcome.kind === 'done') removed();
              })
            }
          >
            {McpHubPageLines.removeEverywhere}
          </Button>
        </div>
      )}
    </div>
  );
}

/** Servers an agent already had before the hub, offered to bring in and never touched until then. */
function Found({ parts, view, said }: { parts: SettingsParts; view: McpHubView; said: (outcome: HubOutcome) => void }) {
  const { hub } = parts;
  if (view.found.length === 0) return null;
  return (
    <Section title={McpHubPageLines.found(view.found.length)}>
      <Panel>
        {view.found.map((entry) => (
          <div key={`${entry.path}/${entry.name}`}>
          <Row
            leading={entry.agent === undefined ? <Plug size={SMALL_LOGO} className="text-muted" /> : <BrandLogo agent={entry.agent} name={agentLabel(entry.agent)} size={ROW_LOGO} />}
            title={entry.name}
            caption={`${entry.agent === undefined ? McpHubPageLines.shared : agentLabel(entry.agent)} · ${entry.path}`}
            trailing={
              entry.agent === undefined ? (
                <span className="text-footnote text-muted">{McpHubPageLines.repositoryFile}</span>
              ) : (
                <Button disabled={hub.press(McpHub.found(entry.name, entry.agent))?.kind === 'working'} onClick={() => entry.agent !== undefined && void hub.importServer(entry.agent, entry.name).then(said)}>
                  {hub.press(McpHub.found(entry.name, entry.agent))?.kind === 'working' && <Spinner size={SMALL_SPINNER} />}
                  {hub.press(McpHub.found(entry.name, entry.agent))?.kind === 'working' ? BRINGING_IN : BRING_IN}
                </Button>
              )
            }
          />
          {entry.agent !== undefined && hub.press(McpHub.found(entry.name, entry.agent))?.kind !== 'working' && hub.press(McpHub.found(entry.name, entry.agent)) !== undefined && (
            <div className="px-4 pb-3">
              <PressLine press={hub.press(McpHub.found(entry.name, entry.agent))} keyTitle={parts.words.keyTitle} />
            </div>
          )}
          </div>
        ))}
      </Panel>
      <p className="text-footnote text-muted">{McpHubPageLines.bringingNote}</p>
    </Section>
  );
}

/** Lines the hub wrote that a person changed since, left as they are and said. */
function Drift({ view }: { view: McpHubView }) {
  const entries = [...view.drifted, ...view.skipped];
  if (entries.length === 0) return null;
  return (
    <Section title={McpHubPageLines.leftAlone}>
      <Panel>
        {entries.map((entry) => (
          <Row
            key={`${entry.path}/${entry.name}/${entry.kind ?? entry.reason ?? ''}`}
            title={entry.name}
            caption={`${entry.agent === undefined ? '' : `${agentLabel(entry.agent)} · `}${entry.reason ?? (entry.kind === 'removed' ? McpHubPageLines.removedLine : McpHubPageLines.changedLine)}`}
            trailing={<StatusWord tone="attention">{McpHubPageLines.yoursNow}</StatusWord>}
          />
        ))}
      </Panel>
    </Section>
  );
}

/** Agents across, servers down: one place to see and change who has what. */
function Clients({ parts, view, said, workspaces }: { parts: SettingsParts; view: McpHubView; said: (outcome: HubOutcome) => void; workspaces: () => void }) {
  const { hub } = parts;
  if (view.servers.length === 0 || view.agents.length === 0) {
    return <EmptyState icon={Plug} title={McpHubPageLines.nothingTitle} body={McpHubPageLines.nothingBody} />;
  }
  const inProjects = view.servers.some((server) => (server.projects ?? []).length > 0);
  return (
    <>
      <div className="overflow-x-auto rounded-card border border-panel-edge">
        <table className="w-full border-collapse text-body">
          <thead>
            <tr className="bg-card">
              <th scope="col" className="px-3.5 py-2.5 text-left text-footnote font-semibold text-muted">{McpHubPageLines.server}</th>
              {view.agents.map(({ agent }) => (
                <th key={agent} scope="col" className="px-3 py-2.5 text-footnote font-semibold whitespace-nowrap text-muted">
                  <span className="inline-flex items-center gap-1.5">
                    <BrandLogo agent={agent} name={agentLabel(agent)} size={SMALL_LOGO} />
                    {agentLabel(agent)}
                  </span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {view.servers.map((server) => (
              <tr key={server.name} className="border-t border-panel-edge">
                <th scope="row" className="px-3.5 py-2.5 text-left font-medium whitespace-nowrap text-foreground">{server.name}</th>
                {view.agents.map(({ agent }) => {
                  const reach = reachOf(server, agent);
                  const on = reach === 'everywhere';
                  if (reach === 'projects') {
                    const help = projectOnlyHelp(server, agent);
                    // Unticked, since ticking gives it everywhere; the project assignment is changed in Projects.
                    return (
                      <td key={agent} className="px-3 py-2.5 text-center">
                        <span className="inline-flex items-center gap-1.5">
                          <Checkbox
                            checked={false}
                            disabled={fromOrganization(server) || hub.busy === `${server.name}/${agent}`}
                            title={fromOrganization(server) ? ORGANIZATION_LINE : GIVE_EVERYWHERE}
                            label={`${GIVE_EVERYWHERE}: ${McpHubPageLines.serverFor(server.name, agentLabel(agent))}`}
                            onToggle={() => void hub.assign(server.name, agent, true).then(said)}
                          />
                          <Pressable title={help} aria-label={help} className="mx-focus inline-flex cursor-pointer items-center gap-1.5" onClick={workspaces}>
                            <ProjectChips server={server} agent={agent} />
                          </Pressable>
                        </span>
                      </td>
                    );
                  }
                  return (
                    <td key={agent} className="px-3 py-2.5 text-center">
                      <span className="inline-flex items-center gap-1.5">
                        <Checkbox
                          checked={on}
                          disabled={fromOrganization(server) || hub.busy === `${server.name}/${agent}`}
                          title={fromOrganization(server) ? ORGANIZATION_LINE : undefined}
                          label={McpHubPageLines.serverFor(server.name, agentLabel(agent))}
                          onToggle={() => void hub.assign(server.name, agent, !on).then(said)}
                        />
                        <ProjectChips server={server} agent={agent} />
                      </span>
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {inProjects && (
        <div className="flex flex-col gap-1.5">
          <p className="text-footnote text-muted">{PROJECT_ONLY_LINE}</p>
          <GoLink onClick={workspaces}>{WORKSPACES_LINK}</GoLink>
        </div>
      )}
    </>
  );
}

/** One repository an agent was given a server in: its folder name, with whose it is and the full path on hover. */
function ProjectChip({ agent, name, path }: { agent: string; name: string; path: string }) {
  const help = projectHelp(agent, path);
  return (
    <span title={help} aria-label={help} className="inline-flex max-w-40 items-center gap-1 rounded-control border border-panel-edge bg-hover px-1.5 py-0.5 text-micro text-muted">
      <Folder size={CHIP_GLYPH} aria-hidden className="shrink-0" />
      <span className="truncate">{name}</span>
    </span>
  );
}

/** Every repository one agent was given a server in, or nothing for one given it everywhere. */
function ProjectChips({ server, agent }: { server: McpHubServerView; agent: string }) {
  const projects = projectsFor(server, agent);
  if (projects.length === 0) return null;
  return (
    <>
      {projects.map((project) => (
        <ProjectChip key={project.path} agent={agent} {...project} />
      ))}
    </>
  );
}

/** Each secret by name, where it is used and whether this computer holds it. A value is typed in once and never read back. */
function Secrets({ parts, view, said }: { parts: SettingsParts; view: McpHubView; said: (outcome: HubOutcome) => void }) {
  const secrets = secretsAcross(view.servers);
  if (secrets.length === 0) {
    return <EmptyState icon={KeyRound} title={McpHubPageLines.noSecretsTitle} body={McpHubPageLines.noSecretsBody} />;
  }
  return (
    <Panel>
      {secrets.map((secret) => (
        <SecretRow key={secret.name} name={secret.name} held={secret.held} usedBy={secret.usedBy} parts={parts} said={said} />
      ))}
    </Panel>
  );
}

function SecretRow({ name, held, usedBy, parts, said }: { name: string; held: boolean; usedBy: string[]; parts: SettingsParts; said: (outcome: HubOutcome) => void }) {
  const { hub } = parts;
  const [editing, setEditing] = useState(false);
  const [value, setValue] = useState('');
  const save = () => {
    void hub.setSecret(name, value).then((outcome) => {
      said(outcome);
      setValue('');
      setEditing(false);
    });
  };
  const trailing: ReactNode = editing ? (
    <span className="flex items-center gap-2">
      <Input type="password" autoComplete="off" width={SECRET_FIELD} value={value} onValue={setValue} onSubmit={() => value !== '' && save()} aria-label={McpHubPageLines.valueOf(name)} />
      <Button kind="primary" disabled={value === '' || hub.busy === name} onClick={save}>
        {McpHubPageLines.keep}
      </Button>
    </span>
  ) : (
    <span className="flex items-center gap-2">
      <StatusWord tone={held ? 'good' : 'bad'}>{held ? McpHubPageLines.kept : McpHubPageLines.notSet}</StatusWord>
      <Button onClick={() => setEditing(true)}>{held ? McpHubPageLines.replace : McpHubPageLines.set}</Button>
      {held && (
        <Button disabled={hub.busy === name} onClick={() => void hub.removeSecret(name).then(said)}>
          {McpHubPageLines.remove}
        </Button>
      )}
    </span>
  );
  return <Row leading={<KeyRound size={ROW_GLYPH} className="text-muted" />} title={name} caption={McpHubPageLines.usedBy(usedBy)} trailing={trailing} />;
}
