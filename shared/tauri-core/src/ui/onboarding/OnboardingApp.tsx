import {
  ArrowRight,
  AudioLines,
  Briefcase,
  Building2,
  Cloud,
  Check,
  ChevronDown,
  ChevronLeft,
  ChevronUp,
  Fingerprint,
  ListChecks,
  Monitor,
  Network,
  RotateCw,
  ShieldCheck,
  Settings as SettingsIcon,
  Smartphone,
  Sparkles,
  UserRound,
  UserRoundSearch,
  Volume2,
  VolumeX,
  type LucideIcon,
} from 'lucide-react';
import { Fragment, useEffect, useRef, useState, type ReactNode } from 'react';
import {
  AGENT_PLACES,
  endLinks,
  type AgentPlace,
  type EndLink,
  FirstRunCoverage,
  FirstRunQuestions,
  GuideLines,
  GuideMemory,
  askOrder,
  askRoutes,
  AUDIENCES,
  nextStep,
  ONBOARDING_IDS,
  ONBOARDING_STEPS,
  TRY_DETAIL,
  TRY_PROMPT,
  TRY_TITLE,
  type AskRoute,
  type Audience,
  placeInfo,
  previousStep,
  progressOf,
  rowSpoken,
  setTitle,
  startingPacks,
  stepCounter,
  stepHeading,
  suggestedPlace,
  throughCloud,
  type OnboardingStage,
  type OnboardingStep,
  type WelcomeRow,
} from '../../core/domain/onboarding';
import { agentsFoundLine, firstName, packTitle } from '../../core/domain/setup-steps';
import type { StepState } from '../../core/domain/step-state';
import { BrandLogo, MEMNOX_MARK } from '../kit/logos';
import { IconTile, MemnoxTile, NeedsHint, QuietLine, StatusMark } from '../settings/kit';
import { useLook, useObserved, usePreferences, type SettingsParts } from '../settings/parts';
import { IslandDemo, useDemoTour } from './IslandDemo';
import { Button, Pressable, Spinner } from '../kit';
import { OnboardingLines } from '../../core/domain/onboarding-lines';
import { orderedProfiles } from '../../core/domain/agent-work-lines';
import { LevelPill } from '../app/capability-strip';

const END_ICONS: Record<EndLink['id'], LucideIcon> = { name: UserRound, voice: AudioLines };
const AUDIENCE_ICONS: Record<Audience, LucideIcon> = { me: UserRound, away: Smartphone, team: Building2 };
const ASK_ICONS: Record<AskRoute, LucideIcon> = { here: Fingerprint, phone: Smartphone, cloud: Building2 };

/**
 * The first run on a fresh computer, with no account: the wordmark and Get Started, then three short steps with a
 * progress bar (connect, the grants this system asks for, the starting rules), each with its safe default chosen,
 * and an end screen with one next action. A scrolling column sits beside the island, with Back and Mute at the foot.
 * The veil lies over the whole screen as the Mac's does, dark over a blue wash, since nothing blurs the desktop here.
 */
