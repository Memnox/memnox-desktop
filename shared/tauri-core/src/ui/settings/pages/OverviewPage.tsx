import type { HomeView } from '@memnox/core/wire';
import { AudioLines, ChevronRight, CircleAlert, CircleArrowRight, CircleCheck, Laptop, UserRoundCheck } from 'lucide-react';
import { useEffect } from 'react';
import { FIRST_RUN } from '../../../core/application/preferences';
import { HomeLines } from '../../../core/domain/home-lines';
import { pageInfo, type SettingsPage } from '../../../core/domain/settings-pages';
import { firstName, greeting, openStep, overviewSteps, readyCount } from '../../../core/domain/setup-steps';
import { BrandLogo } from '../../kit/logos';
import { HOVER_LIGHT, Keycaps, KitButton, SettingsCard, SettingsDivider, SettingsRow, SettingsSection, StatusMark } from '../kit';
import { useObserved, usePreferences, type SettingsParts } from '../parts';

/**
 * The window's first page, as the Mac's `OverviewPage`: a greeting and Talk to Memnox, then the home's
 * blocks once setup is finished, and the setup checklist, which comes first until it is.
 */
export function OverviewPage({ parts, go }: { parts: SettingsParts; go: (page: SettingsPage) => void }) {
  const { preferences, steps, home, account, words, host } = parts;
  useObserved(steps, home, account);
  usePreferences();
  useEffect(() => {
    void steps.refresh();
    void home.refresh();
    void account.refresh();
  }, []);
  const finished = preferences.setupDone;
  const name = preferences.name;
  const blocks = home.home === undefined && home.unavailable ? <OverviewNumbers parts={parts} /> : home.home !== undefined ? <HomeBlocks parts={parts} view={home.home} /> : null;
  return (
    <>
      <header className="flex flex-col gap-1">
        <h1 className="text-title font-bold text-foreground">{greeting(name)}</h1>
        <p className="text-footnote text-muted">What waits on you, what your agents are doing, and what could run on its own.</p>
      </header>
      <div>
        <KitButton icon={AudioLines} onClick={() => host.talk()} title={`Or press ${words.talkKeysSaid} from anywhere`}>
          Talk to Memnox
          <Keycaps keys={words.talkKeys} />
        </KitButton>
      </div>
      {finished && blocks}
      {!finished && preferences.firstRun === '' ? (
        <FirstRunChoice
          signedIn={account.isSignedIn}
          chose={(path) => {
            preferences.firstRun = path;
            if (path === FIRST_RUN.account) {
              if (!account.isSignedIn) void account.start();
              go('account');
            }
          }}
        />
      ) : (
        <SetupProgressCard parts={parts} go={go} />
      )}
      {!finished && blocks}
    </>
  );

  function FirstRunChoice({ signedIn, chose }: { signedIn: boolean; chose: (path: string) => void }) {
    return (
      <SettingsSection title="Start here">
        <SettingsCard>
          <SettingsRow icon={Laptop} title="Set up this computer" caption={`Your own agents, the voice, and ${words.keyTitle} for what they ask.`}>
            <KitButton kind="primary" onClick={() => chose(FIRST_RUN.thisComputer)}>
              Set up
            </KitButton>
          </SettingsRow>
          <SettingsDivider />
          <SettingsRow
            icon={UserRoundCheck}
            title="Sign in"
            caption={
              signedIn
                ? 'Signed in. What your workspace routes to you comes to the island.'
                : 'Answer what your workspace routes to you, from the island, before setting up anything else.'
            }
          >
            <KitButton onClick={() => chose(FIRST_RUN.account)}>{signedIn ? 'Open Account' : 'Sign in'}</KitButton>
          </SettingsRow>
        </SettingsCard>
      </SettingsSection>
    );
  }
}

/** "Do this next": the first open step with its button, every step as a row that opens its page, and Finish. */
function SetupProgressCard({ parts, go }: { parts: SettingsParts; go: (page: SettingsPage) => void }) {
  const { preferences, steps: model, host, words } = parts;
  const steps = overviewSteps(model.setupFacts(preferences.name));
  const open = openStep(steps);
  const ready = readyCount(steps);
  const named = preferences.name.trim() !== '';
  const finish = () => {
    preferences.finishSetup();
    const first = firstName(preferences.name);
    void host.voices.say(`Hi ${first ?? 'there'}, I am Memnox. Press ${words.talkKeysSaid} whenever you want me.`).catch(() => undefined);
  };
  return (
    <SettingsSection
      title={open === undefined ? 'Set up' : 'Do this next'}
      trailing={
        <span className="tabular text-footnote text-muted">
          {ready} of {steps.length}
        </span>
      }
    >
      <SettingsCard>
        {open !== undefined ? (
          <SettingsRow icon={CircleArrowRight} title={open.title} caption={open.hint}>
            <KitButton kind="primary" onClick={() => go(open.page)}>
              Go to {pageInfo(open.page).title}
            </KitButton>
          </SettingsRow>
        ) : (
          <SettingsRow icon={CircleCheck} tint="var(--mx-success)" title="Everything is ready" caption={`Press ${words.talkKeysSaid} from anywhere and ask about your agents.`} />
        )}
        <SettingsDivider full />
        <div className="flex flex-col">
          {steps.map((step) => (
            <button
              key={step.title}
              type="button"
              className={`${HOVER_LIGHT} flex h-8 cursor-pointer items-center gap-2 text-left`}
              onClick={() => go(step.page)}
              title={`Open ${pageInfo(step.page).title}`}
              aria-label={`${step.title}, ${step.state.kind === 'done' ? 'done' : 'not done yet'}`}
            >
              <StatusMark state={step.state} />
              <span className={`flex-1 truncate text-body ${step.state.kind === 'done' ? 'text-muted' : 'text-foreground'}`}>{step.title}</span>
              <span className="text-footnote text-faint">{pageInfo(step.page).title}</span>
              <ChevronRight size={12} strokeWidth={2.6} className="text-faint" />
            </button>
          ))}
        </div>
        {!preferences.setupDone && (
          <>
            <SettingsDivider full />
            <div className="flex items-center gap-3">
              <span className="flex-1 text-footnote text-muted">{named ? 'Finish and hear Memnox say hello.' : 'Add your name first, then finish.'}</span>
              <KitButton kind={open === undefined ? 'primary' : 'secondary'} disabled={!named} onClick={finish}>
                Finish setup
              </KitButton>
            </div>
          </>
        )}
      </SettingsCard>
    </SettingsSection>
  );
}

