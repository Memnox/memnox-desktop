import type { AgentAction, AgentView } from '@memnox/core/wire';
import { Bot, Folder, Pause, Play, ShieldAlert, ShieldCheck, SquareTerminal, TriangleAlert } from 'lucide-react';
import { useEffect, useState, type ReactNode } from 'react';
import type { StudioOutcome } from '../../../core/application/studio';
import {
  AGENT_FILTER_TITLES,
  AgentListLines,
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
import { useObserved, type SettingsParts } from '../../settings/parts';
import { useShellChoices } from '../shell-choices';
import { withCurrent } from '../../../core/domain/shell-lines';
import { BrandLogo, Button, CardGrid, Chip, ChipGroup, EmptyState, ErrorLine, Field, Input, Note, ReadFailed, Select, StatusWord, type Tone } from '../../kit';

/** The narrowest a card reads well at, its name, pill and numbers on their lines, as the Mac's grid sets it. */
const CARD_WIDTH = 300;

/** The strip's shield and the logos beside it, as large as its 13 point words read. */
const STRIP_GLYPH = 16;

/** The card's own logo, the Mac's 30 point mark at its head. */
const CARD_LOGO = 30;

/** A Protect outcome's glyph, a point over its 12 point line. */
const RESULT_GLYPH = 13;

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

  if (list === undefined) return agents.unreadable ? <ReadFailed what={AgentListLines.readWhat} retry={() => void agents.refresh()} /> : null;
  const noteLine = note !== undefined && <Note>{note}</Note>;
  if (list.length === 0) {
    return (
      <div className="flex flex-col gap-6">
        {noteLine}
        <EmptyState icon={Bot} title={AgentListLines.emptyTitle} body={AgentListLines.emptyBody} />
      </div>
    );
  }
  const open = needsProtecting(list);
  const outside = unprotectedKinds(list);
  const shown = shownAgents(list, filter);
  return (
    <div className="flex flex-col gap-6">
      {noteLine}
      <div className="flex items-center gap-3 max-narrow:flex-col max-narrow:items-start">
        <span className="min-w-0 flex-1 truncate text-body-sm text-muted">{agentsSummary(list)}</span>
        <ChipGroup label={AgentListLines.show} role="group">
          {offered.map((each) => (
            <Chip key={each} role="toggle" count={filterCount(list, each)} on={filter === each} pick={() => setFilter(each)}>
              {AGENT_FILTER_TITLES[each]}
            </Chip>
          ))}
        </ChipGroup>
      </div>
      {open !== undefined && (
        <section aria-label={AgentListLines.needsYou} className="flex items-center gap-3 rounded-card border border-warm/45 bg-warm/[0.08] px-4 py-3">
          <ShieldAlert size={STRIP_GLYPH} className="shrink-0 text-warm" aria-hidden />
          <div className="flex min-w-0 flex-1 flex-col gap-0.5">
            <span className="flex items-center gap-1.5">
              <span className="flex gap-0.5" aria-hidden>
                {outside.map((kind) => (
                  <BrandLogo key={kind} agent={kind} name={kind} size={STRIP_GLYPH} />
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

function ProtectButton({ busy, press }: { busy: boolean; press: () => void }) {
  return (
    <Button kind="primary" busy={busy} onClick={press} title={AgentListLines.protectHelp}>
      {busy ? AgentListLines.protecting : AgentListLines.protect}
    </Button>
  );
}

/** What a Protect press came to, in green once the agents are held and in amber while something keeps one outside. */
function ProtectResultLine({ result }: { result: ProtectResult }) {
  const Icon = result.held ? ShieldCheck : TriangleAlert;
  const when = result.at === undefined ? '' : ` · ${new Date(result.at).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}`;
  return (
    <span className={`flex items-start gap-1.5 text-meta select-text ${result.held ? 'text-success' : 'text-warm'}`}>
      <Icon size={RESULT_GLYPH} className="mt-px shrink-0" aria-hidden />
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
    <article aria-label={agent.name} className={`flex h-full flex-col gap-3 rounded-card border bg-card p-4 ${agent.status === 'unprotected' ? 'border-warm/55' : 'border-panel-edge'}`}>
      <header className="flex items-center gap-2.5">
        <BrandLogo agent={agent.kind} name={agent.name} size={CARD_LOGO} />
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
          {AgentListLines.servers(agent.mcpServers)}
        </span>
      )}
      {chips.shown.length > 0 && (
        <div className="flex min-w-0 gap-1.5 overflow-hidden" title={agent.skills.join(', ')} aria-label={AgentListLines.skills(agent.skills)}>
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
          <Button icon={Play} disabled={busy} onClick={resume} title={AgentListLines.resumeHelp(keyTitle)}>
            {AgentListLines.resume}
          </Button>
        ) : (
          <Button icon={Pause} disabled={busy} onClick={pause} title={AgentListLines.pauseHelp} aria-label={AgentListLines.pauseNamed(agent.name)}>
            {AgentListLines.pause}
          </Button>
        )}
        <span className="flex-1" />
        {agent.launchable && !launchOpen && (
          <Button icon={SquareTerminal} onClick={openLaunch} title={AgentListLines.launchHelp}>
            {AgentListLines.launch}
          </Button>
        )}
      </footer>
      {result !== undefined && <ProtectResultLine result={result} />}
      {launchOpen && launchForm}
    </article>
  );
}

/** A skill's name in a small bordered capsule, cut rather than wrapped. */
function SkillChip({ text }: { text: string }) {
  return <span className="inline-flex h-5 min-w-0 shrink items-center truncate rounded-control border border-panel-edge bg-hover px-1.5 text-label font-medium text-muted">{text}</span>;
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
          {target !== undefined && <span className="truncate font-code">{action.operation}</span>}
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
      <span className="text-footnote font-medium text-muted">{AgentListLines.openIn}</span>
      <div className="flex items-center gap-2">
        <Input className="flex-1" value={folder} aria-label={AgentListLines.folder} placeholder={AgentListLines.folderPlaceholder} onValue={setFolder} onSubmit={go} autoFocus />
        {pick !== undefined && (
          <Button
            icon={Folder}
            title={AgentListLines.chooseHelp}
            onClick={() =>
              void pick().then((chosen) => {
                if (chosen === undefined) return;
                setFolder(chosen);
                setProblem(undefined);
              })
            }
          >
            {AgentListLines.choose}
          </Button>
        )}
      </div>
      {folders.length > 0 && (
        <div className="flex gap-1.5 overflow-x-auto" aria-label={AgentListLines.workspaces}>
          {folders.map((each) => (
            <Button key={each.path} kind={folder === each.path ? 'primary' : 'secondary'} title={each.path} aria-pressed={folder === each.path} onClick={() => setFolder(each.path)}>
              {each.name}
            </Button>
          ))}
        </div>
      )}
      {profiles.length > 0 && (
        <Field label={AgentListLines.withProfile} help={profile === '' ? undefined : AgentListLines.profileWaits}>
          <Select look="field" wide value={profile} none={AgentListLines.noProfile} options={profiles.map((each) => ({ value: each.id, label: each.name }))} onChange={setProfile} label={AgentListLines.withProfile} />
        </Field>
      )}
      {problem !== undefined && <ErrorLine>{problem}</ErrorLine>}
      <div className="flex gap-2">
        <Button kind="primary" icon={SquareTerminal} disabled={busy} onClick={go}>
          {busy ? AgentListLines.opening : AgentListLines.openTerminal}
        </Button>
        <Button onClick={cancel}>{AgentListLines.cancel}</Button>
      </div>
    </div>
  );
}

