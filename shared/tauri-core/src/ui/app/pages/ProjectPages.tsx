import type { MemoryItemView, ProjectGrantView, ProjectView } from '@memnox/core/wire';
import {
  ArrowUpRight,
  Building2,
  CalendarDays,
  Check,
  ChevronRight,
  Circle,
  CircleCheck,
  Cpu,
  ExternalLink,
  FileText,
  Folder as FolderIcon,
  FolderGit2,
  Hand,
  ListTodo,
  MessagesSquare,
  Play,
  Plug,
  Plus,
  Puzzle,
  Save,
  Server,
  Sparkles,
  SquareStack,
  TriangleAlert,
  type LucideIcon,
} from 'lucide-react';
import { useEffect, useState, type ReactNode } from 'react';
import type { ProjectOutcome } from '../../../core/application/projects';
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
import { rowCaption } from '../../../core/domain/memory-lines';
import { agentLabel } from '../../../core/domain/mcp-hub-lines';
import { draftOf, everywhereLine, FROM_ORGANIZATION, grantLine, pressLine, ProjectPageLines, projectNote, projectRules, projectStanding, rulesLine, sessionsLine, sharedBy } from '../../../core/domain/project-lines';
import { ALL_CATEGORIES, settledCategory } from '../../../core/domain/catalog';
import {
  AGENTS_SHARED_LINE,
  BACK_TO_PROJECTS,
  GONE_LINE,
  GONE_TITLE,
  ALL_MEMORY_LINK,
  CAN_USE_NOTE,
  CAN_USE_SHOWN,
  CAN_USE_TITLE,
  canUse,
  CLOUD_TOOLS_LINE,
  cloudProjectLink,
  editableHere,
  FOLDER_TITLE,
  GIVEN_TITLE,
  ITS_AGENTS_TITLE,
  LEARNED_EMPTY,
  LEARNED_MORE,
  LEARNED_SHOWN,
  LEARNED_TITLE,
  moreLine,
  moreSkillsLine,
  NO_AGENTS,
  NO_DESCRIPTION,
  NO_SKILLS_GIVEN,
  OPEN_IN_CLOUD,
  projectAgents,
  projectDescription,
  projectPageInfo,
  projectToolCards,
  READY_TITLE,
  readyRules,
  readySteps,
  RULES_HERE_EMPTY,
  RULES_HERE_TITLE,
  RULES_LINK,
  SEEN_TITLE,
  SHARE_TITLE,
  SHARED_LINE,
  SHARED_SKILLS_SHOWN,
  showReady,
  showsTeam,
  shownToolCards,
  SKILLS_CARRIED_TITLE,
  TEAM_TITLE,
  PROJECT_TOOLS_SHOWN,
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
import { CatalogCard, CatalogLayout, CategoryRail } from '../catalog';
import { plainCaption, plainCountLine, plainGroups } from '../../../core/domain/plain-rules';
import { EFFECT_WORDS, effectTone, isEffect } from '../../../core/domain/studio-lines';
import { BrandLogo } from '../../kit/logos';
import { PageTitle } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { GoLink } from './HomePage';
import { Button, CardGrid, EmptyState, Note, Panel, PRESS_DIP, Pressable, ReadFailed, Row, SearchInput, Section, Spinner, StatusWord } from '../../kit';

/**
 * One project's own pages, the main area beside the sidebar it swaps in: Overview, Agents, Memory, and What its AI may
 * do, drawn as the Mac's ProjectPages draws them. Each is a page rather than a dialog. What this computer can save is
 * saved through the daemon; what it cannot, such as an organization's project, is shown read only with the way to
 * Memnox Cloud. People and the cloud's own actions show only once this computer is joined to a workspace or the
 * organization shares the project.
 */
export function ProjectPages({ parts, project, page, go }: { parts: SettingsParts; project: ProjectView; page: ProjectPage; go: (route: Route) => void }) {
  const info = projectPageInfo(page);
  const body = (
    <div className="flex flex-col gap-6">
      {page === 'tools' && PROJECT_TOOLS_SHOWN && <Tools parts={parts} project={project} go={go} />}
      {(page === 'overview' || (page === 'tools' && !PROJECT_TOOLS_SHOWN)) && <Overview parts={parts} project={project} go={go} />}
      {page === 'agents' && <Agents parts={parts} project={project} go={go} />}
      {page === 'memory' && <ProjectMemory parts={parts} project={project} go={go} />}
      {page === 'autonomy' && <Autonomy parts={parts} project={project} go={go} />}
    </div>
  );
  // The Overview heads itself with the project's name; every other page says its own title and line, as on the Mac.
  if (page === 'overview' || page === 'tools') return <div className="flex w-full flex-col">{body}</div>;
  return (
    <div className="flex w-full flex-col gap-5">
      <PageTitle title={info.title} subtitle={info.summary} />
      {body}
    </div>
  );
}

/** Said where a project was open and is no longer among the projects, with the way back to them. */
export function ProjectGone({ back }: { back: () => void }) {
  return (
    <>
      <EmptyState icon={FolderIcon} title={GONE_TITLE} body={GONE_LINE} />
      <GoLink onClick={back}>{BACK_TO_PROJECTS}</GoLink>
    </>
  );
}

/** Where a shared page is changed, or undefined while the daemon does not answer it, so no link leads nowhere. */
function sharedRoute(row: SharedRow, supports: Supports): Route | undefined {
  return shared({}, supports).find((link) => link.row === row)?.route;
}

/** A quiet line of a project's pages, the Mac's ProjectMuted. */
function Muted({ children }: { children: ReactNode }) {
  return <p className="text-footnote text-muted">{children}</p>;
}

/** What the last press came to, the Mac's NoteBanner. */
function NoteBanner({ text }: { text: string | undefined }) {
  if (text === undefined) return null;
  return (
    <Note roomy className="w-full">
      {text}
    </Note>
  );
}

/** The glyph before the organization's word, footnote sized as the word is. */
const ORGANIZATION_GLYPH = 12;

/** The badge a project the organization shares carries in place of its standing, as the Mac's `OrganizationBadge`. */
export function OrganizationBadge() {
  return (
    <span className="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-panel-edge px-2 py-1 text-footnote font-medium whitespace-nowrap text-muted">
      <Building2 size={ORGANIZATION_GLYPH} aria-hidden />
      {FROM_ORGANIZATION}
    </span>
  );
}

/** The agents' logos overlapping, as the cards and the grants show who has a thing. */
export function AgentLogos({ agents, names = {} }: { agents: readonly string[]; names?: Readonly<Record<string, string>> }) {
  return (
    <span className="flex -space-x-1.5">
      {agents.map((kind) => (
        <BrandLogo key={kind} agent={kind} name={names[kind] ?? agentLabel(kind)} size={STACKED_LOGO} className="ring-2 ring-card" />
      ))}
    </span>
  );
}

/**
 * Whether an item belongs to this project alone or is shared with every project, as the Mac's small badge: a folder
 * or a stack before the word on a wash, and a shared one is a link to the page where it is changed.
 */
function ReachBadge({ reach, open }: { reach: ItemReach; open?: (() => void) | undefined }) {
  const Icon = reach === 'only-here' ? FolderIcon : SquareStack;
  const look = reach === 'only-here' ? 'bg-primary/10 text-primary' : 'bg-hover text-muted';
  const className = `inline-flex shrink-0 items-center gap-0.5 rounded-full px-2.5 py-0.5 text-label font-medium whitespace-nowrap ${look}`;
  if (reach === 'every-project' && open !== undefined) {
    return (
      <Pressable title={ProjectPageLines.opensPage(REACH_HINT[reach])} aria-label={REACH_WORD[reach]} onClick={open} className={`mx-focus cursor-pointer ${PRESS_DIP} ${className}`}>
        <Icon size={REACH_GLYPH} strokeWidth={REACH_STROKE} aria-hidden />
        {REACH_WORD[reach]}
        <ArrowUpRight size={REACH_GLYPH} strokeWidth={REACH_STROKE} aria-hidden />
      </Pressable>
    );
  }
  return (
    <span title={REACH_HINT[reach]} aria-label={REACH_WORD[reach]} className={className}>
      <Icon size={REACH_GLYPH} strokeWidth={REACH_STROKE} aria-hidden />
      {REACH_WORD[reach]}
    </span>
  );
}

/** The way to Memnox Cloud for whatever this computer only reads. */
function CloudLink({ parts, project, children = OPEN_IN_CLOUD, wide = false }: { parts: SettingsParts; project: ProjectView; children?: string; wide?: boolean }) {
  return (
    <Button icon={ExternalLink} wide={wide} className="self-start" title={cloudProjectLink(project)} onClick={() => parts.host.openPage(cloudProjectLink(project))}>
      {children}
    </Button>
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

/** The counts the checklist reads, the rules of its own being those that reach into its folder plus its file's in force. */
function useReadyCounts(parts: SettingsParts, project: ProjectView): ReadyCounts {
  const { studio } = parts;
  useObserved(studio);
  useEffect(() => {
    if (studio.rules === undefined) void studio.refresh();
  }, []);
  const here = studio.rules === undefined ? 0 : projectRules(studio.rules.rules, project).here.length;
  return { tools: 0, rules: readyRules(here, project) };
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
  const team = showsTeam(project, account.isJoined);
  const counts = useReadyCounts(parts, project);
  const steps = readySteps(counts);
  return (
    <>
      <OverviewHeader project={project} />
      {showReady(counts) && (
        <Section title={READY_TITLE}>
          <Panel>
            {steps.map((step) => (
              <Row
                key={step.id}
                onClick={() => go(projectRoute(project.id, step.page))}
                leading={
                  step.done ? (
                    <CircleCheck size={READY_GLYPH} fill="currentColor" className="text-success [&>path]:stroke-card" aria-label={ProjectPageLines.done} />
                  ) : (
                    <Circle size={READY_GLYPH} className="text-faint" aria-label={ProjectPageLines.toDo} />
                  )
                }
                title={step.title}
                caption={step.detail}
                trailing={<ChevronRight size={CHEVRON_GLYPH} strokeWidth={REACH_STROKE} className="text-faint" aria-hidden />}
              />
            ))}
          </Panel>
        </Section>
      )}
      <CanUse parts={parts} project={project} team={team} go={go} />
      <LearnedLately parts={parts} project={project} go={go} />
      {team && <Team parts={parts} project={project} />}
      <Folder parts={parts} project={project} />
    </>
  );
}

/** The project's name with its standing on the right, what it is for, and any problem its manifest has. */
function OverviewHeader({ project }: { project: ProjectView }) {
  const standing = projectStanding(project);
  const description = projectDescription(project);
  return (
    <header className="flex flex-col gap-2">
      <div className="flex items-baseline gap-2">
        <h1 className="line-clamp-2 min-w-0 flex-1 text-2xl font-semibold tracking-[-0.02em] text-foreground">{project.name}</h1>
        <span className="shrink-0">{sharedBy(project) === undefined ? <StatusWord tone={standing.tone}>{standing.word}</StatusWord> : <OrganizationBadge />}</span>
      </div>
      <p className={`max-w-app-description text-base leading-app-description ${description === undefined ? 'text-muted' : 'text-foreground'}`}>{description ?? NO_DESCRIPTION}</p>
      {(project.problems ?? []).map((problem) => (
        <p key={problem} role="alert" className="text-footnote text-destructive">
          {problem}
        </p>
      ))}
    </header>
  );
}

/** The few facts learned here most recently, with the way to all of them. */
function LearnedLately({ parts, project, go }: { parts: SettingsParts; project: ProjectView; go: (route: Route) => void }) {
  const learned = useProjectMemory(parts, project);
  const items = learned.items ?? [];
  return (
    <Section title={LEARNED_TITLE}>
      {items.length === 0 ? (
        <Muted>{LEARNED_EMPTY}</Muted>
      ) : (
        <>
          <Panel>
            {items.slice(0, LEARNED_SHOWN).map((item) => (
              <Row key={item.id} title={item.statement} caption={rowCaption(item)} />
            ))}
          </Panel>
          {items.length > LEARNED_SHOWN && <GoLink onClick={() => go(projectRoute(project.id, 'memory'))}>{LEARNED_MORE}</GoLink>}
        </>
      )}
    </Section>
  );
}

const CAN_USE_ICONS: Record<CanUseKind, LucideIcon> = { agents: Cpu, skills: Sparkles, apps: Puzzle };

/** The Mac's ProjectCanUse lays its parts out no narrower than this. */
const CAN_USE_MIN = 180;

/** Logos overlapping on a card, and an agent's beside its row. */
const STACKED_LOGO = 20;
const AGENT_LOGO = 24;

/** The reach badge's glyphs, as small as its 11 point word, drawn heavy so they read. */
const REACH_GLYPH = 10;
const REACH_STROKE = 2.5;

/** A ready step's mark, its row's chevron, a tile's glyph, a tool's glyph and the result line's mark. */
const READY_GLYPH = 16;
const CHEVRON_GLYPH = 12;
const TILE_GLYPH = 14;
const TOOL_GLYPH = 15;
const RESULT_GLYPH = 12;

/**
 * What its AI can use, as Memnox Cloud's Overview draws it: a part each for its agents, skills and apps, every part
 * saying what its word means while it is empty, and a press on one opens the page that holds it.
 */
function CanUse({ parts, project, team, go }: { parts: SettingsParts; project: ProjectView; team: boolean; go: (route: Route) => void }) {
  const { agents, support } = parts;
  useObserved(agents, support);
  const supports: Supports = (method) => support.supports(method);
  const agentNames = Object.fromEntries((agents.agents ?? []).map((each) => [each.kind, each.name]));
  return (
    <Section title={CAN_USE_TITLE}>
      <Muted>{CAN_USE_NOTE}</Muted>
      <CardGrid min={CAN_USE_MIN}>
        {canUse(project, team, agentNames).map((part) => (
          <CanUsePartTile key={part.kind} part={part} open={canUseRoute(part.target, project.id, supports)} go={go} />
        ))}
      </CardGrid>
    </Section>
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
    <Pressable
      onClick={() => open !== undefined && go(open)}
      className={`mx-focus flex h-full cursor-pointer flex-col items-stretch gap-2 rounded-card border border-panel-edge bg-card p-4 text-left ${PRESS_DIP}`}
    >
      <span className="flex items-center gap-2">
        <span className="flex size-control shrink-0 items-center justify-center rounded-control bg-hover text-foreground">
          <Icon size={TILE_GLYPH} aria-hidden />
        </span>
        <span className="text-body-sm font-medium text-foreground">{part.title}</span>
        {part.counted && <span className="text-body-sm tabular-nums text-muted">{part.names.length}</span>}
      </span>
      {part.names.length === 0 ? (
        <>
          <span className="text-body-sm text-foreground">{part.empty}</span>
          <span className="text-footnote text-muted">{part.what}</span>
        </>
      ) : (
        <span className="flex min-w-0 flex-col gap-0.5">
          {part.names.slice(0, CAN_USE_SHOWN).map((name) => (
            <span key={name} className="truncate text-body-sm text-foreground">
              {name}
            </span>
          ))}
          {more !== undefined && <span className="text-footnote text-muted">{more}</span>}
        </span>
      )}
    </Pressable>
  );
}

/**
 * The project's people, shown only once this computer is joined to a workspace or the organization shares it: who shares it, or the
 * way to share it, both in Memnox Cloud where people are added.
 */
function Team({ parts, project }: { parts: SettingsParts; project: ProjectView }) {
  return (
    <Section title={TEAM_TITLE}>
      <Muted>{teamLine(project)}</Muted>
      {sharedBy(project) === undefined ? (
        <CloudLink parts={parts} project={project} wide>
          {SHARE_TITLE}
        </CloudLink>
      ) : (
        <CloudLink parts={parts} project={project} />
      )}
    </Section>
  );
}

/** What the last Apply came to, kept beside its button rather than as the page's note. */
interface Applied {
  readonly outcome: ProjectOutcome;
  readonly at: number;
}

/**
 * The project's folder at the Overview's foot, and Apply or Save as project on the person's own, or the line saying the
 * organization changes it in Memnox Cloud, as the Mac's ProjectOnThisMac draws it.
 */
function Folder({ parts, project }: { parts: SettingsParts; project: ProjectView }) {
  const { projects, words } = parts;
  useObserved(projects);
  const [note, setNote] = useState<string | undefined>(undefined);
  const [applied, setApplied] = useState<Applied | undefined>(undefined);
  const busy = projects.busy === project.id || projects.busy === project.path;
  const organization = sharedBy(project);
  // As on the Mac, the last Apply that found nothing to change keeps the button saying so until it is pressed again.
  const current = applied?.outcome.kind === 'up-to-date';
  const apply = () => {
    setApplied(undefined);
    void projects.apply(project.id).then((outcome) => setApplied({ outcome, at: Date.now() }));
  };
  const save = () => void projects.put(project.path, draftOf(project)).then((outcome) => setNote(projectNote(outcome, words.keyTitle)));
  return (
    <Section title={FOLDER_TITLE}>
      <div className="flex flex-col items-start gap-2">
        <p className="w-full truncate text-footnote text-muted select-text" title={project.path}>
          {project.path}
        </p>
        {organization !== undefined ? (
          <>
            <Muted>{organization.editedIn}</Muted>
            <CloudLink parts={parts} project={project} />
          </>
        ) : (
          <>
            {project.declared ? (
              <Button kind="primary" icon={current ? Check : Play} busy={busy} onClick={apply} title={current ? ProjectPageLines.upToDateHint : ProjectPageLines.applyHint}>
                {busy ? ProjectPageLines.applying : current ? ProjectPageLines.upToDate : ProjectPageLines.apply}
              </Button>
            ) : (
              <Button kind="primary" icon={Save} disabled={busy} onClick={save}>
                {busy ? ProjectPageLines.saving : ProjectPageLines.saveAsProject}
              </Button>
            )}
            {project.declared && applied !== undefined ? <ApplyResultLine applied={applied} keyTitle={words.keyTitle} /> : <Muted>{pressLine(project.declared)}</Muted>}
          </>
        )}
        <NoteBanner text={note} />
        <Muted>{sessionsLine(project, Date.now())}</Muted>
      </div>
    </Section>
  );
}

/** Each way an Apply ends wears the Mac's `ApplyResultLine` mark: its glyph and its colour. */
const APPLY_LOOK: Record<ProjectOutcome['kind'], { icon: LucideIcon; tint: string }> = {
  done: { icon: CircleCheck, tint: 'text-success' },
  proposed: { icon: Hand, tint: 'text-warm' },
  'up-to-date': { icon: Check, tint: 'text-muted' },
  failed: { icon: TriangleAlert, tint: 'text-destructive' },
};

/** What the last Apply came to: a tick for a change, amber for what waits on the island, grey when nothing changed, red for a refusal, with its time. */
function ApplyResultLine({ applied, keyTitle }: { applied: Applied; keyTitle: string }) {
  const { outcome, at } = applied;
  const { icon: Icon, tint } = APPLY_LOOK[outcome.kind];
  const time = new Date(at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  return (
    <p role="status" className={`flex items-start gap-1.5 text-footnote select-text ${tint}`}>
      <Icon size={RESULT_GLYPH} className="mt-0.5 shrink-0" aria-hidden />
      <span>{ProjectPageLines.at(projectNote(outcome, keyTitle), time)}</span>
    </p>
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
function Tools({ parts, project, go }: { parts: SettingsParts; project: ProjectView; go: (route: Route) => void }) {
  const [said, setSaid] = useState<string | undefined>(undefined);
  const { account, hub, projects, support, tools, words } = parts;
  useObserved(account, hub, projects, support, tools);
  const joined = account.isJoined;
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
    void projects.put(project.path, { ...draft, servers: [...(draft.servers ?? []), action.server] }).then((outcome) => setSaid(projectNote(outcome, words.keyTitle)));
  };
  return (
    <div className="flex flex-col gap-5">
      {said !== undefined && <Note>{said}</Note>}
      <ReadOnly parts={parts} project={project} />
      <CatalogLayout rail={<CategoryRail categories={categories} total={cards.length} chosen={shelf} choose={setCategory}  allTitle={ProjectPageLines.allTools} />}>
        <SearchInput value={query} placeholder={ProjectPageLines.searchTools} count={{ shown: shown.length, total: cards.length }} onChange={setQuery} />
        {shown.length === 0 ? (
          <EmptyState icon={Plug} title={ProjectPageLines.noTools} body={query.trim() === '' ? ProjectPageLines.noToolsBody : ProjectPageLines.noToolsMatch} />
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
      {editableHere(project) && <p className="text-footnote text-muted">{ProjectPageLines.serverNote}</p>}
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
      icon={<Icon size={TOOL_GLYPH} aria-hidden />}
      title={card.name}
      line={card.line}
      badges={
        <>
          <span className="inline-flex items-center rounded-full border border-panel-edge px-2 py-px text-label font-medium text-muted">{card.what}</span>
          {card.linked && card.ready && <StatusWord tone="good">{ProjectPageLines.linked}</StatusWord>}
          {card.linked && !card.ready && <StatusWord tone="attention">{ProjectPageLines.missingHere}</StatusWord>}
          {reach !== undefined && <ReachBadge reach={reach} open={openShared} />}
        </>
      }
      {...(action === undefined
        ? {}
        : {
            action: (
              <Button kind={action.kind === 'add-server' ? 'primary' : 'secondary'} icon={Plus} disabled={action.kind === 'add-server' && busy} onClick={() => act(action)}>
                {action.kind === 'add-server' ? ProjectPageLines.add : ProjectPageLines.connect}
              </Button>
            ),
          })}
    />
  );
}


/** The agents that work in this project, each with what the project gives it, and the way to where every agent on this computer is set up. */
function Agents({ parts, project, go }: { parts: SettingsParts; project: ProjectView; go: (route: Route) => void }) {
  const { support } = parts;
  useObserved(support);
  const agentsPage = sharedRoute('agents', (method) => support.supports(method));
  return (
    <>
      <AgentsHere parts={parts} project={project} />
      {agentsPage !== undefined && (
        <div className="flex items-center gap-2">
          <ReachBadge reach="every-project" open={() => go(agentsPage)} />
          <p className="min-w-0 flex-1 text-footnote text-muted">{AGENTS_SHARED_LINE}</p>
        </div>
      )}
    </>
  );
}

/** The agents the project names, then any seen working in it that it does not name. */
function AgentsHere({ parts, project }: { parts: SettingsParts; project: ProjectView }) {
  const { agents } = parts;
  useObserved(agents);
  useEffect(() => void agents.refresh(), []);
  const agentNames = Object.fromEntries((agents.agents ?? []).map((each) => [each.kind, each.name]));
  const { given, seenOnly } = projectAgents(project, agentNames);
  if (given.length === 0 && seenOnly.length === 0) return <Muted>{NO_AGENTS}</Muted>;
  return (
    <div className="flex flex-col gap-5">
      {given.length > 0 && (
        <Section title={GIVEN_TITLE}>
          <AgentRows agents={given} marked />
        </Section>
      )}
      {seenOnly.length > 0 && (
        <Section title={SEEN_TITLE}>
          <AgentRows agents={seenOnly} marked={false} />
        </Section>
      )}
    </div>
  );
}

/**
 * What this project learned, only its own facts, then a short part for what every project knows because it belongs
 * to none, with the way to the shared Memory page where those are changed.
 */
function ProjectMemory({ parts, project, go }: { parts: SettingsParts; project: ProjectView; go: (route: Route) => void }) {
  const { memory, support } = parts;
  const learned = useProjectMemory(parts, project);
  const memoryPage = sharedRoute('memory', (method) => support.supports(method));
  if (!learned.reads) return <Muted>{MEMORY_HERE_EMPTY}</Muted>;
  const openMemory = memoryPage === undefined ? undefined : () => go(memoryPage);
  return (
    <>
      <Section title={MEMORY_HERE_TITLE}>
        {learned.items === undefined ? (
          memory.unreadable.facts ? (
            <ReadFailed what={ProjectPageLines.whatWasLearned} retry={() => void memory.refreshEverything()} />
          ) : (
            <Spinner />
          )
        ) : learned.items.length === 0 ? (
          <Muted>{MEMORY_HERE_EMPTY}</Muted>
        ) : (
          <Facts items={learned.items} reach="only-here" />
        )}
      </Section>
      <Section title={MEMORY_EVERYWHERE_TITLE}>
        <Muted>{MEMORY_EVERYWHERE_NOTE}</Muted>
        {(learned.everywhere ?? []).length > 0 && <Facts items={(learned.everywhere ?? []).slice(0, EVERYWHERE_SHOWN)} reach="every-project" open={openMemory} />}
        {openMemory !== undefined && <GoLink onClick={openMemory}>{ALL_MEMORY_LINK}</GoLink>}
      </Section>
    </>
  );
}

function Facts({ items, reach, open }: { items: readonly MemoryItemView[]; reach: ItemReach; open?: (() => void) | undefined }) {
  return (
    <Panel>
      {items.map((item) => (
        <Row key={item.id} title={item.statement} caption={rowCaption(item)} trailing={<ReachBadge reach={reach} open={open} />} />
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
          leading={<BrandLogo agent={agent.kind} name={agent.name} size={AGENT_LOGO} />}
          title={agent.name}
          caption={agent.line}
          {...(marked ? { trailing: agent.seen ? <StatusWord tone="good">{ProjectPageLines.workedHere}</StatusWord> : <StatusWord tone="quiet">{ProjectPageLines.notSeenHere}</StatusWord> } : {})}
        />
      ))}
    </Panel>
  );
}

/** What its AI may do: the rules that hold here in plain words, then the agents given it and the skills they carry. */
function Autonomy({ parts, project, go }: { parts: SettingsParts; project: ProjectView; go: (route: Route) => void }) {
  return (
    <>
      <RulesHere parts={parts} project={project} open={() => go({ destination: 'governance', tab: 'policies' })} />
      <Section title={ITS_AGENTS_TITLE}>
        <AgentsHere parts={parts} project={project} />
      </Section>
      <Section title={SKILLS_CARRIED_TITLE}>
        <Grants project={project} grants={project.skills} empty={NO_SKILLS_GIVEN} />
        <SharedSkills parts={parts} project={project} go={go} />
      </Section>
      {sharedBy(project) !== undefined && (
        <>
          <Muted>{SHARED_LINE}</Muted>
          <CloudLink parts={parts} project={project} />
        </>
      )}
    </>
  );
}

/** The rules reaching into this project, each family said once with a count, and how many hold everywhere. */
function RulesHere({ parts, project, open }: { parts: SettingsParts; project: ProjectView; open: () => void }) {
  const { studio } = parts;
  useObserved(studio);
  useEffect(() => void studio.refresh(), []);
  const view = studio.rules;
  if (view === undefined) {
    return <Section title={RULES_HERE_TITLE}>{studio.unreadable ? <ReadFailed what={ProjectPageLines.theRules} retry={() => void studio.refresh()} /> : <Spinner />}</Section>;
  }
  const { here, everywhere } = projectRules(view.rules, project);
  // Grouped as the Mac's PlainRules, so rules for different agents stay separate rows.
  const groups = plainGroups(here).flatMap((group) => (isEffect(group.effect) ? [{ ...group, effect: group.effect }] : []));
  return (
    <Section title={RULES_HERE_TITLE}>
      {groups.length === 0 ? (
        <Muted>{RULES_HERE_EMPTY}</Muted>
      ) : (
        <Panel>
          {groups.map((group) => {
            const count = plainCountLine(group.rules.length);
            return (
              <Row
                key={group.rules[0]?.name ?? group.plain.title}
                title={group.plain.title}
                caption={plainCaption(group.plain) ?? rulesLine(project.rules)}
                trailing={
                  <>
                    {count !== undefined && <span className="text-footnote text-muted">{count}</span>}
                    <ReachBadge reach="only-here" />
                    <StatusWord tone={effectTone(group.effect)}>{EFFECT_WORDS[group.effect].title}</StatusWord>
                  </>
                }
              />
            );
          })}
        </Panel>
      )}
      <div className="flex items-center gap-2">
        <ReachBadge reach="every-project" open={open} />
        <p className="min-w-0 flex-1 text-footnote text-muted">{everywhereLine(everywhere)}</p>
      </div>
      <GoLink onClick={open}>{RULES_LINK}</GoLink>
    </Section>
  );
}

/** A skill the project names, with who has it now and that it is only here. */
function Grants({ project, grants, empty }: { project: ProjectView; grants: readonly ProjectGrantView[]; empty: string }) {
  if (grants.length === 0) return <Muted>{empty}</Muted>;
  return (
    <Panel>
      {grants.map((grant) => (
        <Row
          key={grant.name}
          title={grant.name}
          caption={grantLine(grant, project.agents.length)}
          trailing={
            <>
              <ReachBadge reach="only-here" />
              {grant.inHub ? <AgentLogos agents={grant.agents} /> : <StatusWord tone="attention">{ProjectPageLines.notInHub}</StatusWord>}
            </>
          }
        />
      ))}
    </Panel>
  );
}

/** The skills every project's agents carry, the person's own and the organization's, each linking to Skills. */
function SharedSkills({ parts, project, go }: { parts: SettingsParts; project: ProjectView; go: (route: Route) => void }) {
  const { skills, support } = parts;
  useObserved(skills, support);
  const reads = support.supports('skills-hub') === true;
  useEffect(() => {
    if (reads && skills.hub === undefined) void skills.refresh();
  }, [reads]);
  const skillsPage = sharedRoute('skills', (method) => support.supports(method));
  const open = skillsPage === undefined ? undefined : () => go(skillsPage);
  const everywhere = (skills.hub?.skills ?? []).filter((skill) => skillReach(skill.scope, skill.project, project) === 'every-project');
  if (everywhere.length === 0) return null;
  return (
    <>
      <Panel>
        {everywhere.slice(0, SHARED_SKILLS_SHOWN).map((skill) => (
          <Row key={skill.name} title={skill.name} caption={skill.description} trailing={<ReachBadge reach="every-project" open={open} />} />
        ))}
      </Panel>
      {everywhere.length > SHARED_SKILLS_SHOWN && open !== undefined && <GoLink onClick={open}>{moreSkillsLine(everywhere.length - SHARED_SKILLS_SHOWN)}</GoLink>}
    </>
  );
}
