import {
  ArrowRight,
  AudioLines,
  Building2,
  Check,
  ChevronDown,
  ChevronLeft,
  ChevronUp,
  Fingerprint,
  Keyboard,
  ListChecks,
  Lock,
  Mic,
  Monitor,
  RotateCw,
  ScreenShare,
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
  endLinks,
  type EndLink,
  GuideLines,
  GuideMemory,
  ONBOARDING_STEPS,
  permissionsAsked,
  permissionsLine,
  progressOf,
  rowSpoken,
  setTitle,
  startingPacks,
  stepCounter,
  stepHeading,
  type OnboardingStage,
  type OnboardingStep,
  type WelcomeRow,
} from '../../core/domain/onboarding';
import type { PermissionStep } from '../../core/domain/permission-steps';
import { agentsFoundLine, firstName, packTitle } from '../../core/domain/setup-steps';
import type { StepState } from '../../core/domain/step-state';
import { BrandLogo, MEMNOX_MARK } from '../kit/logos';
import { IconTile, MemnoxTile, NeedsHint, QuietLine, StatusMark } from '../settings/kit';
import { useLook, useObserved, usePreferences, type SettingsParts } from '../settings/parts';
import { PermissionGuide } from '../settings/steps';
import { IslandDemo, useDemoTour } from './IslandDemo';
import { Button, Pressable, Spinner } from '../kit';
import { OnboardingLines } from '../../core/domain/onboarding-lines';