export function OnboardingApp({ parts, stage: firstStage = 'intro', step: firstStep = 0 }: { parts: SettingsParts; stage?: OnboardingStage; step?: OnboardingStep }) {
  useLook(parts.preferences);
  const [stage, setStage] = useState<OnboardingStage>(firstStage);
  const [step, setStep] = useState<OnboardingStep>(firstStep);
  // What the starting rules step proposed, said again on the end screen.
  const [proposed, setProposed] = useState<string | undefined>(undefined);
  // The answers to the two questions, each skippable, which the end screen says back.
  const [answers, setAnswers] = useState<Answers>({});
  const answer = (change: Partial<Answers>) => setAnswers((before) => ({ ...before, ...change }));
  const guide = useGuide(parts);
  // The real island plays each part beside the steps, round and round; a row pressed plays its part at once.
  // A preview can start on one part with ?part=, so each part can be looked at.
  const [part] = useDemoTour((new URLSearchParams(location.search).get('part') ?? undefined) as WelcomeRow['id'] | undefined);
  // The part the island moved on to is said once, and only while the first step is on screen, as the Mac's `follow`.
  useEffect(() => {
    if (stage === 'steps' && ONBOARDING_IDS[step] === 'connect' && guideMemory.first(`part-${part}`)) guide(rowSpoken(part, parts.host.platform), false);
  }, [part, stage, step]);

  // Each stage is introduced once in a first run, as the Mac's `firstVisit`, so going Back stays quiet.
  useEffect(() => {
    const at = stage === 'steps' ? `step-${step}` : stage;
    if (!guideMemory.first(at)) return;
    const id = ONBOARDING_IDS[step];
    if (stage === 'steps' && id === 'who') {
      guide(GuideLines.welcome(firstName(parts.preferences.name)));
      guide(GuideLines.who, false);
    }
    if (stage === 'steps' && id === 'agents') guide(GuideLines.place);
    if (stage === 'steps' && id === 'connect') guide(GuideLines.setup(parts.host.platform));
    if (stage === 'steps' && id === 'ask-where') guide(GuideLines.askWhere);
    if (stage === 'steps' && id === 'rules') guide(GuideLines.boundaries(parts.host.platform));
    if (stage === 'done') guide(GuideLines.done);
  }, [stage, step]);

  // The opening lies over the whole screen, as the Mac's veil; the steps take the ordinary window.
  const veiled = stage === 'intro';
  useEffect(() => parts.host.onboardingVeil?.(veiled), [veiled]);

  useEffect(() => {
    const keys = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      const before = previousStep(step);
      if (stage === 'done') setStage('steps');
      else if (stage === 'steps' && before !== undefined) setStep(before);
    };
    window.addEventListener('keydown', keys);
    return () => window.removeEventListener('keydown', keys);
  }, [stage, step]);

  if (veiled) return <Veil next={() => setStage('steps')} />;
  const finish = () => {
    parts.preferences.finishSetup();
    parts.host.close();
  };
  const done = stage === 'done';
  const id = ONBOARDING_IDS[step];
  const back = () => (done ? setStage('steps') : setStep(previousStep(step) ?? step));
  const forward = () => {
    const after = nextStep(step);
    if (after === undefined) setStage('done');
    else setStep(after);
  };
  return (
    <div className="flex h-full flex-col bg-background text-foreground">
      <div className="flex flex-col gap-2 px-onboard-side pt-onboard-top">
        <div className="h-1 overflow-hidden rounded-full bg-ink-fill">
          <div className="h-full rounded-full bg-ink-primary transition-[width] duration-500 ease-out" style={{ width: `${progressOf(step, stage) * 100}%` }} />
        </div>
        <div className="flex gap-4">
          {ONBOARDING_STEPS.map((name, index) => (
            <span key={name} className={`flex items-center gap-1 text-footnote ${index === step && !done ? 'font-semibold text-ink-primary' : 'text-ink-tertiary'}`}>
              {(index < step || done) && <Check size={10} strokeWidth={3.4} />}
              {name}
            </span>
          ))}
        </div>
      </div>
      <div className="flex min-h-0 flex-1 justify-center gap-12 px-14">
        <ScrollColumn key={done ? 'done' : step}>
          {done && <EndScreen parts={parts} proposed={proposed} answers={answers} finish={finish} />}
          {!done && id === 'who' && <WhoStep answers={answers} answer={answer} next={forward} />}
          {!done && id === 'agents' && <AgentsStep parts={parts} answers={answers} answer={answer} next={forward} />}
          {!done && id === 'connect' && <ConnectStep parts={parts} next={forward} />}
          {!done && id === 'ask-where' && <AskWhereStep parts={parts} answers={answers} next={forward} />}
          {!done && id === 'rules' && (
            <RulesStep
              parts={parts}
              next={(note) => {
                setProposed(note);
                setStage('done');
              }}
            />
          )}
        </ScrollColumn>
        <IslandDemo part={part} />
      </div>
      <footer className="flex h-11 shrink-0 items-center gap-3 px-7 pb-3">
        {(step > 0 || done) && (
          <Button icon={ChevronLeft} onClick={back}>
            {OnboardingLines.back}
          </Button>
        )}
        <span className="flex-1" />
        <MuteButton parts={parts} />
        <span className="text-footnote text-ink-tertiary">{OnboardingLines.changeLater}</span>
      </footer>
    </div>
  );
}

/** What the two questions were answered with; each stays undefined until answered. */
interface Answers {
  readonly audience?: Audience;
  readonly place?: AgentPlace;
}

