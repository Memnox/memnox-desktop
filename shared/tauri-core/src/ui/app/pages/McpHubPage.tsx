import type { McpHubServerView, McpHubView } from '@memnox/core/wire';
import { Folder, KeyRound, MoreVertical, Plug, Plus, RefreshCw } from 'lucide-react';
import { useEffect, useState, type ReactNode } from 'react';
import type { HubOutcome } from '../../../core/application/mcp-hub';
import type { Route, WidthClass } from '../../../core/domain/destinations';
import { agentLabel, agentsLine, callsLine, fromOrganization, healthWords, launchLine, missingSecrets, ORGANIZATION_LINE, ORGANIZATION_WORD, GIVE_EVERYWHERE, PROJECT_ONLY_LINE, projectHelp, projectOnlyHelp, projectsFor, reachCaption, reachOf, secretsAcross, toolsLine, WORKSPACES_LINK } from '../../../core/domain/mcp-hub-lines';
import { ago } from '../../../core/domain/session-text';
import { BrandLogo } from '../../kit/logos';
import { KitButton, SearchField } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { YourAppsPage } from '../../settings/pages/YourAppsPage';
import { AddServerDialog } from './AddServerDialog';
import { CardGrid, EmptyState, Inspector, Panel, ReadFailed, Row, ScopeChip, Section, StatusWord } from '../widgets';
import { serverScope } from '../../../core/domain/scope-lines';
import { GoLink } from './HomePage';
import { usePicked } from '../inspector-host';
import { useShellChoices } from '../shell-choices';
import { inScope, NO_ORGANIZATION_ITEMS, ORGANIZATION_READ_ONLY } from '../../../core/domain/shell-lines';

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
  if (view === undefined) return hub.unreadable ? <ReadFailed what="the MCP Hub" retry={() => void hub.refresh()} /> : null;
  return (
    <>
      {note !== undefined && (
        <p role="status" className="rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote text-foreground">
          {note}
        </p>
      )}
      {tab === 'clients' && <Clients parts={parts} view={view} said={said} workspaces={workspaces} />}
      {tab === 'secrets' && <Secrets parts={parts} view={view} said={said} />}
      {(tab === 'servers' || tab === undefined) && <Servers parts={parts} view={view} width={width} said={said} workspaces={workspaces} />}
    </>
  );
}

function noteOf(outcome: HubOutcome, keyTitle: string): string {
  if (outcome.kind === 'proposed') return `Waiting for you on the island: confirm it with ${keyTitle} and the runtime writes it.`;
  if (outcome.kind === 'failed') return outcome.why;
  return outcome.note;
}

