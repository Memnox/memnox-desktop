import type { AgentAction, AgentView } from '@memnox/core/wire';
import { Bot, Folder, Pause, Play, ShieldAlert, ShieldCheck, SquareTerminal, TriangleAlert } from 'lucide-react';
import { useEffect, useState, type ReactNode } from 'react';
import type { StudioOutcome } from '../../../core/application/studio';
import {
  AGENT_FILTER_TITLES,
  afterProtect,
  actionTarget,
  agentFigures,
  agentFilters,
  agentPress,
  agentsSummary,
  filterCount,
  needsProtecting,
  NOTHING_TODAY,
  noneShown,
  OUTSIDE_MEMNOX,
  reachLine,
  RECENT_SHOWN,
  SKILL_CHIPS,
  shownAgents,
  skillChips,
  statusWord,
  unprotectedKinds,
  type AgentFilter,
  type ProtectResult,
} from '../../../core/domain/agent-lines';
import { folderProblem } from '../../../core/domain/launch-lines';
import { ago } from '../../../core/domain/session-text';
import { workspacesFrom } from '../../../core/domain/workspaces';
import { EFFECT_WORDS, activityLine, effectTone, isEffect } from '../../../core/domain/studio-lines';
import { BrandLogo } from '../../kit/logos';
import { KitButton, Spinner } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { CardGrid, EmptyState, ReadFailed, StatusWord, type Tone } from '../widgets';
import { useShellChoices } from '../shell-choices';
import { withCurrent } from '../../../core/domain/shell-lines';

/** The narrowest a card reads well at, its name, pill and numbers on their lines, as the Mac's grid sets it. */
const CARD_WIDTH = 300;

const FIGURE_INK: Record<Tone, string> = {
  good: 'text-success',
  attention: 'text-warm',
  bad: 'text-destructive',
  quiet: 'text-foreground',
};

/**
 * Every agent on this computer as the runtime sees it, as the Mac's `AgentListDestination`: a summary with filters on
 * top, a strip naming any agent running outside Memnox with the one Protect press, then the cards, the ones needing a
 * decision first, every card in a row as tall as the tallest.
 */