/** Set once the first run put the agents found here under Memnox by itself, so it is tried once and then offered. */
let autoProtected = false;

/** The lines said in this first run, kept for the window's life so every page reads the same memory. */
const guideMemory = new GuideMemory();

/**
 * Says a guide line in Memnox's voice unless the person muted the first run. A line cuts off the one before
 * it, as the Mac's `guide` does, unless it is told to wait its turn.
 */
function useGuide(parts: SettingsParts): (line: string, interrupting?: boolean) => void {
  return (line: string, interrupting = true) => {
    if (parts.preferences.guideMuted) return;
    const before = interrupting ? (parts.host.voices.stop?.() ?? Promise.resolve()) : Promise.resolve();
    void before
      .catch(() => undefined)
      .then(() => parts.host.voices.say(line))
      .catch(() => undefined);
  };
}

function MuteButton({ parts }: { parts: SettingsParts }) {
  usePreferences();
  const muted = parts.preferences.guideMuted;
  return (
    <Button
      icon={muted ? VolumeX : Volume2}
      onClick={() => {
        parts.preferences.guideMuted = !muted;
        // Muting silences what is being said now too, as the Mac's `stopGuide`.
        if (!muted) void parts.host.voices.stop?.().catch(() => undefined);
      }}
    >
      {muted ? 'Unmute' : 'Mute'}
    </Button>
  );
}

/** The wordmark and Get Started on the dark veil; the name is asked on the end screen or in Settings, never here. */
function Veil({ next }: { next: () => void }) {
  return (
    <div className="relative flex h-full flex-col items-center justify-center bg-(image:--mx-onboard-veil) text-white">
      <div className="flex animate-[card-in_600ms_cubic-bezier(.2,.8,.2,1)_both] flex-col items-center gap-11">
        <div className="flex items-center gap-4 drop-shadow-onboard-wordmark">
          <img src={MEMNOX_MARK} alt="" className="h-onboard-wordmark w-auto" draggable={false} />
          <span className="font-display text-onboard-wordmark leading-none font-semibold tracking-tight">{OnboardingLines.brand}</span>
        </div>
        <Button kind="glass" trailing={ArrowRight} onClick={next} autoFocus>
          {OnboardingLines.getStarted}
        </Button>
      </div>
    </div>
  );
}

/** The 440 wide column, scrolling with fades at the edges where more waits, and More below until the end. */
function ScrollColumn({ children }: { children: ReactNode }) {
  const scroller = useRef<HTMLDivElement>(null);
  const [more, setMore] = useState(false);
  const measure = () => {
    const box = scroller.current;
    if (box !== null) setMore(box.scrollTop + box.clientHeight < box.scrollHeight - 4);
  };
  useEffect(() => {
    measure();
    const observer = new ResizeObserver(measure);
    if (scroller.current !== null) observer.observe(scroller.current);
    return () => observer.disconnect();
  }, []);
  return (
    <div className="relative w-onboard-scroll shrink-0">
      <div
        ref={scroller}
        onScroll={measure}
        className="h-full animate-[satellite-right_500ms_cubic-bezier(.2,.8,.2,1)_both] overflow-y-auto pr-onboard-gutter"
        style={{ maskImage: more ? 'var(--mx-onboard-fade)' : undefined }}
      >
        <div className="flex flex-col gap-5 py-9">{children}</div>
      </div>
      {more && (
        <span className="absolute bottom-2 left-1/2 -translate-x-1/2 rounded-full shadow-onboard-more">
          <Button icon={ChevronDown} onClick={() => scroller.current?.scrollTo({ top: scroller.current.scrollHeight, behavior: 'smooth' })}>
            {OnboardingLines.moreBelow}
          </Button>
        </span>
      )}
    </div>
  );
}

/** `StepTitle`: "Step N of 3" when it is a step, then 30 semibold over its line 15 at ink 62%. */
function StepTitle({ counter, title, detail }: { counter?: string; title: string; detail: string }) {
  return (
    <header className="flex flex-col gap-2">
      {counter !== undefined && <span className="text-footnote font-medium text-ink-tertiary">{counter}</span>}
      <h1 className="font-display text-onboard-title leading-tight font-semibold text-ink">{title}</h1>
      <p className="text-headline text-ink-secondary">{detail}</p>
    </header>
  );
}