function Servers({ parts, view, width, said, workspaces }: { parts: SettingsParts; view: McpHubView; width: WidthClass; said: (outcome: HubOutcome) => void; workspaces: () => void }) {
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
          <div className="w-full max-w-[320px] min-w-[180px] flex-1">
            <SearchField value={query} placeholder="Search servers" onChange={setQuery} />
          </div>
          <span className="flex-1" />
          <KitButton icon={RefreshCw} disabled={hub.busy === 'sync'} onClick={() => void hub.sync().then(said)} title="Write what the hub gives each agent into its config again">
            Sync
          </KitButton>
          <KitButton kind="primary" icon={Plus} onClick={() => setAdding(true)}>
            Add server
          </KitButton>
        </div>
        {connected && scope === 'organization' && <p className="text-footnote text-muted">{scoped.length === 0 ? NO_ORGANIZATION_ITEMS : ORGANIZATION_READ_ONLY}</p>}
        {scoped.length === 0 ? (
          scope !== 'organization' && (
          <EmptyState
            icon={Plug}
            title="No servers in the hub yet"
            body="Add a server once and give it to any agent, or bring in one an agent already has from Found on this computer below."
            action={<KitButton kind="primary" icon={Plus} onClick={() => setAdding(true)}>Add server</KitButton>}
          />
          )
        ) : (
          <CardGrid>
            {shown.map((server) => (
              <ServerCard key={server.name} server={server} chosen={server.name === chosen} pick={() => choose(server.name)} />
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
      {adding && <AddServerDialog parts={parts} agents={view.agents.map((each) => each.agent)} close={() => setAdding(false)} said={said} />}
    </div>
  );
}

function ServerCard({ server, chosen, pick }: { server: McpHubServerView; chosen: boolean; pick: () => void }) {
  const health = healthWords(server.health);
  const missing = missingSecrets(server);
  return (
    <button
      type="button"
      onClick={pick}
      aria-pressed={chosen}
      className={`mx-focus flex cursor-pointer flex-col gap-3 rounded-xl border bg-card p-4 text-left transition-colors hover:bg-hover ${chosen ? 'border-primary' : 'border-panel-edge'}`}
    >
      <div className="flex items-start gap-2">
        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
          <span className="truncate text-headline font-semibold text-foreground">{server.name}</span>
          <span className="truncate text-footnote text-muted">{server.description ?? launchLine(server)}</span>
        </div>
        <MoreVertical size={15} className="mt-1 shrink-0 text-muted" aria-hidden />
      </div>
      <div className="border-t border-panel-edge" />
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5">
        {missing.length > 0 ? <StatusWord tone="bad">Needs a secret</StatusWord> : <StatusWord tone={health.tone}>{health.word}</StatusWord>}
        <span className="text-footnote text-muted">{server.transport === 'http' ? 'Remote' : 'Local'}</span>
        <span className="text-footnote text-muted">{toolsLine(server.toolCount)}</span>
        <ScopeChip scope={serverScope(server)} />
      </div>
      <div className="flex items-center justify-between gap-2">
        <span className="flex -space-x-1.5" aria-label={agentsLine(server.agents.length)}>
          {server.agents.length === 0 ? <span className="text-footnote text-muted">{agentsLine(0)}</span> : server.agents.map((agent) => <BrandLogo key={agent} agent={agent} name={agentLabel(agent)} size={20} className="ring-2 ring-card" />)}
        </span>
        {server.governed ? <StatusWord tone="good">Governed</StatusWord> : <StatusWord tone="attention">Not governed</StatusWord>}
      </div>
      {(server.projects ?? []).length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {[...new Set(server.agents)].flatMap((agent) => projectsFor(server, agent).map((project) => <ProjectChip key={`${agent}/${project.path}`} agent={agent} {...project} />))}
        </div>
      )}
    </button>
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
        <StatusWord tone={missing.length > 0 ? 'bad' : words.tone}>{missing.length > 0 ? `Needs ${missing.join(', ')}` : words.word}</StatusWord>
        {health.checkedAt !== undefined && <span className="text-footnote text-muted">{`Tested ${ago(health.checkedAt, Date.now()) ?? 'just now'}`}</span>}
        {health.error !== undefined && <span className="text-footnote break-words text-destructive">{health.error}</span>}
        <span className="font-mono text-micro break-all text-muted">{[launchLine(server), ...(server.args ?? [])].join(' ')}</span>
        <span className="text-footnote text-muted">{callsLine(server.callsThisWeek)}</span>
      </div>
      <KitButton disabled={hub.busy === server.name} onClick={() => void hub.test(server.name).then(said)}>
        {hub.busy === server.name ? 'Testing' : 'Test connection'}
      </KitButton>

      {fromOrganization(server) ? (
        <Section title="Agents">
          <StatusWord tone="quiet">{ORGANIZATION_WORD}</StatusWord>
          {server.agents.length > 0 && (
            <Panel>
              {[...new Set(server.agents)].map((agent) => (
                <Row key={agent} leading={<BrandLogo agent={agent} name={agentLabel(agent)} size={22} />} title={agentLabel(agent)} caption={reachCaption(server, agent)} trailing={<ProjectChips server={server} agent={agent} />} />
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
              return (
                <Row
                  key={agent}
                  leading={<BrandLogo agent={agent} name={agentLabel(agent)} size={22} />}
                  title={agentLabel(agent)}
                  caption={reachCaption(server, agent)}
                  trailing={
                    <>
                      <ProjectChips server={server} agent={agent} />
                      {reach === 'projects' && <GoLink onClick={workspaces}>{WORKSPACES_LINK}</GoLink>}
                      <KitButton disabled={hub.busy === `${server.name}/${agent}`} onClick={() => void hub.assign(server.name, agent, !on).then(said)}>
                        {on ? 'Take away' : reach === 'projects' ? GIVE_EVERYWHERE : 'Give'}
                      </KitButton>
                    </>
                  }
                />
              );
            })}
          </Panel>
          <p className="text-footnote text-muted">{`Giving a server to an agent waits for your signature with ${parts.words.keyTitle}. Taking it away happens at once.`}</p>
          {(server.projects ?? []).length > 0 && <p className="text-footnote text-muted">{PROJECT_ONLY_LINE}</p>}
        </Section>
      )}

      {Object.keys(server.secretsHeld).length > 0 && (
        <Section title="Credentials">
          <Panel>
            {Object.entries(server.secretsHeld).map(([name, held]) => (
              <Row key={name} leading={<KeyRound size={16} className="text-muted" />} title={name} trailing={<StatusWord tone={held ? 'good' : 'bad'}>{held ? 'Kept by this computer' : 'Not set'}</StatusWord>} />
            ))}
          </Panel>
          <p className="text-footnote text-muted">A secret is never shown again. Replace one under Secrets.</p>
        </Section>
      )}

      <Section title="Tools">
        {tools.length === 0 ? (
          <p className="text-footnote text-muted">Test the connection to list what this server can do.</p>
        ) : (
          <Panel>
            {tools.map((tool) => (
              <Row key={tool.name} title={<span className="font-mono">{tool.name}</span>} caption={tool.description} />
            ))}
          </Panel>
        )}
      </Section>

      {/* Set apart at the end, away from the routine controls; an organization's server is removed in Memnox Cloud. */}
      {!fromOrganization(server) && (
        <div className="border-t border-panel-edge pt-4">
          <KitButton
            disabled={hub.busy === server.name}
            onClick={() =>
              void hub.removeServer(server.name).then((outcome) => {
                said(outcome);
                if (outcome.kind === 'done') removed();
              })
            }
          >
            Remove from every agent
          </KitButton>
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
    <Section title={`Found on this computer · ${view.found.length}`}>
      <Panel>
        {view.found.map((entry) => (
          <Row
            key={`${entry.path}/${entry.name}`}
            leading={entry.agent === undefined ? <Plug size={18} className="text-muted" /> : <BrandLogo agent={entry.agent} name={agentLabel(entry.agent)} size={22} />}
            title={entry.name}
            caption={`${entry.agent === undefined ? 'Shared by several agents' : agentLabel(entry.agent)} · ${entry.path}`}
            trailing={
              entry.agent === undefined ? (
                <span className="text-footnote text-muted">A repository’s own file</span>
              ) : (
                <KitButton disabled={hub.busy === entry.name} onClick={() => entry.agent !== undefined && void hub.importServer(entry.agent, entry.name).then(said)}>
                  Bring into the hub
                </KitButton>
              )
            }
          />
        ))}
      </Panel>
      <p className="text-footnote text-muted">Bringing a server in puts it behind Memnox, so every call it makes is ruled on and recorded.</p>
    </Section>
  );
}

/** Lines the hub wrote that a person changed since, left as they are and said. */
function Drift({ view }: { view: McpHubView }) {
  const entries = [...view.drifted, ...view.skipped];
  if (entries.length === 0) return null;
  return (
    <Section title="Left as they are">
      <Panel>
        {entries.map((entry) => (
          <Row
            key={`${entry.path}/${entry.name}/${entry.kind ?? entry.reason ?? ''}`}
            title={entry.name}
            caption={`${entry.agent === undefined ? '' : `${agentLabel(entry.agent)} · `}${entry.reason ?? (entry.kind === 'removed' ? 'You removed the line the hub wrote, so it is not put back.' : 'You changed the line the hub wrote, so the hub leaves it alone.')}`}
            trailing={<StatusWord tone="attention">Yours now</StatusWord>}
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
    return <EmptyState icon={Plug} title="Nothing to give yet" body="Once the hub holds a server and an agent with an MCP config is found, who has what is set here." />;
  }
  const inProjects = view.servers.some((server) => (server.projects ?? []).length > 0);
  return (
    <>
      <div className="overflow-x-auto rounded-xl border border-panel-edge">
        <table className="w-full border-collapse text-body">
          <thead>
            <tr className="bg-card">
              <th scope="col" className="px-3.5 py-2.5 text-left text-footnote font-semibold text-muted">Server</th>
              {view.agents.map(({ agent }) => (
                <th key={agent} scope="col" className="px-3 py-2.5 text-footnote font-semibold whitespace-nowrap text-muted">
                  <span className="inline-flex items-center gap-1.5">
                    <BrandLogo agent={agent} name={agentLabel(agent)} size={18} />
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
                    // Unticked, since ticking gives it everywhere; the project assignment is changed in Workspaces.
                    return (
                      <td key={agent} className="px-3 py-2.5 text-center">
                        <span className="inline-flex items-center gap-1.5">
                          <input
                            type="checkbox"
                            checked={false}
                            disabled={fromOrganization(server) || hub.busy === `${server.name}/${agent}`}
                            title={fromOrganization(server) ? ORGANIZATION_LINE : GIVE_EVERYWHERE}
                            aria-label={`${GIVE_EVERYWHERE}: ${server.name} for ${agentLabel(agent)}`}
                            className="size-4 cursor-pointer accent-[var(--color-primary)]"
                            onChange={() => void hub.assign(server.name, agent, true).then(said)}
                          />
                          <button type="button" title={help} aria-label={help} className="mx-focus inline-flex cursor-pointer items-center gap-1.5" onClick={workspaces}>
                            <ProjectChips server={server} agent={agent} />
                          </button>
                        </span>
                      </td>
                    );
                  }
                  return (
                    <td key={agent} className="px-3 py-2.5 text-center">
                      <span className="inline-flex items-center gap-1.5">
                        <input
                          type="checkbox"
                          checked={on}
                          disabled={fromOrganization(server) || hub.busy === `${server.name}/${agent}`}
                          title={fromOrganization(server) ? ORGANIZATION_LINE : undefined}
                          aria-label={`${server.name} for ${agentLabel(agent)}`}
                          className="size-4 cursor-pointer accent-[var(--color-primary)]"
                          onChange={() => void hub.assign(server.name, agent, !on).then(said)}
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
    <span title={help} aria-label={help} className="inline-flex max-w-40 items-center gap-1 rounded-md border border-panel-edge bg-hover px-1.5 py-0.5 text-micro text-muted">
      <Folder size={11} aria-hidden className="shrink-0" />
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
    return <EmptyState icon={KeyRound} title="No secrets yet" body="When a server needs a token, mark it as a secret while adding the server. Its value stays with this computer and no agent's config ever holds it." />;
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
      <input
        type="password"
        autoComplete="off"
        value={value}
        onChange={(event) => setValue(event.target.value)}
        onKeyDown={(event) => event.key === 'Enter' && value !== '' && save()}
        aria-label={`The value of ${name}`}
        className="h-8 w-48 rounded-lg border border-field-edge bg-field px-2.5 text-body text-foreground outline-none focus:border-primary"
      />
      <KitButton kind="primary" disabled={value === '' || hub.busy === name} onClick={save}>
        Keep
      </KitButton>
    </span>
  ) : (
    <span className="flex items-center gap-2">
      <StatusWord tone={held ? 'good' : 'bad'}>{held ? 'Kept' : 'Not set'}</StatusWord>
      <KitButton onClick={() => setEditing(true)}>{held ? 'Replace' : 'Set'}</KitButton>
      {held && (
        <KitButton disabled={hub.busy === name} onClick={() => void hub.removeSecret(name).then(said)}>
          Remove
        </KitButton>
      )}
    </span>
  );
  return <Row leading={<KeyRound size={16} className="text-muted" />} title={name} caption={`Used by ${usedBy.join(', ')}`} trailing={trailing} />;
}
