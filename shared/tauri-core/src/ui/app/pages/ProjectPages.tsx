import type { MemoryItemView, ProjectView } from '@memnox/core/wire';
import { Bot, CalendarDays, CheckCircle2, Circle, ExternalLink, FileText, FolderGit2, ListTodo, MessagesSquare, Plug, Plus, Server, ShieldCheck, Sparkles, Users, type LucideIcon } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { RuleDraftInput, StudioOutcome } from '../../../core/application/studio';
import { projectRoute, type ProjectPage, type Route, type Supports } from '../../../core/domain/destinations';
import {
  EVERYWHERE_SHOWN,
  MEMORY_EVERYWHERE_NOTE,
  MEMORY_EVERYWHERE_TITLE,
  MEMORY_HERE_EMPTY,
  MEMORY_HERE_TITLE,
  projectMemorySplit,
  REACH_HINT,
  REACH_WORD,
  serverReach,
  shared,
  skillReach,
  type ItemReach,
  type SharedRow,
} from '../../../core/domain/project-context';
import { statusWord } from '../../../core/domain/memory-lines';
import { counted, draftOf, projectRules, sharedBy } from '../../../core/domain/project-lines';
import { ALL_CATEGORIES, settledCategory } from '../../../core/domain/catalog';
import {
  CAN_USE_NOTE,
  CAN_USE_SHOWN,
  CAN_USE_TITLE,
  canUse,
  CLOUD_TOOLS_LINE,
  cloudProjectLink,
  editableHere,
  LEARNED_SHOWN,
  linkedToolCount,
  moreLine,
  OPEN_IN_CLOUD,
  projectAgents,
  projectDescription,
  projectPageInfo,
  projectToolCards,
  readyLine,
  readySteps,
  SHARE_TITLE,
  showReady,
  showsTeam,
  shownToolCards,
  TEAM_TITLE,
  TEAM_TOOLS_SHOWN,
  teamLine,
  toolCategoryCounts,
  type AgentOnProject,
  type CanUseKind,
  type CanUsePart,
  type CanUseTarget,
  type ProjectToolCard,
  type ReadyCounts,
  type ToolAction,
  type ToolCategory,
} from '../../../core/domain/project-sidebar';
import { CatalogCard, CatalogLayout, CatalogSearch, CategoryRail } from '../catalog';
import { groupCountLine, ruleGroups } from '../../../core/domain/rule-words';
import { ago } from '../../../core/domain/session-text';
import { ALWAYS_ASK, EFFECT_WORDS, effectTone, switchOn } from '../../../core/domain/studio-lines';
import { BrandLogo } from '../../kit/logos';
import { KitButton, PageTitle } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { GoLink } from './HomePage';
import { OrganizationBadge, projectNote } from './ProjectInspector';
import { CardGrid, EmptyState, Panel, ReadFailed, Row, Section, StatusWord } from '../widgets';

/**
 * One project's own pages, the main area beside the sidebar it swaps in: Overview, Agents, Memory, and What its AI may
 * do. Each is a page rather than a dialog. What this computer can save is saved through the daemon; what it cannot,
 * such as an organization's project, is shown read only with the way to Memnox Cloud. The desktop is one person's, so
 * people and the cloud's own actions show only once this computer is joined to a workspace or the organization shares the project.
 */
export function ProjectPages({ parts, project, page, go }: { parts: SettingsParts; project: ProjectView; page: ProjectPage; go: (route: Route) => void }) {
  const [note, setNote] = useState<string | undefined>(undefined);
  const info = projectPageInfo(page);
  return (
    <div className="flex w-full max-w-[880px] flex-col gap-6">
      {page !== 'overview' && page !== 'tools' && <PageTitle title={info.title} subtitle={info.summary} eyebrow={project.name} />}
      {note !== undefined && (
        <p role="status" className="rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote text-foreground">
          {note}
        </p>
      )}
      {/* Tools is left off for now, so a route to it shows the Overview, which holds its folder. */}
      {(page === 'overview' || page === 'tools') && <Overview parts={parts} project={project} go={go} />}
      {page === 'agents' && <Agents parts={parts} project={project} go={go} />}
      {page === 'memory' && <ProjectMemory parts={parts} project={project} go={go} />}
      {page === 'autonomy' && <Autonomy parts={parts} project={project} go={go} said={setNote} />}
    </div>
  );
}