/** `KitCard`: radius 16, padding 16, the card fill; a header with its symbol, title and line, then the rows. */
function KitCard({ icon: Icon, title, detail, children }: { icon?: LucideIcon; title?: string; detail?: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-4 rounded-2xl bg-card p-4">
      {title !== undefined && (
        <header className="flex gap-3">
          {Icon !== undefined && (
            <span className="grid w-5 shrink-0 place-items-start text-ink-primary">
              <Icon size={17} strokeWidth={1.8} />
            </span>
          )}
          <span className="flex flex-col gap-0.5">
            <span className="text-headline font-semibold text-ink">{title}</span>
            {detail !== undefined && <span className="text-body text-ink-secondary">{detail}</span>}
          </span>
        </header>
      )}
      {children !== null && children !== undefined && <div className="flex flex-col">{children}</div>}
    </section>
  );
}

/** `KitRow`: a tile, the title 14 semibold over its line 12, an optional hint, and the control at the end. */
function KitRow({ tile, title, detail, hint, trailing }: { tile: ReactNode; title: string; detail: string; hint?: string; trailing?: ReactNode }) {
  return (
    <div className="flex items-center gap-3 py-2.5">
      {tile}
      <span className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="text-callout font-semibold text-ink">{title}</span>
        <span className="text-footnote text-ink-secondary">{detail}</span>
        {hint !== undefined && (
          <span className="pt-0.5">
            <NeedsHint why={hint} size={12} />
          </span>
        )}
      </span>
      {trailing !== undefined && <span className="ml-2 flex shrink-0 items-center gap-1.5">{trailing}</span>}
    </div>
  );
}

function KitDivider() {
  return <div className="ml-settings-row-text h-px bg-ink-faint-fill" />;
}

/** A row's done mark, or its control until then. */
function DoneOr({ state, children }: { state: StepState; children: ReactNode }) {
  return state.kind === 'done' ? <StatusMark state={state} /> : <>{children}</>;
}


