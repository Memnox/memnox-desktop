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
  STEPS_HIDDEN_KEY,
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
import { KitButton } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { Dialog } from './SkillDialogs';

/**
 * Home's getting started steps, drawn the way the Mac's `HomeStart` and the cloud console's home draw the ladder:
 * the stage and how many steps are done, the one thing to do next with its press, what waits on an agent, the rest
 * under their two tracks, and the counts already won. The block goes once every step is done, and folds to one line
 * while the person hides it.
 */
export function HomeStart({ parts, go, actions, mode }: { parts: SettingsParts; go: (route: Route) => void; actions: number; mode: HomeMode | undefined }) {
  const { agents, studio, memory, skills, hub, pairing, tools, home, words, support } = parts;
  useObserved(agents, studio, memory, skills, hub, pairing, tools, home);
  const [hidden, setHidden] = useState(() => localStorage.getItem(STEPS_HIDDEN_KEY) === 'true');
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

  const toggle = () => {
    localStorage.setItem(STEPS_HIDDEN_KEY, String(!hidden));
    setHidden(!hidden);
  };
  // Stopping rather than watching is confirmed here first; every other step opens where it is done.
  const press = (step: HomeStep) => {
    if (step.id === 'enforce' && !step.done) setConfirming(true);
    else go(STEP_ROUTE[step.id]);
  };
  const hide = (
    <KitButton onClick={toggle} title={hidden ? 'Show the steps again' : 'Fold these steps to one line until you want them again'}>
      {hidden ? 'Show' : 'Hide'}
    </KitButton>
  );

  if (hidden) {
    return (
      <section aria-label="What to do next, hidden" className="flex items-center gap-3 rounded-xl border border-panel-edge bg-card px-5 py-3">
        <span className="flex-1 text-body-sm font-medium text-foreground">{STAGE_LABEL[setup.stage]}</span>
        <StepsDone setup={setup} />
        {hide}
      </section>
    );
  }
  return (
    <section aria-label="What to do next" className="flex flex-col gap-3 rounded-xl border border-panel-edge bg-card p-5">
      <div className="flex flex-col gap-1">
        <div className="flex items-center gap-3">
          <h2 className="flex-1 text-base font-medium text-foreground">{STAGE_LABEL[setup.stage]}</h2>
          <StepsDone setup={setup} />
          {hide}
        </div>
        <p className="text-body-sm text-muted">{STAGE_MEANS[setup.stage]}</p>
      </div>
      {setup.next !== undefined && <NextRung step={setup.next} busy={setup.next.id === 'enforce' && home.enforcing} press={press} />}
      {home.enforceNote !== undefined && <p className="text-body-sm text-muted select-text">{home.enforceNote}</p>}
      {setup.waiting.map((step) => (
        <WaitingRung key={step.id} step={step} />
      ))}
      <div className="grid grid-cols-[repeat(auto-fit,minmax(280px,1fr))] gap-4">
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
                    <button
                      type="button"
                      title={step.value}
                      aria-label={`${step.title}, ${step.done ? 'done' : 'not yet'}`}
                      onClick={() => press(step)}
                      className="mx-focus flex cursor-pointer items-start gap-2 text-left text-body-sm"
                    >
                      {step.done ? <Check size={14} strokeWidth={2.4} className="mt-0.5 shrink-0 text-primary" aria-hidden /> : <Circle size={14} className="mt-0.5 shrink-0 text-faint" aria-hidden />}
                      <span className={step.done ? 'text-muted' : 'text-foreground'}>{step.title}</span>
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          );
        })}
      </div>
      {setup.standing.length > 0 && (
        <dl className="flex flex-wrap gap-x-6 gap-y-2 border-t border-panel-edge pt-3">
          {setup.standing.map((count) => (
            <div key={count.label} className="flex items-baseline gap-1.5">
              <dd className="text-body-sm font-semibold text-foreground tabular-nums">{count.count}</dd>
              <dt className="text-meta text-muted">{count.label}</dt>
            </div>
          ))}
        </dl>
      )}
      {confirming && (
        <Dialog
          title={HomeEnforce.title}
          close={() => setConfirming(false)}
          footer={
            <>
              <KitButton
                onClick={() => {
                  setConfirming(false);
                  go(STEP_ROUTE.enforce);
                }}
              >
                {HomeEnforce.readFirst}
              </KitButton>
              <span className="flex-1" />
              <KitButton onClick={() => setConfirming(false)}>Cancel</KitButton>
              <KitButton
                kind="primary"
                icon={Hand}
                onClick={() => {
                  setConfirming(false);
                  void home.enforce();
                }}
              >
                {HomeEnforce.confirm}
              </KitButton>
            </>
          }
        >
          <p className="text-body-sm text-foreground">{HomeEnforce.message}</p>
          <p className="text-body-sm text-muted">{HomeEnforce.detail}</p>
        </Dialog>
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
    <span className="flex items-center gap-1.5" aria-label={`${setup.completed} of ${setup.steps.length} steps done`}>
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
    <div className="flex flex-col gap-1.5 rounded-xl border border-primary/30 bg-primary/5 p-4">
      <p className="font-code text-label font-medium tracking-[0.16em] text-primary uppercase">Do this next</p>
      <p className="text-base font-medium text-foreground">{step.title}</p>
      <p className="text-body-sm text-muted">{step.value}</p>
      <p className="pt-1 text-body-sm text-foreground select-text">{step.how}</p>
      <div className="pt-1.5">
        <KitButton kind="primary" trailing={ArrowRight} disabled={busy} onClick={() => press(step)}>
          {step.action}
        </KitButton>
      </div>
    </div>
  );
}

/** A step nobody can hurry, drawn quietly as a state rather than a task: no accent and no press. */
function WaitingRung({ step }: { step: HomeStep }) {
  return (
    <div className="flex items-start gap-2 rounded-xl border border-panel-edge p-4">
      <Clock size={13} className="mt-0.5 shrink-0 text-muted" aria-hidden />
      <div className="flex flex-col gap-1">
        <p className="font-code text-label font-medium text-muted">{WAITING_LABEL}</p>
        <p className="text-body-sm font-medium text-foreground">{step.title}</p>
        <p className="text-meta text-muted">{WAITING_MEANS}</p>
      </div>
    </div>
  );
}