export function AgentListTab({ parts }: { parts: SettingsParts }) {
  const { agents, home, words, sessions, support, profiles, host } = parts;
  useObserved(agents, home, sessions, support, profiles);
  const offersProfiles = support.supports('profiles') === true;
  useEffect(() => {
    if (offersProfiles) void profiles.refresh();
  }, [offersProfiles]);
  useEffect(() => {
    void agents.refresh();
    // The workspaces the sessions ran in are the folders offered to launch in.
    sessions.start();
    return () => sessions.stop();
  }, []);
  const [note, setNote] = useState<string | undefined>(undefined);
  const [launching, setLaunching] = useState<string | undefined>(undefined);
  const [filter, setFilter] = useState<AgentFilter>('all');
  const [result, setResult] = useState<ProtectResult | undefined>(undefined);
  const { project } = useShellChoices();
  const list = agents.agents;
  const offered = list === undefined ? [] : agentFilters(list);
  // A filter that no agent is in any more, after a protect or a resume, falls back to all of them.
  useEffect(() => {
    if (list !== undefined && !offered.includes(filter)) setFilter('all');
  }, [offered.join(), filter]);
  // The current project is offered first, so an agent launches there unless the person picks another folder.
  const folders = withCurrent(
    workspacesFrom(sessions.state.cards, Date.now()).map((each) => ({ path: each.path, name: each.name })),
    project,
  );
  const said = (outcome: StudioOutcome) =>
    setNote(outcome.kind === 'proposed' ? `Waiting for you on the island: confirm it with ${words.keyTitle}.` : outcome.kind === 'failed' ? outcome.why : outcome.note);
  // Hooks every agent found here into Memnox the way setup does, then reads the cards again to say what it came to.
  const protect = (kinds: readonly string[]) => {
    if (home.protecting) return;
    setResult(undefined);
    void home.protect().then(async () => {
      await agents.refresh();
      setResult(afterProtect(kinds, agents.agents ?? [], home.protectFailed, { at: Date.now() }));
    });
  };

  if (list === undefined) return agents.unreadable ? <ReadFailed what="the agents" retry={() => void agents.refresh()} /> : null;
  const noteLine = note !== undefined && <p role="status" className="rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote">{note}</p>;
  if (list.length === 0) {
    return (
      <div className="flex flex-col gap-6">
        {noteLine}
        <EmptyState icon={Bot} title="No agents found yet" body="Install Claude Code, Codex, Cursor or another agent and it appears here." />
      </div>
    );
  }
  const open = needsProtecting(list);
  const outside = unprotectedKinds(list);
  const shown = shownAgents(list, filter);
  return (
    <div className="flex flex-col gap-6">
      {noteLine}
      <div className="flex items-center gap-3 max-[639px]:flex-col max-[639px]:items-start">
        <span className="min-w-0 flex-1 truncate text-body-sm text-muted">{agentsSummary(list)}</span>
        <div role="group" aria-label="Show" className="flex flex-wrap gap-1.5">
          {offered.map((each) => (
            <FilterChip key={each} title={AGENT_FILTER_TITLES[each]} count={filterCount(list, each)} chosen={filter === each} choose={() => setFilter(each)} />
          ))}
        </div>
      </div>
      {open !== undefined && (
        <section aria-label="Needs you" className="flex items-center gap-3 rounded-xl border border-warm/45 bg-warm/[0.08] px-4 py-3">
          <ShieldAlert size={16} className="shrink-0 text-warm" aria-hidden />
          <div className="flex min-w-0 flex-1 flex-col gap-0.5">
            <span className="flex items-center gap-1.5">
              <span className="flex gap-0.5" aria-hidden>
                {outside.map((kind) => (
                  <BrandLogo key={kind} agent={kind} name={kind} size={16} />
                ))}
              </span>
              <span className="text-body-sm font-semibold text-foreground">{open}</span>
            </span>
            {result !== undefined && outside.some((kind) => result.kinds.includes(kind)) ? <ProtectResultLine result={result} /> : <span className="text-meta text-muted">{OUTSIDE_MEMNOX}</span>}
          </div>
          <ProtectButton busy={home.protecting} press={() => protect(outside)} />
        </section>
      )}
      {shown.length === 0 ? (
        <p className="text-footnote text-muted">{noneShown(filter)}</p>
      ) : (
        <CardGrid min={CARD_WIDTH}>
          {shown.map((agent) => (
            <AgentCard
              key={agent.kind}
              agent={agent}
              keyTitle={words.keyTitle}
              busy={agents.busy === agent.kind}
              protecting={home.protecting}
              result={result !== undefined && result.kinds.includes(agent.kind) ? result : undefined}
              launchOpen={launching === agent.kind}
              protect={() => protect([agent.kind])}
              pause={() => void agents.pause(agent.kind).then(said)}
              resume={() => void agents.resume(agent.kind).then(said)}
              openLaunch={() => setLaunching(agent.kind)}
              launchForm={
                <LaunchForm
                  folders={folders}
                  profiles={offersProfiles ? (profiles.profiles ?? []).map((each) => ({ id: each.id, name: each.name })) : []}
                  busy={agents.busy === `launch/${agent.kind}`}
                  {...(host.pickProjectFolder === undefined ? {} : { pick: () => host.pickProjectFolder?.() ?? Promise.resolve(undefined) })}
                  cancel={() => setLaunching(undefined)}
                  launch={(folder, profile) =>
                    void agents.launch(agent.kind, folder, profile === '' ? undefined : { name: profile, keyTitle: words.keyTitle }).then((outcome) => {
                      said(outcome);
                      if (outcome.kind !== 'failed') setLaunching(undefined);
                    })
                  }
                />
              }
            />
          ))}
        </CardGrid>
      )}
    </div>
  );
}

/** The console's filter, as the Mac's `FilterChip`: 32 tall, bordered, the chosen one washed in its blue, a count beside it. */
function FilterChip({ title, count, chosen, choose }: { title: string; count: number; chosen: boolean; choose: () => void }) {
  return (
    <button
      type="button"
      aria-pressed={chosen}
      onClick={choose}
      className={`mx-focus inline-flex h-8 cursor-pointer items-center gap-1.5 rounded-md border px-3 text-body-sm ${chosen ? 'border-primary/45 bg-primary/[0.07] font-medium text-foreground' : 'border-panel-edge bg-card text-muted hover:bg-hover hover:text-foreground'}`}
    >
      {title}
      {count > 0 && <span className="text-meta font-medium text-muted tabular-nums">{count}</span>}
    </button>
  );
}

function ProtectButton({ busy, press }: { busy: boolean; press: () => void }) {
  return (
    <KitButton kind="primary" disabled={busy} onClick={press} title="Puts every agent found on this computer under Memnox the way setup does">
      {busy && <Spinner />}
      {busy ? 'Protecting' : 'Protect'}
    </KitButton>
  );
}