/** Step 1: the service starting by itself, the confirm key, and the agents found here, on one screen. */
function ConnectStep({ parts, next }: { parts: SettingsParts; next: () => void }) {
  const { steps, words, agents, home } = parts;
  useObserved(steps, agents, home);
  useEffect(() => {
    void steps.refresh().then(() => steps.recheckOnce());
    void agents.refresh();
    // The grants are read now, so they are settled by the time their step shows.
    void steps.readPermissions();
    // The voice is optional, but it is fetched now so it has arrived by the time anybody asks for it.
    if (steps.voiceInstall.kind === 'idle') void steps.installVoice();
  }, []);
  const service = steps.service;
  const key = steps.keyState;
  const found = agents.agents;
  // What was found is put under Memnox once by itself, the way setup does, while the service runs; Protect stays for
  // what that could not reach, as on the Mac.
  const unprotected = (found ?? []).filter((agent) => agent.status === 'unprotected').map((agent) => agent.kind);
  const [protectedByItself, setProtectedByItself] = useState(false);
  useEffect(() => {
    if (unprotected.length === 0 || autoProtected || service.state.kind !== 'done' || home.protecting) return;
    autoProtected = true;
    void home.protect().then(async () => {
      await agents.refresh();
      setProtectedByItself(home.protectFailed === undefined);
    });
  }, [unprotected.join(), service.state.kind]);
  // Before the agents method answers, the agents the voice found stand in, so a fresh computer still shows its agents.
  const fallback = steps.agents.filter((agent) => agent.installed);
  const heading = stepHeading(2, words.keyTitle);
  return (
    <>
      <StepTitle counter={stepCounter(2)} title={heading.title} detail={heading.detail} />
      <KitCard icon={Monitor} title={OnboardingLines.onComputer} detail={OnboardingLines.onComputerDetail}>
        <KitRow
          tile={<MemnoxTile />}
          title={OnboardingLines.service}
          detail={service.detail}
          hint={service.state.kind === 'needs' ? service.state.why : undefined}
          trailing={
            <DoneOr state={service.state}>
              {parts.setup.state.doing !== undefined ? (
                <Spinner />
              ) : (
                <Button icon={RotateCw} onClick={() => void steps.checkService()}>
                  {OnboardingLines.checkAgain}
                </Button>
              )}
            </DoneOr>
          }
        />
        <KitDivider />
        <KitRow
          tile={<IconTile icon={Fingerprint} />}
          title={words.approveTitle}
          detail={OnboardingLines.keyDetail}
          hint={key.kind === 'needs' ? key.why : undefined}
          trailing={
            <DoneOr state={key}>
              <Button icon={RotateCw} onClick={() => void steps.checkKey()}>
                {OnboardingLines.checkAgain}
              </Button>
            </DoneOr>
          }
        />
      </KitCard>
      <KitCard icon={UserRoundSearch} title={OnboardingLines.agentsHere} detail={found === undefined ? OnboardingLines.looking : agentsFoundLine(found)}>
        {found !== undefined
          ? found.map((agent, index) => (
              <Fragment key={agent.kind}>
                {index > 0 && <KitDivider />}
                <KitRow
                  tile={<BrandLogo agent={agent.kind} name={agent.name} size={26} />}
                  title={agent.name}
                  detail={agent.status === 'unprotected' ? OnboardingLines.unprotected : agent.status === 'paused' ? OnboardingLines.paused : OnboardingLines.protected}
                  trailing={
                    agent.status === 'unprotected' ? (
                      <Button disabled={home.protecting} onClick={() => void home.protect().then(() => agents.refresh())}>
                        {OnboardingLines.protect}
                      </Button>
                    ) : (
                      <StatusMark state={{ kind: 'done' }} />
                    )
                  }
                />
              </Fragment>
            ))
          : fallback.map((agent, index) => (
              <Fragment key={agent.kind}>
                {index > 0 && <KitDivider />}
                <KitRow tile={<BrandLogo agent={agent.kind} name={agent.label} size={26} />} title={agent.label} detail={OnboardingLines.foundHere} />
              </Fragment>
            ))}
        {found !== undefined && found.length === 0 && (
          <KitRow tile={<IconTile icon={UserRoundSearch} />} title={OnboardingLines.noAgent} detail={OnboardingLines.noAgentDetail} trailing={<Button onClick={() => void agents.refresh()}>{OnboardingLines.checkAgain}</Button>} />
        )}
        {protectedByItself && <QuietLine size={12}>{FirstRunQuestions.protectedByItself}</QuietLine>}
        {home.protectFailed !== undefined && <NeedsHint why={home.protectFailed} size={12} />}
      </KitCard>
      <Button kind="primary" wide trailing={ArrowRight} onClick={next}>
        {OnboardingLines.continue}
      </Button>
    </>
  );
}

/** One answer of a question as a row pressed whole, with the radio mark the rule packs wear. */
function AnswerRow({ icon, title, detail, on, disabled, pick }: { icon: LucideIcon; title: string; detail: string; on: boolean; disabled?: boolean; pick: () => void }) {
  return (
    <Pressable role="radio" aria-checked={on} disabled={disabled} onClick={pick} className="cursor-pointer text-left disabled:cursor-default">
      <KitRow tile={<IconTile icon={icon} />} title={title} detail={detail} trailing={<span aria-hidden className={`size-4 rounded-full border-2 ${on ? 'border-primary bg-primary' : 'border-ink-edge'}`} />} />
    </Pressable>
  );
}

const PLACE_ICONS: Record<AgentPlace, LucideIcon> = {
  'computer-coding': Monitor,
  'computer-app': Monitor,
  hosted: Cloud,
  'inside-app': Network,
  'no-code': Network,
  'own-code': Network,
  'none-yet': Briefcase,
};

/**
 * Step 3, the second question: where the person's agent runs. On this computer the agents found are already under
 * Memnox and the job can go to one of them; anywhere else the agent reaches Memnox through Memnox Cloud, offered and
 * never required.
 */
