import { AGENT_STATUS } from '@memnox/core/wire';
import { ArrowRight, Check, Circle, Clock, Hand } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { Route } from '../../../core/domain/destinations';
import {
  HomeEnforce,
  homeSetup,
  progressLine,
  restOf,
  STAGE_LABEL,
  STAGE_MEANS,
  STEP_ROUTE,
  ALL_STEPS,
  CARD_TITLE,
  FEWER_STEPS,
  TRACK_LABEL,
  TRACK_LEAD,
  TRACKS,
  WAITING_LABEL,
  WAITING_MEANS,
  type HomeMode,
  type HomeSetup,
  type HomeStanding,
  type HomeStep,
} from '../../../core/domain/home-steps';
import { HomeStartLines } from '../../../core/domain/home-page-lines';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { Button, ConfirmDialog, PRESS_DIP, Pressable } from '../../kit';
import { PAGE_METRICS } from '../page-metrics';

/** The two tracks sit side by side once each has this much room, as the Mac's grid does. */
const TRACK_MIN = PAGE_METRICS.homeTrack;

/** A step's tick or ring, as the button glyphs are, the tick drawn a little heavy. */
const STEP_GLYPH = 14;
const STEP_TICK_STROKE = 2.4;

/** The clock on a waiting step, a point under the step's own glyphs. */
const WAITING_GLYPH = 13;

/**
 * Home's one Do this next card, as the Mac's `HomeStart` draws it: the stage and how many steps are done, the one thing
 * to do next with its press, and what waits on an agent; Show all steps opens the rest under their two tracks with the
 * counts already won. The card goes once every step is done.
 */
export function HomeStart({ parts, go, actions, mode, openSetup }: { parts: SettingsParts; go: (route: Route) => void; actions: number; mode: HomeMode | undefined; openSetup: () => void }) {
  const { agents, studio, memory, skills, hub, pairing, tools, home, words, support, preferences } = parts;
  useObserved(agents, studio, memory, skills, hub, pairing, tools, home);
  const [allSteps, setAllSteps] = useState(false);
  const [confirming, setConfirming] = useState(false);
  useEffect(() => {
    void tools.refresh();
    void pairing.loadDevices();
    if (support.supports('rules') !== false) void studio.refresh();
    if (support.supports('memory-facts') !== false) void memory.refreshSources();
    if (support.supports('agents') !== false) void agents.refresh();
    if (support.supports('skills-hub') !== false) void skills.refresh();
    if (support.supports('mcp-hub') !== false) void hub.refresh();
  }, []);

  const shown = agents.agents ?? [];
  const standing: HomeStanding = {
    setupFinished: preferences.setupDone,
    agents: shown.length,
    agentsProtected: shown.filter((agent) => agent.status !== AGENT_STATUS.UNPROTECTED).length,
    rulesInForce: studio.rules?.rules.length ?? 0,
    // Today's count resets at midnight, so the agents' own recent actions keep the step ticked the morning after.
    actionsRecorded: Math.max(actions, shown.reduce((sum, agent) => sum + agent.recent.length, 0)),
    phonesPaired: pairing.devices.length,
    mode,
    appsConnected: tools.connectedCount,
    sourcesLinked: memory.sources?.length ?? 0,
    skillsShared: skills.hub?.skills.length ?? 0,
    serversShared: hub.hub?.servers.length ?? 0,
  };
  const setup = homeSetup(standing, words.keyTitle);
  if (setup.climbed) return null;

  // Stopping rather than watching is confirmed here first, setup opens where it was left, every other step opens where it is done.
  const press = (step: HomeStep) => {
    if (step.id === 'finishSetup') openSetup();
    else if (step.id === 'enforce' && !step.done) setConfirming(true);
    else go(STEP_ROUTE[step.id]);
  };
  const more = <Button onClick={() => setAllSteps(!allSteps)}>{allSteps ? FEWER_STEPS : ALL_STEPS}</Button>;

  return (
    <section aria-label={CARD_TITLE} className="flex flex-col gap-3 rounded-xl border border-panel-edge bg-card p-5">
      <div className="flex flex-col gap-1">
        <div className="flex items-center gap-3">
          <h2 className="flex-1 text-base font-medium text-foreground">{STAGE_LABEL[setup.stage]}</h2>
          <StepsDone setup={setup} />
          {more}
        </div>
        <p className="text-body-sm text-muted">{STAGE_MEANS[setup.stage]}</p>
      </div>
      {setup.next !== undefined && <NextRung step={setup.next} busy={setup.next.id === 'enforce' && home.enforcing} press={press} />}
      {home.enforceNote !== undefined && <p className="text-body-sm text-muted select-text">{home.enforceNote}</p>}
      {setup.waiting.map((step) => (
        <WaitingRung key={step.id} step={step} />
      ))}
      {allSteps && (
        <div className="grid gap-4" style={{ gridTemplateColumns: `repeat(auto-fill, minmax(${TRACK_MIN}px, 1fr))` }}>
          {TRACKS.map((track) => {
            const steps = restOf(setup, track);
            if (steps.length === 0) return null;
            return (
              <div key={track} className="flex flex-col gap-1.5">
                <p className="text-body-sm font-medium text-foreground">{TRACK_LABEL[track]}</p>
                <p className="text-meta text-muted">{TRACK_LEAD[track]}</p>
                <ul className="flex flex-col gap-1.5 pt-1">
                  {steps.map((step) => (
                    <li key={step.id}>
                      <Pressable
                        title={step.value}
                        aria-label={HomeStartLines.step(step.title, step.done)}
                        onClick={() => press(step)}
                        className={`mx-focus flex cursor-pointer items-start gap-2 text-left text-body-sm ${PRESS_DIP}`}
                      >
                        {step.done ? <Check size={STEP_GLYPH} strokeWidth={STEP_TICK_STROKE} className="mt-0.5 shrink-0 text-primary" aria-hidden /> : <Circle size={STEP_GLYPH} className="mt-0.5 shrink-0 text-faint" aria-hidden />}
                        <span className={step.done ? 'text-muted' : 'text-foreground'}>{step.title}</span>
                      </Pressable>
                    </li>
                  ))}
                </ul>
              </div>
            );
          })}
        </div>
      )}
      {allSteps && setup.standing.length > 0 && (
        <dl className="flex flex-wrap gap-x-4 gap-y-1.5 border-t border-panel-edge pt-2">
          {/* The label first and its count after it, as the Mac's Standing reads. */}
          {setup.standing.map((count) => (
            <div key={count.label} className="flex items-baseline gap-1">
              <dt className="text-meta text-muted">{count.label}</dt>
              <dd className="font-code text-body-sm font-medium text-foreground tabular-nums">{count.count}</dd>
            </div>
          ))}
        </dl>
      )}
      {confirming && (
        // The Mac asks with its console confirm, in blue since stopping takes nothing away, reading first as the aside.
        <ConfirmDialog
          icon={Hand}
          tone="neutral"
          title={HomeEnforce.title}
          message={HomeEnforce.message}
          detail={HomeEnforce.detail}
          confirm={HomeEnforce.confirm}
          aside={{
            label: HomeEnforce.readFirst,
            act: () => {
              setConfirming(false);
              go(STEP_ROUTE.enforce);
            },
          }}
          cancel={() => setConfirming(false)}
          act={() => {
            setConfirming(false);
            void home.enforce();
          }}
        />
      )}
    </section>
  );
}