/** What a Protect press came to, in green once the agents are held and in amber while something keeps one outside. */
function ProtectResultLine({ result }: { result: ProtectResult }) {
  const Icon = result.held ? ShieldCheck : TriangleAlert;
  const when = result.at === undefined ? '' : ` · ${new Date(result.at).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}`;
  return (
    <span className={`flex items-start gap-1.5 text-meta select-text ${result.held ? 'text-success' : 'text-warm'}`}>
      <Icon size={13} className="mt-px shrink-0" aria-hidden />
      <span>{`${result.line}${when}`}</span>
    </span>
  );
}

/**
 * One agent, as the Mac's `AgentStandingCard`: who it is and where it stands at the top, the few numbers worth reading,
 * when it was last active and what it reaches, what it did last, and its controls pinned along the foot.
 */
function AgentCard({
  agent,
  keyTitle,
  busy,
  protecting,
  result,
  launchOpen,
  protect,
  pause,
  resume,
  openLaunch,
  launchForm,
}: {
  agent: AgentView;
  keyTitle: string;
  busy: boolean;
  protecting: boolean;
  result: ProtectResult | undefined;
  launchOpen: boolean;
  protect: () => void;
  pause: () => void;
  resume: () => void;
  openLaunch: () => void;
  launchForm: ReactNode;
}) {
  const standing = statusWord(agent.status);
  const figures = agentFigures(agent);
  const chips = skillChips(agent.skills, SKILL_CHIPS);
  const press = agentPress(agent);
  return (
    <article aria-label={agent.name} className={`flex h-full flex-col gap-3 rounded-xl border bg-card p-4 ${agent.status === 'unprotected' ? 'border-warm/55' : 'border-panel-edge'}`}>
      <header className="flex items-center gap-2.5">
        <BrandLogo agent={agent.kind} name={agent.name} size={30} />
        <span className="min-w-0 flex-1 truncate text-headline font-semibold text-foreground">{agent.name}</span>
        <StatusWord tone={standing.tone}>{standing.word}</StatusWord>
      </header>
      <div className="flex flex-col gap-1.5">
        {figures.length === 0 ? (
          <span className="text-meta text-faint">{NOTHING_TODAY}</span>
        ) : (
          <div className="flex items-baseline gap-4">
            {figures.map((figure) => (
              <span key={figure.label} className="flex flex-col gap-0.5">
                <span className={`text-lg font-semibold tabular-nums ${FIGURE_INK[figure.tone]}`}>{figure.value}</span>
                <span className="text-label font-medium text-muted">{figure.label}</span>
              </span>
            ))}
          </div>
        )}
        <span className="truncate text-meta text-muted">{reachLine(agent, Date.now())}</span>
      </div>
      {agent.mcpServers.length > 0 && (
        <span className="truncate text-footnote text-muted" title={agent.mcpServers.join(', ')}>
          {`Servers: ${agent.mcpServers.join(', ')}`}
        </span>
      )}
      {chips.shown.length > 0 && (
        <div className="flex min-w-0 gap-1.5 overflow-hidden" title={agent.skills.join(', ')} aria-label={`Skills: ${agent.skills.join(', ')}`}>
          {chips.shown.map((name) => (
            <SkillChip key={name} text={name} />
          ))}
          {chips.more > 0 && <SkillChip text={`+${chips.more}`} />}
        </div>
      )}
      {agent.recent.length > 0 && (
        <div className="flex flex-col gap-1.5">
          {agent.recent.slice(0, RECENT_SHOWN).map((action) => (
            <RecentRow key={action.id} action={action} />
          ))}
        </div>
      )}
      <span className="flex-1" />
      <footer className="flex items-center gap-2">
        {press === 'protect' ? (
          <ProtectButton busy={protecting} press={protect} />
        ) : press === 'resume' ? (
          <KitButton icon={Play} disabled={busy} onClick={resume} title={`Lets it carry on once you confirm with ${keyTitle}`}>
            Resume
          </KitButton>
        ) : (
          <KitButton icon={Pause} disabled={busy} onClick={pause} title="Holds everything it tries until you resume it" aria-label={`Pause ${agent.name}`}>
            Pause
          </KitButton>
        )}
        <span className="flex-1" />
        {agent.launchable && !launchOpen && (
          <KitButton icon={SquareTerminal} onClick={openLaunch} title="Opens it in a new terminal in a folder you choose">
            Launch
          </KitButton>
        )}
      </footer>
      {result !== undefined && <ProtectResultLine result={result} />}
      {launchOpen && launchForm}
    </article>
  );
}