function AgentsStep({ parts, answers, answer, next }: { parts: SettingsParts; answers: Answers; answer: (change: Partial<Answers>) => void; next: () => void }) {
  const { agents, words } = parts;
  useObserved(agents);
  const found = agents.agents ?? [];
  const place = answers.place ?? suggestedPlace(found.length);
  useEffect(() => {
    if (agents.agents === undefined) void agents.refresh();
  }, []);
  const info = place === undefined ? undefined : placeInfo(place);
  const heading = stepHeading(1, words.keyTitle);
  return (
    <>
      <StepTitle counter={stepCounter(1)} title={heading.title} detail={heading.detail} />
      <KitCard icon={Network} title={FirstRunQuestions.placeTitle}>
        <div role="radiogroup" aria-label={FirstRunQuestions.placeTitle} className="flex flex-col">
          {AGENT_PLACES.map((each, index) => (
            <Fragment key={each.id}>
              {index > 0 && <KitDivider />}
              <AnswerRow icon={PLACE_ICONS[each.id]} title={each.title} detail={each.detail} on={place === each.id} pick={() => answer({ place: each.id })} />
            </Fragment>
          ))}
        </div>
      </KitCard>
      {info !== undefined && (
        <KitCard icon={info.local ? Monitor : Cloud} title={FirstRunQuestions.reaches} detail={info.connects}>
          {info.local && <QuietLine size={13}>{found.length === 0 ? FirstRunQuestions.nothingFound : agentsFoundLine(found)}</QuietLine>}
          {place !== undefined && throughCloud(place) && (
            <div className="flex flex-col gap-2 py-2">
              <QuietLine size={13}>{FirstRunQuestions.cloudOptional}</QuietLine>
              <CloudSignIn parts={parts} />
            </div>
          )}
        </KitCard>
      )}
      <Button
        kind="primary"
        wide
        trailing={ArrowRight}
        onClick={() => {
          if (place !== undefined && answers.place === undefined) answer({ place });
          next();
        }}
      >
        {OnboardingLines.continue}
      </Button>
    </>
  );
}

/** Who Memnox is for, which only picks where Where should Memnox ask you suggests first. */
function WhoStep({ answers, answer, next }: { answers: Answers; answer: (change: Partial<Answers>) => void; next: () => void }) {
  const audience = answers.audience ?? 'me';
  const heading = stepHeading(0, '');
  return (
    <>
      <StepTitle counter={stepCounter(0)} title={heading.title} detail={heading.detail} />
      <KitCard icon={UserRound} title={FirstRunQuestions.placeCard}>
        <div role="radiogroup" aria-label={heading.title} className="flex flex-col">
          {AUDIENCES.map((each, index) => (
            <Fragment key={each.id}>
              {index > 0 && <KitDivider />}
              <AnswerRow icon={AUDIENCE_ICONS[each.id]} title={each.title} detail={each.detail} on={audience === each.id} pick={() => answer({ audience: each.id })} />
            </Fragment>
          ))}
        </div>
      </KitCard>
      <Button
        kind="primary"
        wide
        trailing={ArrowRight}
        onClick={() => {
          if (answers.audience === undefined) answer({ audience });
          next();
        }}
      >
        {OnboardingLines.continue}
      </Button>
    </>
  );
}

/** Where Memnox asks: this computer's key, always on, then the phone and Memnox Cloud, the suggested one first. */
function AskWhereStep({ parts, answers, next }: { parts: SettingsParts; answers: Answers; next: () => void }) {
  const { words, host, steps, pairing } = parts;
  useObserved(steps, pairing);
  const heading = stepHeading(3, words.keyTitle);
  const routes = askRoutes(words.keyTitle);
  return (
    <>
      <StepTitle counter={stepCounter(3)} title={heading.title} detail={heading.detail} />
      <KitCard icon={Smartphone} title={OnboardingLines.askMe}>
        {askOrder(answers.audience).map((id, index) => {
          const route = routes.find((each) => each.id === id);
          if (route === undefined) return null;
          return (
            <Fragment key={id}>
              {index > 0 && <KitDivider />}
              <KitRow
                tile={<IconTile icon={ASK_ICONS[id]} />}
                title={route.title}
                detail={route.detail}
                trailing={
                  id === 'here' ? (
                    <StatusMark state={steps.keyState} />
                  ) : id === 'phone' ? (
                    pairing.devices.length > 0 ? <StatusMark state={{ kind: 'done' }} /> : <Button onClick={() => host.openSettings('phones')}>{OnboardingLines.pair}</Button>
                  ) : (
                    <CloudSignIn parts={parts} />
                  )
                }
              />
            </Fragment>
          );
        })}
      </KitCard>
      <Button kind="primary" wide trailing={ArrowRight} onClick={next}>
        {OnboardingLines.continue}
      </Button>
    </>
  );
}