/** Where a shared page is changed, or undefined while the daemon does not answer it, so no link leads nowhere. */
function sharedRoute(row: SharedRow, supports: Supports): Route | undefined {
  return shared({}, supports).find((link) => link.row === row)?.route;
}

/**
 * Whether an item belongs to this project alone or is shared with every project, as a small badge. A shared one is a
 * link to the page where it is changed, since this project only inherits it.
 */
function ReachBadge({ reach, open }: { reach: ItemReach; open?: (() => void) | undefined }) {
  const look = reach === 'only-here' ? 'border-primary/40 text-primary' : 'border-panel-edge text-muted';
  const className = `inline-flex shrink-0 items-center rounded-full border px-2 py-px text-label font-medium ${look}`;
  if (reach === 'every-project' && open !== undefined) {
    return (
      <button type="button" title={REACH_HINT[reach]} onClick={open} className={`mx-focus cursor-pointer hover:bg-hover hover:text-foreground ${className}`}>
        {REACH_WORD[reach]}
      </button>
    );
  }
  return (
    <span title={REACH_HINT[reach]} className={className}>
      {REACH_WORD[reach]}
    </span>
  );
}

/** The way to Memnox Cloud for whatever this computer only reads. */
function CloudLink({ parts, project, children = OPEN_IN_CLOUD }: { parts: SettingsParts; project: ProjectView; children?: string }) {
  return (
    <KitButton icon={ExternalLink} onClick={() => parts.host.openPage(cloudProjectLink(project))}>
      {children}
    </KitButton>
  );
}

/** Said above a page whose project this computer cannot change, with the way to where it is changed. */
function ReadOnly({ parts, project }: { parts: SettingsParts; project: ProjectView }) {
  const organization = sharedBy(project);
  if (organization === undefined) return null;
  return (
    <div className="flex flex-wrap items-center gap-3 rounded-xl border border-panel-edge bg-card px-4 py-3">
      <OrganizationBadge />
      <p className="min-w-0 flex-1 text-footnote text-muted">{organization.editedIn}</p>
      <CloudLink parts={parts} project={project} />
    </div>
  );
}

/** The counts the checklist reads, the rules of its own being those that reach into its folder or come from its file. */
function useReadyCounts(parts: SettingsParts, project: ProjectView): ReadyCounts {
  const { studio } = parts;
  useObserved(studio);
  useEffect(() => {
    if (studio.rules === undefined) void studio.refresh();
  }, []);
  const rules = studio.rules === undefined ? project.rules.count : projectRules(studio.rules.rules, project).here.length;
  return { tools: linkedToolCount(projectToolCards(project)), rules };
}

/** What its AI learned about the project, read once from everything memory holds. */
function useProjectMemory(parts: SettingsParts, project: ProjectView) {
  const { memory, support } = parts;
  useObserved(memory, support);
  const reads = support.supports('memory-facts') === true;
  useEffect(() => {
    if (reads) void memory.refreshEverything();
  }, [reads]);
  const split = memory.everything === undefined ? undefined : projectMemorySplit(memory.everything, project);
  return { reads, items: split?.here, everywhere: split?.everywhere };
}

/**
 * The Overview in Memnox Cloud's order: the name and what it is for, Get it ready while it is still empty, what its AI
 * can use, what it learned lately, its people once this computer is joined to a workspace, and at the foot its folder.
 */
