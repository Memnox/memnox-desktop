import {
  ArrowRight,
  ArrowUp,
  AudioLines,
  Building2,
  Check,
  ChevronDown,
  ChevronLeft,
  ChevronUp,
  Copy,
  Fingerprint,
  Hand,
  Keyboard,
  KeyRound,
  Layers,
  ListChecks,
  Lock,
  Mic,
  Monitor,
  Play,
  Power,
  QrCode as QrIcon,
  Quote,
  RotateCw,
  ScreenShare,
  Send,
  SkipForward,
  Smartphone,
  Sparkles,
  Speech,
  UserRoundSearch,
  Volume2,
  VolumeX,
  X,
  type LucideIcon,
} from 'lucide-react';
import { Fragment, useEffect, useRef, useState, type ReactNode } from 'react';
import { groupedDigits } from '../../core/domain/account-whole';
import { AgentCheckText } from '../../core/domain/agent-check-text';
import { GuideLines, ONBOARDING_STEPS, progressOf, setTitle, WELCOME_ROWS, type OnboardingStage, type OnboardingStep, type WelcomeRow } from '../../core/domain/onboarding';
import type { PermissionStep } from '../../core/domain/permission-steps';
import { firstName, voiceDetail, voiceStep } from '../../core/domain/setup-steps';
import type { StepState } from '../../core/domain/step-state';
import { BrandLogo, MEMNOX_MARK } from '../kit/logos';
import { CloudRow } from '../settings/pages/AccountPage';
import { Digits, IconTile, KitButton, Keycaps, MemnoxTile, NeedsHint, QuietLine, Spinner, StatusMark, useCopied } from '../settings/kit';
import { useLook, useObserved, usePreferences, type SettingsParts } from '../settings/parts';
import { PermissionGuide, QrCode } from '../settings/steps';

/** The icons of the welcome rows, the lucide stand ins for the Mac's symbols. */
const WELCOME_ICONS: Record<WelcomeRow['id'], LucideIcon> = {
  glance: Layers,
  answer: Hand,
  rule: ListChecks,
  tools: Send,
  'catch-up': AudioLines,
};

const PERMISSION_ICONS: Record<PermissionStep['id'], LucideIcon> = { hear: Mic, type: Keyboard, see: ScreenShare };

/**
 * The first run, as the Mac's `OnboardingWindow`: the wordmark and Get Started, the name asked for, then
 * three steps with a progress bar, a scrolling column beside a picture, and Back and Mute at the foot.
 * The veil the Mac lays over the whole screen is drawn here inside the window, dark over a blue glass.
 */
export function OnboardingApp({ parts, stage: firstStage = 'intro', step: firstStep = 0 }: { parts: SettingsParts; stage?: OnboardingStage; step?: OnboardingStep }) {
  useLook(parts.preferences);
  const [stage, setStage] = useState<OnboardingStage>(firstStage);
  const [step, setStep] = useState<OnboardingStep>(firstStep);
  const guide = useGuide(parts);

  useEffect(() => {
    if (stage === 'name') guide(GuideLines.name);
    if (stage === 'steps' && step === 0) guide(GuideLines.welcome(firstName(parts.preferences.name)));
    if (stage === 'steps' && step === 1) guide(GuideLines.setup);
    if (stage === 'steps' && step === 2) guide(GuideLines.ready(firstName(parts.preferences.name), parts.words.talkKeysSaid));
  }, [stage, step]);

  useEffect(() => {
    const keys = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && stage === 'steps' && step > 0) setStep((step - 1) as OnboardingStep);
    };
    window.addEventListener('keydown', keys);
    return () => window.removeEventListener('keydown', keys);
  }, [stage, step]);

  if (stage !== 'steps') {
    return <Veil parts={parts} stage={stage} next={() => setStage(stage === 'intro' ? 'name' : 'steps')} skip={() => setStage('steps')} />;
  }
  const finish = () => {
    parts.preferences.finishSetup();
    parts.host.close();
  };
  return (
    <div className="flex h-full flex-col bg-background text-foreground">
      <div className="flex flex-col gap-2 px-7 pt-[18px]">
        <div className="h-1 overflow-hidden rounded-full bg-ink-fill">
          <div className="h-full rounded-full bg-ink-primary transition-[width] duration-500 ease-out" style={{ width: `${progressOf(step) * 100}%` }} />
        </div>
        <div className="flex gap-4">
          {ONBOARDING_STEPS.map((name, index) => (
            <span key={name} className={`flex items-center gap-1 text-footnote ${index === step ? 'font-semibold text-ink-primary' : 'text-ink-tertiary'}`}>
              {index < step && <Check size={10} strokeWidth={3.4} />}
              {name}
            </span>
          ))}
        </div>
      </div>
      <div className="flex min-h-0 flex-1 justify-center gap-12 px-14">
        <ScrollColumn key={step}>
          {step === 0 && <WelcomeStep parts={parts} next={() => setStep(1)} />}
          {step === 1 && <SetupStepPage parts={parts} next={() => setStep(2)} />}
          {step === 2 && <TryStep parts={parts} finish={finish} />}
        </ScrollColumn>
        <Art />
      </div>
      <footer className="flex h-11 shrink-0 items-center gap-3 px-7 pb-3">
        {step > 0 && (
          <KitButton icon={ChevronLeft} onClick={() => setStep((step - 1) as OnboardingStep)}>
            Back
          </KitButton>
        )}
        <span className="flex-1" />
        <MuteButton parts={parts} />
        <span className="text-footnote text-ink-tertiary">You can change all of this later in Settings.</span>
      </footer>
    </div>
  );
}