/** How far along the steps are, as a thin ring filling in the console's blue beside "3 of 8 done". */
function StepsDone({ setup }: { setup: HomeSetup }) {
  const share = setup.steps.length === 0 ? 0 : setup.completed / setup.steps.length;
  const radius = 6;
  const round = 2 * Math.PI * radius;
  return (
    <span className="flex items-center gap-1.5" aria-label={HomeStartLines.stepsDone(setup.completed, setup.steps.length)}>
      <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden className="-rotate-90">
        <circle cx="7" cy="7" r={radius} fill="none" stroke="var(--color-panel-edge)" strokeWidth="2" />
        <circle cx="7" cy="7" r={radius} fill="none" stroke="var(--color-primary)" strokeWidth="2" strokeLinecap="round" strokeDasharray={`${round * share} ${round}`} />
      </svg>
      <span className="text-meta font-medium text-muted tabular-nums">{progressLine(setup)}</span>
    </span>
  );
}

/** The one thing to do now, and the only part of the block with a filled press, as the cloud's Do this next rung. */
function NextRung({ step, busy, press }: { step: HomeStep; busy: boolean; press: (step: HomeStep) => void }) {
  return (
    <div className="flex flex-col gap-1.5 rounded-card border border-primary/30 bg-primary/5 p-4">
      <p className="font-code text-label font-medium tracking-[0.16em] text-primary">{CARD_TITLE.toUpperCase()}</p>
      <p className="text-base font-medium text-foreground">{step.title}</p>
      <p className="text-body-sm text-muted">{step.value}</p>
      <p className="pt-1 text-body-sm text-foreground select-text">{step.how}</p>
      <div className="pt-1.5">
        <Button kind="primary" trailing={ArrowRight} disabled={busy} onClick={() => press(step)}>
          {step.action}
        </Button>
      </div>
    </div>
  );
}

/** A step nobody can hurry, drawn quietly as a state rather than a task: no accent and no press. */
function WaitingRung({ step }: { step: HomeStep }) {
  return (
    <div className="flex items-start gap-2 rounded-card border border-panel-edge p-4">
      <Clock size={WAITING_GLYPH} className="mt-0.5 shrink-0 text-muted" aria-hidden />
      <div className="flex flex-col gap-1">
        <p className="font-code text-label font-medium text-muted">{WAITING_LABEL}</p>
        <p className="text-body-sm font-medium text-foreground">{step.title}</p>
        <p className="text-meta text-muted">{WAITING_MEANS}</p>
      </div>
    </div>
  );
}