function Overview({ parts, project, go }: { parts: SettingsParts; project: ProjectView; go: (route: Route) => void }) {
  const { account } = parts;
  useObserved(account);
  const joined = account.isSignedIn;
  const counts = useReadyCounts(parts, project);
  const learned = useProjectMemory(parts, project);
  const description = projectDescription(project);
  const ai = project.agents.length;
  return (
    <div className="flex flex-col gap-8">
      <header className="flex flex-col gap-2 pt-2">
        <div className="flex flex-wrap items-center gap-3">
          <h1 className="text-[28px] leading-tight font-semibold tracking-[-0.02em] text-foreground">{project.name}</h1>
          {sharedBy(project) !== undefined && <OrganizationBadge />}
        </div>
        <p className="max-w-2xl text-body leading-relaxed text-muted">{description ?? 'No description yet.'}</p>
        <p className="text-footnote text-faint">{[counted(ai, 'AI agent', 'AI agents'), counted(counts.rules, 'rule of its own', 'rules of its own')].join(' · ')}</p>
      </header>

      {showReady(counts) && (
        <section aria-label="Get it ready" className="flex flex-col gap-3 rounded-2xl border border-panel-edge bg-card p-5">
          <div className="flex items-baseline justify-between gap-3">
            <h2 className="text-base font-semibold text-foreground">Get it ready</h2>
            <span className="text-footnote text-muted">{readyLine(counts)}</span>
          </div>
          <ol className="flex flex-col gap-1">
            {readySteps(counts).map((step) => (
              <li key={step.id}>
                <button
                  type="button"
                  onClick={() => go(projectRoute(project.id, step.page))}
                  className="mx-focus flex w-full cursor-pointer items-center gap-3 rounded-lg px-2 py-2 text-left hover:bg-hover"
                >
                  {step.done ? <CheckCircle2 size={18} className="shrink-0 text-success" aria-hidden /> : <Circle size={18} className="shrink-0 text-faint" aria-hidden />}
                  <span className={`flex-1 text-body-sm ${step.done ? 'text-muted line-through decoration-faint' : 'font-medium text-foreground'}`}>{step.title}</span>
                  <span className="sr-only">{step.done ? 'Done' : 'Not done yet'}</span>
                </button>
              </li>
            ))}
          </ol>
        </section>
      )}

      <CanUse parts={parts} project={project} joined={joined} go={go} />

      <Section title="Learned lately" trailing={learned.items !== undefined && learned.items.length > LEARNED_SHOWN ? <GoLink onClick={() => go(projectRoute(project.id, 'memory'))}>Everything it learned</GoLink> : undefined}>
        {!learned.reads || learned.items === undefined || learned.items.length === 0 ? (
          <p className="text-body-sm text-muted">Nothing yet. What its AI reads about this project in its tools shows here once you confirm it.</p>
        ) : (
          <Panel>
            {learned.items.slice(0, LEARNED_SHOWN).map((item) => (
              <Row key={item.id} title={<span className="whitespace-pre-wrap">{item.statement}</span>} caption={ago(item.createdAt, Date.now()) ?? ''} trailing={<StatusWord tone={statusWord(item.status).tone}>{statusWord(item.status).word}</StatusWord>} />
            ))}
          </Panel>
        )}
      </Section>

      {showsTeam(project, joined) && <Team parts={parts} project={project} />}

      <Folder project={project} />
    </div>
  );
}

const CAN_USE_ICONS: Record<CanUseKind, LucideIcon> = { agents: Bot, skills: Sparkles, apps: Plug };

/**
 * What its AI can use, as Memnox Cloud's Overview draws it: a part each for its agents, skills and apps, every part
 * saying what its word means while it is empty, and a press on one opens the page that holds it.
 */
function CanUse({ parts, project, joined, go }: { parts: SettingsParts; project: ProjectView; joined: boolean; go: (route: Route) => void }) {
  const { agents, support } = parts;
  useObserved(agents, support);
  const supports: Supports = (method) => support.supports(method);
  const agentNames = Object.fromEntries((agents.agents ?? []).map((each) => [each.kind, each.name]));
  return (
    <section aria-label={CAN_USE_TITLE} className="flex flex-col gap-4 rounded-2xl border border-panel-edge bg-card p-5">
      <div className="flex flex-col gap-1">
        <h2 className="text-base font-semibold text-foreground">{CAN_USE_TITLE}</h2>
        <p className="text-footnote text-muted">{CAN_USE_NOTE}</p>
      </div>
      <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
        {canUse(project, joined, agentNames).map((part) => (
          <CanUsePartTile key={part.kind} part={part} open={canUseRoute(part.target, project.id, supports)} go={go} />
        ))}
      </div>
    </section>
  );
}

/** Where a part opens: a page of the project, or the shared page, which is undefined while the daemon answers none of it. */
function canUseRoute(target: CanUseTarget, id: string, supports: Supports): Route | undefined {
  return target.kind === 'page' ? projectRoute(id, target.page) : sharedRoute(target.row, supports);
}