/** Sign in to Memnox Cloud from the first run, waiting on the console page it opens; cancelling changes nothing. */
function CloudSignIn({ parts }: { parts: SettingsParts }) {
  const { team } = parts;
  useObserved(team);
  useEffect(() => {
    void team.load();
  }, []);
  const step = team.step;
  if (step.kind === 'signed-in') return <StatusMark state={{ kind: 'done' }} />;
  if (step.kind === 'starting' || step.kind === 'showing-code') {
    return (
      <span className="flex items-center gap-2">
        {step.kind === 'showing-code' && <span className="font-mono text-callout text-ink">{step.code}</span>}
        <Button onClick={() => team.cancel()}>{OnboardingLines.cancelSignIn}</Button>
      </span>
    );
  }
  return (
    <span className="flex flex-col items-start gap-1">
      <Button icon={UserRound} onClick={() => void team.start()}>
        {OnboardingLines.signIn}
      </Button>
      {step.kind === 'failed' && <NeedsHint why={step.why} size={12} />}
    </span>
  );
}

/**
 * What Memnox can and cannot do, at the end, in the five plain levels: each agent's levels as the service states them,
 * the place the person named until its own connection reports, and a job with nobody behind it saying so.
 */
function CoverageCard({ parts, answers }: { parts: SettingsParts; answers: Answers }) {
  const { profiles, support } = parts;
  useObserved(profiles, support);
  const offers = support.supports('profiles') === true;
  useEffect(() => {
    if (offers) void profiles.refresh();
  }, [offers]);
  const agents = orderedProfiles(profiles.profiles ?? []).filter((each) => each.connections.length > 0);
  const place = answers.place;
  const elsewhere = place !== undefined && !placeInfo(place).local;
  return (
    <KitCard icon={ShieldCheck} title={FirstRunCoverage.title} detail={FirstRunCoverage.lead}>
      {agents.map((profile, index) => (
        <Fragment key={profile.id}>
          {index > 0 && <KitDivider />}
          <div className="flex flex-col gap-1.5 py-2.5">
            <span className="flex items-center gap-2">
              <BrandLogo agent={profile.connections[0]?.agentKind} name={profile.name} size={22} />
              <span className="text-callout font-semibold text-ink">{profile.name}</span>
            </span>
            {FirstRunCoverage.lines(profile.levels).map((line) => (
              <span key={line.level} className="flex items-start gap-2">
                <LevelPill level={line.level} />
                <span className="text-footnote text-ink-secondary">{line.things.join(', ')}</span>
              </span>
            ))}
          </div>
        </Fragment>
      ))}
      {elsewhere && place !== undefined && place !== 'none-yet' && <KitRow tile={<IconTile icon={Cloud} />} title={placeInfo(place).title} detail={FirstRunCoverage.place(place)} trailing={<LevelPill level="none" />} />}
      {agents.length === 0 && !elsewhere && <QuietLine size={13}>{FirstRunCoverage.noAgents}</QuietLine>}
      <div className="pt-2">
        <QuietLine size={12}>{FirstRunCoverage.cannot}</QuietLine>
      </div>
    </KitCard>
  );
}