const PERMISSION_ICONS: Record<PermissionStep['id'], LucideIcon> = { hear: Mic, type: Keyboard, see: ScreenShare };
const END_ICONS: Record<EndLink['id'], LucideIcon> = { name: UserRound, voice: AudioLines, workspace: Building2, phone: Smartphone };

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
  const guide = useGuide(parts);
  // The real island plays each part beside the steps, round and round; a row pressed plays its part at once.
  // A preview can start on one part with ?part=, so each part can be looked at.
  const [part] = useDemoTour((new URLSearchParams(location.search).get('part') ?? undefined) as WelcomeRow['id'] | undefined);
  // The part the island moved on to is said once, and only while the first step is on screen, as the Mac's `follow`.
  useEffect(() => {
    if (stage === 'steps' && step === 0 && guideMemory.first(`part-${part}`)) guide(rowSpoken(part, parts.host.platform), false);
  }, [part, stage, step]);

  // Each stage is introduced once in a first run, as the Mac's `firstVisit`, so going Back stays quiet.
  useEffect(() => {
    const at = stage === 'steps' ? `step-${step}` : stage;
    if (!guideMemory.first(at)) return;
    if (stage === 'steps' && step === 0) {
      guide(GuideLines.welcome(firstName(parts.preferences.name)));
      guide(GuideLines.setup(parts.host.platform), false);
    }
    if (stage === 'steps' && step === 1) guide(GuideLines.permissions);
    if (stage === 'steps' && step === 2) guide(GuideLines.boundaries(parts.host.platform));
    if (stage === 'done') guide(GuideLines.done);
  }, [stage, step]);

  // The opening lies over the whole screen, as the Mac's veil; the steps take the ordinary window.
  const veiled = stage === 'intro';
  useEffect(() => parts.host.onboardingVeil?.(veiled), [veiled]);

  useEffect(() => {
    const keys = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      if (stage === 'done') setStage('steps');
      else if (stage === 'steps' && step > 0) setStep((step - 1) as OnboardingStep);
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
  const back = () => (done ? setStage('steps') : setStep((step - 1) as OnboardingStep));
  return (
    <div className="flex h-full flex-col bg-background text-foreground">
      <div className="flex flex-col gap-2 px-7 pt-[18px]">
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
          {done && <EndScreen parts={parts} proposed={proposed} finish={finish} />}
          {!done && step === 0 && <ConnectStep parts={parts} next={() => setStep(1)} />}
          {!done && step === 1 && <PermissionsStep parts={parts} next={() => setStep(2)} />}
          {!done && step === 2 && (
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
    <div
      className="relative flex h-full flex-col items-center justify-center text-white"
      style={{ background: 'linear-gradient(rgb(0 0 0 / 0.58), rgb(0 0 0 / 0.58)), radial-gradient(120% 90% at 50% 20%, #2b4f7f 0%, #10213a 55%, #05070c 100%)' }}
    >
      <div className="flex animate-[card-in_600ms_cubic-bezier(.2,.8,.2,1)_both] flex-col items-center gap-11">
        <div className="flex items-center gap-4" style={{ filter: 'drop-shadow(0 0 6px rgb(255 255 255 / .6)) drop-shadow(0 0 28px rgb(255 255 255 / .55))' }}>
          <img src={MEMNOX_MARK} alt="" className="h-[72px] w-auto" draggable={false} />
          <span className="font-display text-[72px] leading-none font-semibold tracking-tight">{OnboardingLines.brand}</span>
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
    <div className="relative w-[458px] shrink-0">
      <div
        ref={scroller}
        onScroll={measure}
        className="h-full animate-[satellite-right_500ms_cubic-bezier(.2,.8,.2,1)_both] overflow-y-auto pr-[18px]"
        style={{ maskImage: more ? 'linear-gradient(black calc(100% - 36px), transparent)' : undefined }}
      >
        <div className="flex flex-col gap-5 py-9">{children}</div>
      </div>
      {more && (
        <span className="absolute bottom-2 left-1/2 -translate-x-1/2 shadow-[0_4px_10px_rgba(0,0,0,.25)] [border-radius:999px]">
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
      <h1 className="font-display text-[30px] leading-tight font-semibold text-ink">{title}</h1>
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
  return <div className="ml-[38px] h-px bg-ink-faint-fill" />;
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
    // The next step's grants are read now, so they are settled by the time it shows.
    void steps.readPermissions();
    // The voice is optional, but it is fetched now so it has arrived by the time anybody asks for it.
    if (steps.voiceInstall.kind === 'idle') void steps.installVoice();
  }, []);
  const service = steps.service;
  const key = steps.keyState;
  const found = agents.agents;
  // Before the agents method answers, the agents the voice found stand in, so a fresh computer still shows its agents.
  const fallback = steps.agents.filter((agent) => agent.installed);
  const heading = stepHeading(0, words.keyTitle);
  return (
    <>
      <StepTitle counter={stepCounter(0)} title={heading.title} detail={heading.detail} />
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
      </KitCard>
      <Button kind="primary" wide trailing={ArrowRight} onClick={next}>
        {OnboardingLines.continue}
      </Button>
    </>
  );
}

/** Step 2: only the grants this system asks the person for, each with its one button; installs need nobody. */
function PermissionsStep({ parts, next }: { parts: SettingsParts; next: () => void }) {
  const { steps, words, host } = parts;
  useObserved(steps);
  const guide = useGuide(parts);
  useEffect(() => {
    void steps.readPermissions();
  }, []);
  const asked = permissionsAsked(steps.permissions);
  // A grant that waits on the person is said once, with what to do, as the Mac's guide follows its typing and seeing.
  const waitingOn = asked.filter((step) => step.state.kind === 'needs').map((step) => step.id);
  useEffect(() => {
    for (const step of asked) {
      if (step.state.kind !== 'needs' || !guideMemory.first(`needs-${step.id}`)) continue;
      if (step.id === 'hear') guide(GuideLines.microphone(host.platform), false);
      if (step.id === 'type') guide(GuideLines.typing, false);
      if (step.id === 'see') guide(GuideLines.seeing(step.guide.some((line) => line.includes('portal')) ? 'portal' : 'accessibility'), false);
    }
  }, [waitingOn.join()]);
  const heading = stepHeading(1, words.keyTitle);
  return (
    <>
      <StepTitle counter={stepCounter(1)} title={heading.title} detail={heading.detail} />
      <KitCard icon={Lock} title={OnboardingLines.asksFor} detail={permissionsLine(asked)}>
        {asked.map((step, index) => {
          const pane = step.pane;
          return (
            <Fragment key={step.id}>
              {index > 0 && <KitDivider />}
              <KitRow
                tile={<IconTile icon={PERMISSION_ICONS[step.id]} />}
                title={step.title}
                detail={step.onboardingDetail}
                trailing={
                  <DoneOr state={step.state}>
                    {step.state.kind === 'waiting' ? (
                      <Spinner size={12} />
                    ) : pane !== undefined && step.switchName !== undefined ? (
                      <Button icon={SettingsIcon} onClick={() => void host.openPrivacy(pane).then(() => steps.readPermissions())}>
                        {OnboardingLines.allow}
                      </Button>
                    ) : (
                      <Button icon={RotateCw} onClick={() => void steps.readPermissions()}>
                        {OnboardingLines.checkAgain}
                      </Button>
                    )}
                  </DoneOr>
                }
              />
              {step.state.kind === 'needs' && step.guide.length > 0 && (
                <div className="pb-2.5 pl-[38px]">
                  <PermissionGuide
                    steps={step.guide}
                    pane={pane === 'microphone' ? 'Microphone' : undefined}
                    switchName={step.switchName}
                    settingsApp={words.settingsApp}
                    open={pane === undefined ? undefined : () => void host.openPrivacy(pane)}
                  />
                </div>
              )}
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

/** Step 3: the recommended pack chosen already, the rest folded behind See other packs; Finish proposes the one chosen. */
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
  const heading = stepHeading(2, words.keyTitle);
  return (
    <>
      <StepTitle counter={stepCounter(2)} title={heading.title} detail={heading.detail} />
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
function EndScreen({ parts, proposed, finish }: { parts: SettingsParts; proposed: string | undefined; finish: () => void }) {
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
      <Button kind="primary" wide icon={Sparkles} onClick={finish}>
        {OnboardingLines.start}
      </Button>
      <KitCard icon={SettingsIcon} title={OnboardingLines.optional} detail={OnboardingLines.optionalDetail}>
        {endLinks(name).map((link, index) => (
          <Fragment key={link.id}>
            {index > 0 && <KitDivider />}
            <KitRow tile={<IconTile icon={END_ICONS[link.id]} />} title={link.title} detail={link.detail} trailing={<Button onClick={() => open(link.page)}>{OnboardingLines.open}</Button>} />
          </Fragment>
        ))}
      </KitCard>
    </>
  );
}