/** Says a guide line in Memnox's voice unless the person muted the first run. */
function useGuide(parts: SettingsParts): (line: string) => void {
  return (line: string) => {
    if (parts.preferences.guideMuted) return;
    void parts.host.voices.say(line).catch(() => undefined);
  };
}

function MuteButton({ parts }: { parts: SettingsParts }) {
  usePreferences();
  const muted = parts.preferences.guideMuted;
  return (
    <KitButton icon={muted ? VolumeX : Volume2} onClick={() => (parts.preferences.guideMuted = !muted)}>
      {muted ? 'Unmute' : 'Mute'}
    </KitButton>
  );
}

/** The intro and the name, on the dark veil, with Skip intro in the corner. */
function Veil({ parts, stage, next, skip }: { parts: SettingsParts; stage: OnboardingStage; next: () => void; skip: () => void }) {
  const [name, setName] = useState(parts.preferences.name);
  const send = () => {
    if (name.trim() === '') return;
    parts.preferences.name = name;
    next();
  };
  return (
    <div
      className="relative flex h-full flex-col items-center justify-center text-white"
      style={{ background: 'linear-gradient(rgb(0 0 0 / 0.58), rgb(0 0 0 / 0.58)), radial-gradient(120% 90% at 50% 20%, #2b4f7f 0%, #10213a 55%, #05070c 100%)' }}
    >
      {stage === 'intro' ? (
        <div key="intro" className="flex animate-[card-in_600ms_cubic-bezier(.2,.8,.2,1)_both] flex-col items-center gap-11">
          <div className="flex items-center gap-4" style={{ filter: 'drop-shadow(0 0 6px rgb(255 255 255 / .6)) drop-shadow(0 0 28px rgb(255 255 255 / .55))' }}>
            <img src={MEMNOX_MARK} alt="" className="h-[72px] w-auto" draggable={false} />
            <span className="font-display text-[72px] leading-none font-semibold tracking-tight">Memnox</span>
          </div>
          <KitButton kind="glass" trailing={ArrowRight} onClick={next} autoFocus>
            Get Started
          </KitButton>
        </div>
      ) : (
        <div key="name" className="flex animate-[pill-in_600ms_cubic-bezier(.2,.8,.2,1)_both] flex-col items-center gap-10">
          <div className="flex flex-col items-center gap-3 text-center font-display text-[30px] font-medium">
            <p>Welcome to Memnox. I&rsquo;m the voice over your agents.</p>
            <p>So, what should I call you?</p>
          </div>
          <div className="flex h-[52px] w-[420px] items-center rounded-full border border-white/[0.14] bg-white/[0.14] pr-2 pl-5">
            <input
              className="min-w-0 flex-1 bg-transparent text-[17px] text-white outline-none placeholder:text-white/[0.62]"
              placeholder="Your name"
              value={name}
              autoFocus
              onChange={(event) => setName(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === 'Enter') send();
              }}
              aria-label="Your name"
            />
            <button
              type="button"
              className={`grid size-[34px] cursor-pointer place-items-center rounded-full disabled:cursor-default ${name.trim() === '' ? 'bg-white/[0.08] text-white' : 'bg-white text-black'}`}
              disabled={name.trim() === ''}
              onClick={send}
              aria-label="Send"
            >
              <ArrowUp size={14} strokeWidth={3} />
            </button>
          </div>
        </div>
      )}
      <button type="button" className="absolute right-7 bottom-7 flex cursor-pointer items-center gap-1.5 text-callout font-medium text-white/[0.62] hover:text-white" onClick={skip}>
        <SkipForward size={14} /> Skip intro
      </button>
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
          <KitButton icon={ChevronDown} onClick={() => scroller.current?.scrollTo({ top: scroller.current.scrollHeight, behavior: 'smooth' })}>
            More below
          </KitButton>
        </span>
      )}
    </div>
  );
}