function CanUsePartTile({ part, open, go }: { part: CanUsePart; open: Route | undefined; go: (route: Route) => void }) {
  const Icon = CAN_USE_ICONS[part.kind];
  const more = moreLine(part);
  return (
    <button type="button" disabled={open === undefined} onClick={() => open !== undefined && go(open)} className="mx-focus flex cursor-pointer flex-col gap-3 rounded-xl border border-panel-edge bg-background p-4 text-left hover:bg-hover">
      <span className="flex items-center gap-2 text-body-sm font-medium text-foreground">
        <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-hover">
          <Icon size={16} aria-hidden />
        </span>
        {part.title}
        {part.counted && <span className="tabular-nums text-muted">{part.names.length}</span>}
      </span>
      {part.names.length === 0 ? (
        <span className="flex flex-col gap-1">
          <span className="text-body-sm text-foreground">{part.empty}</span>
          <span className="text-footnote leading-relaxed text-muted">{part.what}</span>
        </span>
      ) : (
        <ul className="flex flex-col gap-1 text-body-sm text-foreground">
          {part.names.slice(0, CAN_USE_SHOWN).map((name) => (
            <li key={name} className="truncate">
              {name}
            </li>
          ))}
          {more !== undefined && <li className="text-footnote text-muted">{more}</li>}
        </ul>
      )}
    </button>
  );
}

/**
 * The project's people, shown only once this computer is joined to a workspace or the organization shares it: who shares it, or the
 * way to share it, both in Memnox Cloud where people are added.
 */
function Team({ parts, project }: { parts: SettingsParts; project: ProjectView }) {
  return (
    <Section title={TEAM_TITLE}>
      <div className="flex flex-wrap items-center gap-3 rounded-xl border border-panel-edge bg-card px-4 py-3">
        <Users size={16} className="shrink-0 text-muted" aria-hidden />
        <p className="min-w-0 flex-1 text-footnote text-muted">{teamLine(project)}</p>
        {sharedBy(project) === undefined ? <CloudLink parts={parts} project={project}>{SHARE_TITLE}</CloudLink> : <CloudLink parts={parts} project={project} />}
      </div>
    </Section>
  );
}

/** The project's folder at the Overview's foot, and the repository its organization shares it from, since Tools is left off for now. */
function Folder({ project }: { project: ProjectView }) {
  const repository = sharedBy(project)?.repository;
  return (
    <Section title="Folder">
      <Panel>
        {repository !== undefined && repository !== '' && <Row title={repository} caption="Repository shared by your organization" />}
        <Row title={<span className="truncate" title={project.path}>{project.path}</span>} caption="Folder on this computer" />
      </Panel>
    </Section>
  );
}

/** Each shelf wears the icon nearest what sits on it. */
const TOOL_ICONS: Record<ToolCategory, LucideIcon> = {
  files: FileText,
  channels: MessagesSquare,
  meetings: CalendarDays,
  tickets: ListTodo,
  repositories: FolderGit2,
  servers: Server,
  apps: Plug,
};

/**
 * The project's tools as the Connectors page lays its catalogue out: the shelves down the side, a search, and a card
 * per tool saying what is linked, its add action on the card itself. Adding a server writes the project's manifest
 * through the daemon; connecting an app happens on Connectors, once for every project. Left off for now, so nothing opens it.
 */