/** Step 5: the recommended pack chosen already, the rest folded behind See other packs; Finish proposes the one chosen. */
function RulesStep({ parts, next }: { parts: SettingsParts; next: (proposed: string | undefined) => void }) {
  const { studio, words } = parts;
  useObserved(studio);
  const [picked, pick] = useState<string | undefined>(undefined);
  const [others, showOthers] = useState(false);
  const [failed, fail] = useState<string | undefined>(undefined);
  const [sending, setSending] = useState(false);
  useEffect(() => {
    void studio.readPacks();
  }, []);
  const packs = studio.packs;
  const starting = startingPacks(packs ?? []);
  const chosen = picked ?? starting.recommended?.id;
  const pack = packs?.find((each) => each.id === chosen);
  const finish = async () => {
    if (pack === undefined) return next(undefined);
    setSending(true);
    const outcome = await studio.importPack(pack.toml);
    setSending(false);
    if (outcome.kind === 'failed') return fail(outcome.why);
    next(outcome.kind === 'proposed' ? OnboardingLines.rulesWait : outcome.note);
  };
  const row = (each: NonNullable<typeof packs>[number], index: number, recommended: boolean) => (
    <Fragment key={each.id}>
      {index > 0 && <KitDivider />}
      <Pressable role="radio" aria-checked={chosen === each.id} disabled={sending} onClick={() => pick(each.id)} className="cursor-pointer text-left disabled:cursor-default">
        <KitRow
          tile={<IconTile icon={ListChecks} />}
          title={recommended ? OnboardingLines.recommendedPack(packTitle(each)) : packTitle(each)}
          detail={each.description}
          trailing={<span aria-hidden className={`size-4 rounded-full border-2 ${chosen === each.id ? 'border-primary bg-primary' : 'border-ink-edge'}`} />}
        />
      </Pressable>
    </Fragment>
  );
  const heading = stepHeading(4, words.keyTitle);
  return (
    <>
      <StepTitle counter={stepCounter(4)} title={heading.title} detail={heading.detail} />
      <KitCard icon={ListChecks} title={OnboardingLines.rulePacks} detail={OnboardingLines.rulePacksDetail}>
        {packs === undefined && <Spinner />}
        {packs !== undefined && packs.length === 0 && <QuietLine size={13}>{OnboardingLines.noPacks}</QuietLine>}
        {starting.recommended !== undefined && (
          <div role="radiogroup" aria-label={OnboardingLines.rulePacks} className="flex flex-col">
            {row(starting.recommended, 0, true)}
            {others && starting.others.map((each, index) => row(each, index + 1, false))}
          </div>
        )}
        {starting.others.length > 0 && (
          <div className="pt-2">
            <Button icon={others ? ChevronUp : ChevronDown} onClick={() => showOthers(!others)}>
              {others ? OnboardingLines.hideOthers : OnboardingLines.seeOthers}
            </Button>
          </div>
        )}
      </KitCard>
      {failed !== undefined && <NeedsHint why={failed} size={12} />}
      <Button kind="primary" wide trailing={ArrowRight} disabled={sending || packs === undefined} onClick={() => void finish()}>
        {sending ? OnboardingLines.proposing : OnboardingLines.finish}
      </Button>
    </>
  );
}

/** The end screen: one next action, then a short optional list, each row opening the Settings page that holds it. */
function EndScreen({ parts, proposed, answers, finish }: { parts: SettingsParts; proposed: string | undefined; answers: Answers; finish: () => void }) {
  const { words, host, preferences } = parts;
  usePreferences();
  const name = firstName(preferences.name);
  const open = (page: string) => {
    preferences.finishSetup();
    host.openSettings(page);
    host.close();
  };
  return (
    <>
      <StepTitle title={setTitle(name)} detail={GuideLines.ready(name, words.talkKeysSaid)} />
      {proposed !== undefined && <QuietLine size={13}>{proposed}</QuietLine>}
      <TryCard />
      <CoverageCard parts={parts} answers={answers} />
      <Button kind="primary" wide icon={Sparkles} onClick={finish}>
        {OnboardingLines.start}
      </Button>
      <KitCard icon={SettingsIcon} title={OnboardingLines.optionalSkip} detail={OnboardingLines.optionalDetail}>
        {endLinks(name).map((link, index) => (
          <Fragment key={link.id}>
            {index > 0 && <KitDivider />}
            <KitRow
              tile={<IconTile icon={END_ICONS[link.id]} />}
              title={link.title}
              detail={link.detail}
              trailing={<Button onClick={() => open(link.page)}>{OnboardingLines.open}</Button>}
            />
          </Fragment>
        ))}
      </KitCard>
    </>
  );
}

/** The one thing to try first: a prompt that produces a real ask, the same words on every surface (the contract's `tryPrompt`). */
function TryCard() {
  const [copied, setCopied] = useState(false);
  return (
    <KitCard icon={Sparkles} title={TRY_TITLE} detail={TRY_DETAIL}>
      <div className="flex items-center gap-3 py-2">
        <code className="flex-1 font-code text-footnote text-ink select-text">{TRY_PROMPT}</code>
        <Button
          icon={copied ? Check : undefined}
          onClick={() => {
            void navigator.clipboard?.writeText(TRY_PROMPT);
            setCopied(true);
          }}
        >
          {copied ? OnboardingLines.copied : OnboardingLines.copy}
        </Button>
      </div>
    </KitCard>
  );
}