/** The home's blocks: what waits, what only the person can do, what is working, today, ready, not covered. */
function HomeBlocks({ parts, view }: { parts: SettingsParts; view: HomeView }) {
  const { home, words, host } = parts;
  return (
    <div className="flex flex-col gap-5">
      <HomeBlock title="Waiting on you">
        <div className="flex items-center gap-2">
          <span className="tabular font-mono text-body font-semibold text-ink">{view.waiting}</span>
          <span className="flex-1 text-body text-muted">{HomeLines.waiting(view.waiting)}</span>
          {view.waiting > 0 && <KitButton onClick={() => host.talk()}>Answer</KitButton>}
        </div>
      </HomeBlock>
      {view.needsYou !== undefined && view.needsYou.length > 0 && (
        <HomeBlock title="What needs you">
          {view.needsYou.map((line) => (
            <p key={line} className="flex items-start gap-2 text-body text-foreground">
              <CircleAlert size={13} className="mt-0.5 shrink-0 text-muted" />
              {line}
            </p>
          ))}
        </HomeBlock>
      )}
      <HomeBlock title="Working now">
        {view.working.length === 0 ? (
          <p className="text-body text-muted">Nothing is working right now.</p>
        ) : (
          view.working.map((session) => (
            <div key={session.sessionId} className="flex items-center gap-3 py-0.5">
              <span className="relative">
                <BrandLogo agent={session.agent} name={session.agentName} size={32} />
                <span className="absolute -right-0.5 -bottom-0.5 size-[9px] rounded-full bg-green ring-2 ring-surface" />
              </span>
              <span className="flex min-w-0 flex-1 flex-col gap-px">
                <span className="text-body font-semibold text-ink">{session.agentName}</span>
                <span className="line-clamp-2 text-footnote text-ink-secondary">{HomeLines.working(session)}</span>
              </span>
              <ChevronRight size={12} strokeWidth={2.6} className="text-ink-tertiary" />
            </div>
          ))
        )}
      </HomeBlock>
      <HomeBlock title="Today">
        <p className="text-body text-foreground">{HomeLines.today(view.today)}</p>
      </HomeBlock>
      {view.ready !== undefined && (
        <HomeBlock title="Ready to hand over">
          <p className="text-headline font-semibold text-ink">{HomeLines.ready(view.ready)}</p>
          {view.ready.targets.length > 0 && (
            <div className="flex flex-col gap-1">
              {view.ready.targets.map((target) => (
                <span key={target} className="truncate font-mono text-footnote text-ink-primary">
                  {target}
                </span>
              ))}
            </div>
          )}
          <p className="text-body text-muted">{view.ready.because}</p>
          <div className="flex items-center gap-2">
            <KitButton
              kind="primary"
              disabled={home.handingOver}
              onClick={() => view.ready !== undefined && void home.handOver(view.ready, words.keyTitle)}
              title={`Proposes an allow rule for exactly these; nothing changes until you confirm it with ${words.keyTitle}`}
            >
              {home.handingOver ? 'Proposing the rule' : 'Let it run on its own'}
            </KitButton>
            {home.handOverNote !== undefined && <span className="text-body text-muted">{home.handOverNote}</span>}
          </div>
        </HomeBlock>
      )}
      <HomeBlock title="Not covered">
        {HomeLines.notCovered(view.notCovered).map((line) => (
          <p key={line} className={`text-body ${view.notCovered.unprotected === 0 && view.notCovered.dormant === 0 ? 'text-muted' : 'text-foreground'}`}>
            {line}
          </p>
        ))}
        {view.notCovered.unprotected > 0 && (
          <div className="flex items-center gap-2">
            <KitButton kind="primary" disabled={home.protecting} onClick={() => void home.protect()} title="Hooks every agent found on this computer into Memnox, the way setup does">
              {home.protecting ? 'Protecting your agents' : 'Protect my agents'}
            </KitButton>
            {home.protectFailed !== undefined && <span className="text-body text-muted">{home.protectFailed}</span>}
          </div>
        )}
      </HomeBlock>
    </div>
  );
}

function HomeBlock({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <SettingsSection title={title}>
      <div className="flex flex-col gap-2 rounded-2xl bg-card p-4">{children}</div>
    </SettingsSection>
  );
}

/** The counts on one line, when the daemon has no home to give. */
function OverviewNumbers({ parts }: { parts: SettingsParts }) {
  const numbers = parts.home.numbers;
  const pairs: [string, number][] = [
    ['Need you', numbers.needYou],
    ['Working', numbers.working],
    ['Agents', numbers.agents],
    ['Repositories', numbers.repositories],
  ];
  return (
    <div className="flex gap-5 pt-1">
      {pairs.map(([label, value]) => (
        <span key={label} className="flex items-baseline gap-1.5">
          <span className="text-footnote text-ink-secondary">{label}</span>
          <span className="tabular text-callout font-semibold text-ink">{value}</span>
        </span>
      ))}
    </div>
  );
}