function Tools({ parts, project, go, said }: { parts: SettingsParts; project: ProjectView; go: (route: Route) => void; said: (note: string) => void }) {
  const { account, hub, projects, support, tools, words } = parts;
  useObserved(account, hub, projects, support, tools);
  const joined = showsTeam(project, account.isSignedIn);
  const hubAnswers = support.supports('mcp-hub') === true;
  useEffect(() => {
    if (hubAnswers && hub.hub === undefined) void hub.refresh();
  }, [hubAnswers]);
  useEffect(() => void tools.refresh(), []);
  const [category, setCategory] = useState<string>(ALL_CATEGORIES);
  const [query, setQuery] = useState('');
  const cards = projectToolCards(project, { hub: (hub.hub?.servers ?? []).map((server) => server.name), connections: tools.state.connections });
  const everywhere = new Set((hub.hub?.servers ?? []).filter((server) => server.agents.length > 0 || server.scope === 'organization').map((server) => server.name));
  const serversPage = sharedRoute('servers', (method) => support.supports(method));
  const appsPage = sharedRoute('connectors', (method) => support.supports(method));
  const categories = toolCategoryCounts(cards);
  const shelf = settledCategory(category, categories);
  const shown = shownToolCards(cards, shelf, query);
  const busy = projects.busy !== undefined;
  const act = (action: ToolAction) => {
    if (action.kind === 'connect') return go({ destination: 'mcp', tab: 'apps' });
    const draft = draftOf(project);
    void projects.put(project.path, { ...draft, servers: [...(draft.servers ?? []), action.server] }).then((outcome) => said(projectNote(outcome, words.keyTitle)));
  };
  return (
    <div className="flex flex-col gap-5">
      <ReadOnly parts={parts} project={project} />
      <CatalogLayout rail={<CategoryRail categories={categories} total={cards.length} chosen={shelf} choose={setCategory} allTitle="All tools" />}>
        <CatalogSearch value={query} placeholder="Search tools" showing={shown.length} total={cards.length} onChange={setQuery} />
        {shown.length === 0 ? (
          <EmptyState icon={Plug} title="No tools here" body={query.trim() === '' ? 'Add the places this project lives: its apps, documents and repositories.' : 'Nothing matches that search. Try fewer words.'} />
        ) : (
          <CardGrid>
            {shown.map((card) => (
              <ToolCard key={card.id} card={card} busy={busy} act={act} reach={reachOf(card, everywhere)} openShared={() => { const to = card.id.startsWith('app:') ? appsPage : serversPage; if (to !== undefined) go(to); }} />
            ))}
          </CardGrid>
        )}
      </CatalogLayout>
      {joined && !TEAM_TOOLS_SHOWN && (
        <div className="flex flex-wrap items-center gap-3">
          <p className="min-w-0 flex-1 text-footnote text-muted">{CLOUD_TOOLS_LINE}</p>
          <CloudLink parts={parts} project={project} />
        </div>
      )}
      {editableHere(project) && <p className="text-footnote text-muted">Adding a server writes it into the project’s .memnox/project.toml. Its AI is given it once you apply the project, signed on the island.</p>}
    </div>
  );
}

/**
 * Whether a linked tool belongs to this project alone: a server its manifest names is only here unless the hub gives
 * it to agents everywhere, an app connected as the person reaches every project, and its repository is its own.
 */
function reachOf(card: ProjectToolCard, everywhere: ReadonlySet<string>): ItemReach | undefined {
  if (!card.linked) return undefined;
  if (card.id.startsWith('server:')) return serverReach(everywhere.has(card.name));
  if (card.id.startsWith('app:')) return 'every-project';
  return 'only-here';
}

function ToolCard({ card, busy, act, reach, openShared }: { card: ProjectToolCard; busy: boolean; act: (action: ToolAction) => void; reach: ItemReach | undefined; openShared: () => void }) {
  const Icon = TOOL_ICONS[card.category];
  const action = card.action;
  return (
    <CatalogCard
      icon={<Icon size={15} aria-hidden />}
      title={card.name}
      line={card.line}
      badges={
        <>
          <span className="inline-flex items-center rounded-full border border-panel-edge px-2 py-px text-label font-medium text-muted">{card.what}</span>
          {card.linked && card.ready && <StatusWord tone="good">Linked</StatusWord>}
          {card.linked && !card.ready && <StatusWord tone="attention">Missing here</StatusWord>}
          {reach !== undefined && <ReachBadge reach={reach} open={openShared} />}
        </>
      }
      {...(action === undefined
        ? {}
        : {
            action: (
              <KitButton kind={action.kind === 'add-server' ? 'primary' : 'secondary'} icon={Plus} disabled={action.kind === 'add-server' && busy} onClick={() => act(action)}>
                {action.kind === 'add-server' ? 'Add' : 'Connect'}
              </KitButton>
            ),
          })}
    />
  );
}