/** A skill's name in a small bordered capsule, cut rather than wrapped. */
function SkillChip({ text }: { text: string }) {
  return <span className="inline-flex h-5 min-w-0 shrink items-center truncate rounded-md border border-panel-edge bg-hover px-1.5 text-label font-medium text-muted">{text}</span>;
}

/** One thing it did lately: the target by its last parts on top, the operation and how long ago under it, and its pill. */
function RecentRow({ action }: { action: AgentAction }) {
  const target = actionTarget(action);
  const when = ago(action.at, Date.now());
  return (
    <div className="flex items-center gap-2" title={activityLine(action)}>
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        {/* Cut at the start, as the Mac cuts it, so the file's own name stays in view. */}
        <span className="truncate text-left text-body-sm font-medium text-foreground [direction:rtl]">
          <bdi dir="ltr">{target ?? action.operation}</bdi>
        </span>
        <span className="flex min-w-0 gap-1.5 text-label text-muted">
          {target !== undefined && <span className="truncate font-mono">{action.operation}</span>}
          {when !== undefined && <span className="shrink-0">{when}</span>}
        </span>
      </div>
      <StatusWord tone={effectTone(action.effect)}>{isEffect(action.effect) ? EFFECT_WORDS[action.effect].title : action.effect}</StatusWord>
    </div>
  );
}

/** The folder an agent opens in, picked in the system's own dialog, typed whole or one of its workspaces, and a profile. */
function LaunchForm({
  folders,
  profiles,
  busy,
  pick,
  cancel,
  launch,
}: {
  folders: readonly { path: string; name: string }[];
  profiles: readonly { id: string; name: string }[];
  busy: boolean;
  pick?: () => Promise<string | undefined>;
  cancel: () => void;
  launch: (folder: string, profile: string) => void;
}) {
  const [folder, setFolder] = useState(folders[0]?.path ?? '');
  const [profile, setProfile] = useState('');
  const [problem, setProblem] = useState<string | undefined>(undefined);
  const go = () => {
    const wrong = folderProblem(folder);
    setProblem(wrong);
    if (wrong === undefined) launch(folder, profile);
  };
  return (
    <div className="flex flex-col gap-2 border-t border-panel-edge pt-3">
      <span className="text-footnote font-medium text-muted">Open it in</span>
      <div className="flex items-center gap-2">
        <input
          className="h-9 min-w-0 flex-1 mx-field rounded-lg border border-field-edge bg-field px-3 text-footnote text-foreground outline-none placeholder:text-faint focus:border-primary"
          value={folder}
          aria-label="The folder it opens in"
          placeholder="/home/you/code/project"
          onChange={(event) => setFolder(event.target.value)}
          onKeyDown={(event) => event.key === 'Enter' && go()}
          autoFocus
        />
        {pick !== undefined && (
          <KitButton
            icon={Folder}
            title="Pick the folder in the system's own dialog"
            onClick={() =>
              void pick().then((chosen) => {
                if (chosen === undefined) return;
                setFolder(chosen);
                setProblem(undefined);
              })
            }
          >
            Choose
          </KitButton>
        )}
      </div>
      {folders.length > 0 && (
        <div className="flex gap-1.5 overflow-x-auto" aria-label="Your workspaces">
          {folders.map((each) => (
            <KitButton key={each.path} kind={folder === each.path ? 'primary' : 'secondary'} title={each.path} aria-pressed={folder === each.path} onClick={() => setFolder(each.path)}>
              {each.name}
            </KitButton>
          ))}
        </div>
      )}
      {profiles.length > 0 && (
        <label className="flex flex-col gap-1.5">
          <span className="text-footnote font-medium text-muted">With a profile</span>
          <select
            className="h-9 w-full mx-field rounded-lg border border-field-edge bg-field px-3 text-footnote text-foreground outline-none focus:border-primary"
            value={profile}
            onChange={(event) => setProfile(event.target.value)}
          >
            <option value="">No profile</option>
            {profiles.map((each) => (
              <option key={each.id} value={each.id}>
                {each.name}
              </option>
            ))}
          </select>
          {profile !== '' && <span className="text-footnote text-muted">What the profile gives waits for your signature on the island as the agent opens.</span>}
        </label>
      )}
      {problem !== undefined && (
        <p role="alert" className="text-footnote text-destructive">
          {problem}
        </p>
      )}
      <div className="flex gap-2">
        <KitButton kind="primary" icon={SquareTerminal} disabled={busy} onClick={go}>
          {busy ? 'Opening' : 'Open a terminal'}
        </KitButton>
        <KitButton onClick={cancel}>Cancel</KitButton>
      </div>
    </div>
  );
}