/** The picture beside the steps: a screen on a sky with the island hanging from its top. */
function Art() {
  return (
    <div className="pointer-events-none flex min-w-0 flex-1 py-9" aria-hidden>
      <div className="relative flex flex-1 items-end justify-center overflow-hidden rounded-3xl border border-ink-rim p-6" style={{ background: 'linear-gradient(#86B3C9, #4F7BB3)' }}>
        <div className="relative aspect-[828/634] w-full max-w-[520px] rounded-t-[22px] bg-[#0C0C0D] px-[1.7%] pt-[1.7%] shadow-[0_14px_24px_rgba(0,0,0,.35)] [mask-image:linear-gradient(black_82%,transparent)]">
          <div className="relative h-full overflow-hidden rounded-t-[14px]" style={{ background: 'linear-gradient(160deg, #1E86EE, #0a3d7a)' }}>
            <div className="flex h-[5%] items-center justify-between bg-black/[0.18] px-3 text-[9px] font-medium text-white">
              <span className="font-semibold">Terminal</span>
              <span>9:41</span>
            </div>
            <div className="absolute top-0 left-1/2 flex h-[6%] w-[30%] -translate-x-1/2 items-center gap-1.5 rounded-b-[10px] bg-black px-2">
              <span className="size-2 rounded-full bg-[#1E86EE] shadow-[0_0_6px_#1E86EE]" />
              <span className="h-1 flex-1 rounded-full bg-white/20" />
            </div>
            <div className="absolute top-[12%] left-[8%] flex w-[60%] flex-col gap-1.5 rounded-lg bg-black/40 p-3">
              {[80, 60, 72, 40].map((width) => (
                <span key={width} className="h-1.5 rounded-full bg-white/30" style={{ width: `${width}%` }} />
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

/** `StepTitle`: 30 semibold over its line 15 at ink 62%. */
function StepTitle({ title, detail }: { title: string; detail: string }) {
  return (
    <header className="flex flex-col gap-2">
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

/** Step 1: what Memnox does, five rows each said aloud on a press, and how it thinks. */
function WelcomeStep({ parts, next }: { parts: SettingsParts; next: () => void }) {
  const [playing, setPlaying] = useState<WelcomeRow['id']>();
  const guide = useGuide(parts);
  return (
    <>
      <StepTitle title="Welcome to Memnox" detail="Let AI agents work autonomously. Keep their actions within your boundaries." />
      <KitCard>
        {WELCOME_ROWS.map((row, index) => {
          const Icon = WELCOME_ICONS[row.id];
          const on = playing === row.id;
          return (
            <Fragment key={row.id}>
              {index > 0 && <KitDivider />}
              <button
                type="button"
                className={`cursor-pointer text-left transition-opacity duration-300 ${playing !== undefined && !on ? 'opacity-55' : ''}`}
                title="Hear this"
                onClick={() => {
                  setPlaying(on ? undefined : row.id);
                  if (!on) guide(`${row.title}. ${row.detail}`);
                }}
              >
                <KitRow tile={<IconTile icon={Icon} />} title={row.title} detail={row.detail} trailing={<Play size={12} fill={on ? 'currentColor' : 'none'} className={on ? 'text-primary' : 'text-ink-tertiary'} />} />
              </button>
            </Fragment>
          );
        })}
      </KitCard>
      <KitCard
        icon={KeyRound}
        title="Works through your own agent"
        detail="Memnox has no model of its own. It answers through an agent you already use, such as Claude Code, Codex, Cursor or Hermes, signed in with that agent's own account. No API key to bring."
      >
        {null}
      </KitCard>
      <KitButton kind="primary" wide trailing={ArrowRight} onClick={next}>
        Set up this computer
      </KitButton>
    </>
  );
}

/** Step 2: the permissions this system needs, Memnox installing itself and its voice, and who answers. */
function SetupStepPage({ parts, next }: { parts: SettingsParts; next: () => void }) {
  const { steps, words, host } = parts;
  useObserved(steps);
  useEffect(() => {
    void steps.refresh().then(() => steps.recheckOnce());
    if (steps.voiceInstall.kind === 'idle') void steps.installVoice();
  }, []);
  const service = steps.service;
  const key = steps.keyState;
  const install = steps.voiceInstall;
  const starts = steps.startsAtSignIn === true;
  return (
    <>
      <StepTitle title="Set up this computer" detail="A few permissions, asked once, and Memnox installs itself and its voice under your agents." />
      <KitCard icon={Lock} title="Permissions" detail="Used only when you talk or approve.">
        {steps.permissions.map((step, index) => {
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
                      <span className="flex items-center gap-1.5 text-footnote font-medium text-ink-secondary">
                        <Spinner size={12} /> Waiting
                      </span>
                    ) : (
                      <KitButton icon={RotateCw} onClick={() => void steps.readPermissions()}>
                        Check again
                      </KitButton>
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
        <KitDivider />
        <KitRow
          tile={<IconTile icon={Fingerprint} />}
          title={words.approveTitle}
          detail="Your approval signs what agents ask. The key never leaves this computer."
          hint={key.kind === 'needs' ? key.why : undefined}
          trailing={
            <DoneOr state={key}>
              <KitButton icon={RotateCw} onClick={() => void steps.checkKey()}>
                Check again
              </KitButton>
            </DoneOr>
          }
        />
      </KitCard>
      <KitCard icon={Monitor} title="Memnox on this computer" detail="Installed under your agents and kept up to date for you.">
        <KitRow
          tile={<MemnoxTile />}
          title="Memnox service"
          detail={service.detail}
          hint={service.state.kind === 'needs' ? service.state.why : undefined}
          trailing={
            <DoneOr state={service.state}>
              {parts.setup.state.doing !== undefined ? (
                <Spinner />
              ) : (
                <KitButton icon={RotateCw} onClick={() => void steps.checkService()}>
                  Check again
                </KitButton>
              )}
            </DoneOr>
          }
        />
        <KitDivider />
        <KitRow
          tile={<IconTile icon={AudioLines} />}
          title="Voice"
          detail={install.kind === 'installing' && install.percent !== undefined ? `${voiceDetail(install)} ${install.percent}%.` : voiceDetail(install)}
          trailing={
            <DoneOr state={voiceStep(install)}>
              {install.kind === 'failed' ? <KitButton onClick={() => void steps.installVoice()}>Try again</KitButton> : <Spinner />}
            </DoneOr>
          }
        />
        <KitDivider />
        <KitRow
          tile={<IconTile icon={Power} />}
          title="Start when you sign in"
          detail="So a call that waits on you is never missed because Memnox was closed."
          trailing={
            starts ? (
              <StatusMark state={{ kind: 'done' }} />
            ) : (
              <KitButton onClick={() => void steps.setStartsAtSignIn(true)}>Turn on</KitButton>
            )
          }
        />
      </KitCard>
      <KitCard icon={Speech} title="Who answers when you talk" detail={steps.agentsDetail}>
        <AgentChecks parts={parts} />
      </KitCard>
      <KitButton kind="primary" wide trailing={ArrowRight} onClick={next}>
        Continue
      </KitButton>
    </>
  );
}

/** `AgentChecks`: the agents that can answer, then the ones that cannot folded into one row with why. */
function AgentChecks({ parts }: { parts: SettingsParts }) {
  const { steps } = parts;
  const [open, setOpen] = useState(false);
  const installed = steps.agents.filter((agent) => agent.installed);
  const ready = installed.filter((agent) => !AgentCheckText.notReady(agent));
  const stuck = installed.filter((agent) => AgentCheckText.notReady(agent));
  const chosen = installed.find((agent) => agent.chosen);
  if (installed.length === 0) {
    const state = steps.agentsState;
    return (
      <KitRow
        tile={<IconTile icon={UserRoundSearch} />}
        title={steps.checkingAgents ? 'Your agents' : 'No agent found yet'}
        detail={state.kind === 'needs' ? state.why : 'Looking for the agents on this computer.'}
        trailing={<KitButton onClick={() => void steps.loadAgents(true)}>Check again</KitButton>}
      />
    );
  }
  return (
    <>
      {ready.map((agent, index) => (
        <Fragment key={agent.kind}>
          {index > 0 && <KitDivider />}
          <KitRow
            tile={<BrandLogo agent={agent.kind} name={agent.label} size={26} />}
            title={agent.label}
            detail={AgentCheckText.status(agent, steps.checkingAgents)}
            trailing={
              agent.chosen && agent.works === true ? (
                <StatusMark state={{ kind: 'done' }} />
              ) : agent.works === true ? (
                <KitButton icon={Check} onClick={() => void steps.useAgent(agent.kind)}>
                  Use
                </KitButton>
              ) : steps.checkingAgents ? (
                <Spinner />
              ) : undefined
            }
          />
        </Fragment>
      ))}
      {stuck.length > 0 && (
        <>
          {ready.length > 0 && <KitDivider />}
          <KitRow
            tile={
              <span className="flex w-[26px] shrink-0">
                {stuck.slice(0, 3).map((agent, index) => (
                  <span key={agent.kind} className="rounded-[7px] ring-2 ring-card" style={{ marginLeft: index === 0 ? 0 : -8 }}>
                    <BrandLogo agent={agent.kind} name={agent.label} size={22} />
                  </span>
                ))}
              </span>
            }
            title={`${AgentCheckText.names(stuck.map((agent) => agent.label))} can’t answer yet`}
            detail={chosen !== undefined ? `Nothing to do now, since ${chosen.label} already answers for you.` : 'Fix one in its own account, then check again.'}
            trailing={
              <KitButton icon={open ? ChevronUp : ChevronDown} onClick={() => setOpen(!open)}>
                {open ? 'Hide' : 'Show why'}
              </KitButton>
            }
          />
          {open && (
            <div className="flex flex-col gap-3 pb-2.5 pl-[38px]">
              {stuck.map((agent) => {
                const reply = AgentCheckText.reply(agent);
                return (
                  <div key={agent.kind} className="flex flex-col gap-1.5">
                    <div className="flex items-center gap-2">
                      <span className="text-callout font-semibold text-ink">{agent.label}</span>
                      <span className="flex items-center gap-1 rounded-full bg-warm/[0.14] px-2 py-1 text-footnote font-medium text-warm">
                        <span className="size-1.5 rounded-full bg-warm" /> Not ready
                      </span>
                    </div>
                    <span className="text-footnote text-ink-secondary">{AgentCheckText.status(agent, false)}</span>
                    {reply !== undefined && (
                      <span className="flex gap-1.5 rounded-lg bg-field p-2">
                        <Quote size={12} className="shrink-0 text-ink-tertiary" />
                        <span className="line-clamp-3 font-mono text-footnote text-ink-secondary">{reply}</span>
                      </span>
                    )}
                  </div>
                );
              })}
              <div className="flex items-center gap-2">
                <span className="flex-1 text-footnote text-ink-secondary">Fix it in the agent&rsquo;s own account, then check again.</span>
                <KitButton onClick={() => void steps.loadAgents(true)}>Check again</KitButton>
              </div>
            </div>
          )}
        </>
      )}
    </>
  );
}

/** Step 3: the two keys to try, then the workspace and the phone, both optional, and Start using Memnox. */
function TryStep({ parts, finish }: { parts: SettingsParts; finish: () => void }) {
  const { words, host, preferences } = parts;
  usePreferences();
  return (
    <>
      <StepTitle
        title={setTitle(firstName(preferences.name))}
        detail="Hand an agent the task and close your laptop. Everything inside your boundary runs on its own, and the one thing outside it finds you on your phone."
      />
      <KitCard icon={Keyboard} title="Two keys to try" detail="Memnox answers in the island.">
        <KitRow
          tile={<IconTile icon={Mic} />}
          title="Ask out loud"
          detail="Press, talk, and Memnox listens until you stop."
          trailing={
            <>
              <Keycaps keys={words.talkKeys} gap={2} />
              <KitButton icon={Play} onClick={() => host.talk()}>
                Try it
              </KitButton>
            </>
          }
        />
        <KitDivider />
        <KitRow
          tile={<IconTile icon={ListChecks} />}
          title="Say a rule"
          detail="Hold, and say never deploy on Fridays."
          trailing={
            <>
              <Keycaps keys={['Ctrl', 'Alt']} gap={2} />
              <KitButton icon={Play} onClick={() => host.talk('rule')}>
                Try it
              </KitButton>
            </>
          }
        />
      </KitCard>
      <KitCard icon={Building2} title="Optional" detail="Your workspace and your iPhone. Both wait in Settings.">
        <div className="-mx-4">
          <CloudRow parts={parts} compact />
        </div>
        <KitDivider />
        <PhoneRow parts={parts} />
      </KitCard>
      <KitButton kind="primary" wide icon={Sparkles} onClick={finish}>
        Start using Memnox
      </KitButton>
    </>
  );
}

/** Pair your iPhone, in the first run's own shape: a 132 QR, then the digits, then the phone paired. */
function PhoneRow({ parts }: { parts: SettingsParts }) {
  const { pairing, host } = parts;
  useObserved(pairing);
  const [copied, copy] = useCopied(host.copy);
  const step = pairing.step;
  if (step.kind === 'paired') {
    return <KitRow tile={<IconTile icon={Smartphone} />} title={step.name} detail="Paired. Questions reach it with Face ID." trailing={<StatusMark state={{ kind: 'done' }} />} />;
  }
  return (
    <>
      <KitRow
        tile={<IconTile icon={QrIcon} />}
        title="Pair your iPhone"
        detail={step.kind === 'opening' ? 'Opening a pairing' : 'Scan a code with the Memnox app.'}
        hint={step.kind === 'failed' ? step.why : undefined}
        trailing={
          step.kind === 'idle' || step.kind === 'failed' ? (
            <KitButton icon={QrIcon} onClick={() => void pairing.pair()}>
              Pair
            </KitButton>
          ) : step.kind === 'opening' ? (
            <Spinner />
          ) : undefined
        }
      />
      {step.kind === 'showing' && (
        <div className="flex items-center gap-4 pb-2.5 pl-[38px]">
          <QrCode text={step.qr} size={132} quiet={8} radius={7} />
          <div className="flex flex-col items-start gap-2">
            <QuietLine size={13}>Scan this with the Memnox app on your iPhone.</QuietLine>
            <div className="flex gap-2">
              <KitButton icon={copied ? Check : Copy} onClick={() => copy(step.qr)}>
                {copied ? 'Copied' : 'Copy link'}
              </KitButton>
              <KitButton icon={X} onClick={() => void pairing.decline()}>
                Cancel
              </KitButton>
            </div>
          </div>
        </div>
      )}
      {(step.kind === 'checking' || step.kind === 'approving') && (
        <div className="flex flex-col items-start gap-1.5 pb-2.5 pl-[38px]">
          <span className="text-callout font-semibold text-foreground">{step.phone.name}</span>
          <Digits code={groupedDigits(step.phone.code)} size={24} />
          <QuietLine size={12}>Approve if your iPhone shows the same digits.</QuietLine>
          <div className="flex gap-2 pt-1">
            <KitButton kind="primary" icon={Check} disabled={step.kind === 'approving'} onClick={() => void pairing.approve()}>
              Approve
            </KitButton>
            <KitButton icon={X} disabled={step.kind === 'approving'} onClick={() => void pairing.decline()}>
              Decline
            </KitButton>
          </div>
        </div>
      )}
    </>
  );
}