/** The agents that work in this project: those it names with what each is given, then those seen here it does not name. */
function Agents({ parts, project, go }: { parts: SettingsParts; project: ProjectView; go: (route: Route) => void }) {
  const { agents, skills, support } = parts;
  useObserved(agents, skills, support);
  const readsSkills = support.supports('skills-hub') === true;
  useEffect(() => {
    void agents.refresh();
    if (readsSkills && skills.hub === undefined) void skills.refresh();
  }, [readsSkills]);
  const supports: Supports = (method) => support.supports(method);
  const agentNames = Object.fromEntries((agents.agents ?? []).map((each) => [each.kind, each.name]));
  const { given, seenOnly } = projectAgents(project, agentNames);
  const agentsPage = sharedRoute('agents', supports);
  const skillsPage = sharedRoute('skills', supports);
  const hubSkills = skills.hub?.skills ?? [];
  const named = new Set(project.skills.map((each) => each.name));
  // The skills its agents carry here: those the project names, then the person's own that every project shares.
  const ownSkills = project.skills.map((grant) => {
    const skill = hubSkills.find((each) => each.name === grant.name);
    return { name: grant.name, agents: grant.agents, reach: (skill === undefined ? undefined : skillReach(skill.scope, skill.project, project)) ?? ('only-here' as ItemReach) };
  });
  const inherited = hubSkills.filter((skill) => !named.has(skill.name) && skillReach(skill.scope, skill.project, project) !== undefined).map((skill) => ({ name: skill.name, agents: skill.agents, reach: skillReach(skill.scope, skill.project, project) ?? ('every-project' as ItemReach) }));
  const carried = [...ownSkills, ...inherited];
  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center gap-3 rounded-xl border border-panel-edge bg-card px-4 py-3">
        <ReachBadge reach="every-project" open={agentsPage === undefined ? undefined : () => go(agentsPage)} />
        <p className="min-w-0 flex-1 text-footnote text-muted">AI agents are set up once for every project on this computer. This page shows the ones that work here and what this project gives each.</p>
        {agentsPage !== undefined && <GoLink onClick={() => go(agentsPage)}>AI agents</GoLink>}
      </div>
      {given.length === 0 && seenOnly.length === 0 && <p className="text-footnote text-muted">No agent has worked here yet, and the project names none.</p>}
      {given.length > 0 && (
        <Section title="Given this project">
          <AgentRows agents={given} marked />
        </Section>
      )}
      {seenOnly.length > 0 && (
        <Section title="Seen here, not named">
          <AgentRows agents={seenOnly} marked={false} />
        </Section>
      )}
      <Section title="Skills its agents carry here" trailing={skillsPage === undefined ? undefined : <GoLink onClick={() => go(skillsPage)}>Skills</GoLink>}>
        {carried.length === 0 ? (
          <p className="text-footnote text-muted">No skill is given here yet, by this project or for every project.</p>
        ) : (
          <Panel>
            {carried.map((each) => (
              <Row
                key={each.name}
                title={each.name}
                caption={each.agents.length === 0 ? 'No agent carries it yet' : counted(each.agents.length, 'agent carries it', 'agents carry it')}
                trailing={<ReachBadge reach={each.reach} open={skillsPage === undefined ? undefined : () => go(skillsPage)} />}
              />
            ))}
          </Panel>
        )}
      </Section>
    </div>
  );
}

/**
 * What this project learned, only its own facts, then a short part for what every project knows because it belongs
 * to none, with the way to the shared Memory page where those are changed.
 */
function ProjectMemory({ parts, project, go }: { parts: SettingsParts; project: ProjectView; go: (route: Route) => void }) {
  const { support } = parts;
  const learned = useProjectMemory(parts, project);
  const memoryPage = sharedRoute('memory', (method) => support.supports(method));
  if (!learned.reads) return <p className="text-footnote text-muted">This computer’s runtime does not keep memory yet, so nothing learned shows here.</p>;
  if (learned.items === undefined || learned.everywhere === undefined) return null;
  const everywhere = learned.everywhere.slice(0, EVERYWHERE_SHOWN);
  return (
    <div className="flex flex-col gap-6">
      <Section title={MEMORY_HERE_TITLE}>
        {learned.items.length === 0 ? <p className="text-body-sm text-muted">{MEMORY_HERE_EMPTY}</p> : <Facts items={learned.items} reach="only-here" />}
      </Section>
      <Section title={MEMORY_EVERYWHERE_TITLE} trailing={memoryPage === undefined ? undefined : <GoLink onClick={() => go(memoryPage)}>Memory</GoLink>}>
        <p className="text-footnote text-muted">{MEMORY_EVERYWHERE_NOTE}</p>
        {everywhere.length === 0 ? <p className="text-body-sm text-muted">Nothing yet.</p> : <Facts items={everywhere} reach="every-project" open={memoryPage === undefined ? undefined : () => go(memoryPage)} />}
        {learned.everywhere.length > EVERYWHERE_SHOWN && memoryPage !== undefined && <GoLink onClick={() => go(memoryPage)}>{`All ${learned.everywhere.length} shared facts`}</GoLink>}
      </Section>
    </div>
  );
}

function Facts({ items, reach, open }: { items: readonly MemoryItemView[]; reach: ItemReach; open?: (() => void) | undefined }) {
  return (
    <Panel>
      {items.map((item) => (
        <Row
          key={item.id}
          title={<span className="whitespace-pre-wrap">{item.statement}</span>}
          caption={[statusWord(item.status).word, ago(item.createdAt, Date.now())].filter((each) => each !== undefined).join(' · ')}
          trailing={<ReachBadge reach={reach} open={open} />}
        />
      ))}
    </Panel>
  );
}

function AgentRows({ agents, marked }: { agents: readonly AgentOnProject[]; marked: boolean }) {
  return (
    <Panel>
      {agents.map((agent) => (
        <Row
          key={agent.kind}
          leading={<BrandLogo agent={agent.kind} name={agent.name} size={24} />}
          title={agent.name}
          caption={agent.line}
          {...(marked ? { trailing: agent.seen ? <StatusWord tone="good">Worked here</StatusWord> : <StatusWord tone="quiet">Not seen here</StatusWord> } : {})}
        />
      ))}
    </Panel>
  );
}

function studioNote(outcome: StudioOutcome, keyTitle: string): string {
  if (outcome.kind === 'proposed') return `Waiting for you on the island: confirm it with ${keyTitle} and it holds in this project.`;
  return outcome.kind === 'failed' ? outcome.why : outcome.note;
}

/** The rules that hold in this project in plain words, and ready made ones to ask about first, scoped to its folder. */
function Autonomy({ parts, project, go, said }: { parts: SettingsParts; project: ProjectView; go: (route: Route) => void; said: (note: string) => void }) {
  const { studio, words } = parts;
  useObserved(studio);
  useEffect(() => void studio.refresh(), []);
  const view = studio.rules;
  if (view === undefined) return studio.unreadable ? <ReadFailed what="the rules" retry={() => void studio.refresh()} /> : null;
  const { here, everywhere } = projectRules(view.rules, project);
  const groups = ruleGroups(here);
  const offered = editableHere(project) ? ALWAYS_ASK.filter((each) => !switchOn(here, each.draft.action, 'branches' in each.draft ? each.draft.branches : undefined)) : [];
  const propose = (draft: (typeof ALWAYS_ASK)[number]['draft']) =>
    void studio.propose({ ...draft, workingDirectories: [project.path] } as unknown as RuleDraftInput).then((outcome) => said(studioNote(outcome, words.keyTitle)));
  return (
    <div className="flex flex-col gap-6">
      <ReadOnly parts={parts} project={project} />
      {groups.length === 0 ? (
        <EmptyState icon={ShieldCheck} title="Nothing of its own yet" body="No rule names this project, so the rules of this computer decide what its AI does here." />
      ) : (
        <Panel>
          {groups.map((group) => (
            <Row
              key={`${group.effect}:${group.title}`}
              title={group.title}
              caption={[group.why, groupCountLine(group.rules.length)].filter((each) => each !== undefined).join(' · ')}
              trailing={
                <span className="flex items-center gap-2">
                  <ReachBadge reach="only-here" />
                  <StatusWord tone={effectTone(group.effect)}>{EFFECT_WORDS[group.effect].title}</StatusWord>
                </span>
              }
            />
          ))}
        </Panel>
      )}
      {offered.length > 0 && (
        <Section title="Ask first about">
          <Panel>
            {offered.map((each) => (
              <Row
                key={each.id}
                title={each.title}
                caption={`${each.line}, in this project only`}
                trailing={
                  <KitButton disabled={studio.busy !== undefined} onClick={() => propose(each.draft)}>
                    Ask first
                  </KitButton>
                }
              />
            ))}
          </Panel>
          <p className="text-footnote text-muted">{`A rule that holds here waits for your signature with ${words.keyTitle}.`}</p>
        </Section>
      )}
      <div className="flex flex-wrap items-center gap-3 rounded-xl border border-panel-edge bg-card px-4 py-3">
        <ReachBadge reach="every-project" open={() => go({ destination: 'governance', tab: 'policies' })} />
        <p className="min-w-0 flex-1 text-footnote text-muted">{everywhere === 1 ? '1 rule of this computer holds here too, as in every project.' : `${everywhere} rules of this computer hold here too, as in every project.`}</p>
        <GoLink onClick={() => go({ destination: 'governance', tab: 'policies' })}>Protection settings</GoLink>
      </div>
    </div>
  );
}
