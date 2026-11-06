import type { HomeView } from '@memnox/core/wire';
import { islandWindow } from '../../adapters/tauri-island-window';
import { AudioLines, ChevronRight, CircleAlert, CircleArrowRight, CircleCheck, Laptop, UserRoundCheck } from 'lucide-react';
import { useEffect } from 'react';
import { FIRST_RUN } from '../../../core/application/preferences';
import { HomeLines } from '../../../core/domain/home-lines';
import { pageInfo, type SettingsPage } from '../../../core/domain/settings-pages';
import { firstName, greeting, openStep, overviewSteps, readyCount } from '../../../core/domain/setup-steps';
import { HOVER_LIGHT, Keycaps, SettingsCard, SettingsDivider, SettingsRow, SettingsSection, StatusMark } from '../kit';
import { useObserved, usePreferences, type SettingsParts } from '../parts';
import { BrandLogo, Button, Card, Pressable, TruncatedText } from '../../kit';
import { OverviewLines } from '../../../core/domain/overview-lines';

/** A row's trailing chevron, 12 heavy, and the mark beside a line that needs the person. */
const ROW_CHEVRON = 12;
const ROW_CHEVRON_STROKE = 2.6;
const NEED_GLYPH = 13;
/** A working session's agent logo, as the Mac's home row draws it. */
const SESSION_LOGO = 32;

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
  // While the page shows, a change on the daemon's stream reads the home again once the burst passes, as the Mac's.
  useEffect(() => host.onHomeStale?.(() => home.refreshSoon()), []);
  const finished = preferences.setupDone;
  const name = preferences.name;
  const blocks = home.home === undefined && home.unavailable ? <OverviewNumbers parts={parts} /> : home.home !== undefined ? <HomeBlocks parts={parts} view={home.home} /> : null;
  return (
    <>
      <header className="flex flex-col gap-1">
        <h1 className="text-title font-bold text-foreground">{greeting(name)}</h1>
        <p className="text-footnote text-muted">{OverviewLines.subtitle}</p>
      </header>
      <div>
        <Button icon={AudioLines} onClick={() => host.talk()} title={OverviewLines.talkHint(words.talkKeysSaid)}>
          {OverviewLines.talk}
          <Keycaps keys={words.talkKeys} />
        </Button>
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
      <SettingsSection title={OverviewLines.startHere}>
        <SettingsCard>
          <SettingsRow icon={Laptop} title={OverviewLines.setUpComputer} caption={OverviewLines.setUpComputerCaption(words.keyTitle)}>
            <Button kind="primary" onClick={() => chose(FIRST_RUN.thisComputer)}>
              {OverviewLines.setUp}
            </Button>
          </SettingsRow>
          <SettingsDivider />
          <SettingsRow
            icon={UserRoundCheck}
            title={OverviewLines.signIn}
            caption={signedIn ? OverviewLines.signedInCaption : OverviewLines.signInCaption}
          >
            <Button onClick={() => chose(FIRST_RUN.account)}>{signedIn ? OverviewLines.openAccount : OverviewLines.signIn}</Button>
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
    void host.voices.say(OverviewLines.hello(first, words.talkKeysSaid)).catch(() => undefined);
  };
  return (
    <SettingsSection
      title={open === undefined ? OverviewLines.setUpTitle : OverviewLines.doNext}
      trailing={<span className="tabular text-footnote text-muted">{OverviewLines.readyOf(ready, steps.length)}</span>}
    >
      <SettingsCard>
        {open !== undefined ? (
          <SettingsRow icon={CircleArrowRight} title={open.title} caption={open.hint}>
            <Button kind="primary" onClick={() => go(open.page)}>
              {OverviewLines.goTo(pageInfo(open.page).title)}
            </Button>
          </SettingsRow>
        ) : (
          <SettingsRow icon={CircleCheck} tint="var(--mx-success)" title={OverviewLines.allReady} caption={OverviewLines.allReadyCaption(words.talkKeysSaid)} />
        )}
        <SettingsDivider full />
        <div className="flex flex-col">
          {steps.map((step) => (
            <Pressable
              key={step.title}
              className={`${HOVER_LIGHT} flex h-control cursor-pointer items-center gap-2 text-left`}
              onClick={() => go(step.page)}
              title={OverviewLines.openPage(pageInfo(step.page).title)}
              aria-label={OverviewLines.stepState(step.title, step.state.kind === 'done')}
            >
              <StatusMark state={step.state} />
              <span className={`flex-1 truncate text-body ${step.state.kind === 'done' ? 'text-muted' : 'text-foreground'}`}>{step.title}</span>
              <span className="text-footnote text-faint">{pageInfo(step.page).title}</span>
              <ChevronRight size={ROW_CHEVRON} strokeWidth={ROW_CHEVRON_STROKE} className="text-faint" />
            </Pressable>
          ))}
        </div>
        {!preferences.setupDone && (
          <>
            <SettingsDivider full />
            <div className="flex items-center gap-3">
              <span className="flex-1 text-footnote text-muted">{named ? OverviewLines.finishReady : OverviewLines.finishNamed}</span>
              <Button kind={open === undefined ? 'primary' : 'secondary'} disabled={!named} onClick={finish}>
                {OverviewLines.finish}
              </Button>
            </div>
          </>
        )}
      </SettingsCard>
    </SettingsSection>
  );
}

/** The home's blocks: what waits, what only the person can do, what is working, today, ready, not covered. */
function HomeBlocks({ parts, view }: { parts: SettingsParts; view: HomeView }) {
  const { home, words } = parts;
  return (
    <div className="flex flex-col gap-5">
      <HomeBlock title={OverviewLines.waitingTitle}>
        <div className="flex items-center gap-2">
          <span className="tabular font-mono text-body font-semibold text-ink">{view.waiting}</span>
          <span className="flex-1 text-body text-muted">{HomeLines.waiting(view.waiting)}</span>
          {view.waiting > 0 && <Button onClick={() => islandWindow.openFromSettings()}>{OverviewLines.answer}</Button>}
        </div>
      </HomeBlock>
      {view.needsYou !== undefined && view.needsYou.length > 0 && (
        <HomeBlock title={OverviewLines.needsTitle}>
          {view.needsYou.map((line) => (
            <p key={line} className="flex items-start gap-2 text-body text-foreground">
              <CircleAlert size={NEED_GLYPH} className="mt-0.5 shrink-0 text-muted" />
              {line}
            </p>
          ))}
        </HomeBlock>
      )}
      <HomeBlock title={OverviewLines.workingTitle}>
        {view.working.length === 0 ? (
          <p className="text-body text-muted">{OverviewLines.nothingWorking}</p>
        ) : (
          view.working.map((session) => (
            <Pressable
              key={session.sessionId}
              className={`-mx-1.5 flex cursor-pointer items-center gap-3 rounded-control px-1.5 py-0.5 text-left ${HOVER_LIGHT}`}
              onClick={() => parts.host.openLive?.(session.sessionId)}
              title={OverviewLines.openLive}
            >
              <span className="relative">
                <BrandLogo agent={session.agent} name={session.agentName} size={SESSION_LOGO} />
                <span className="absolute -right-0.5 -bottom-0.5 size-[9px] rounded-full bg-green ring-2 ring-surface" />
              </span>
              <span className="flex min-w-0 flex-1 flex-col gap-px">
                <span className="text-body font-semibold text-ink">{session.agentName}</span>
                <span className="line-clamp-2 text-footnote text-ink-secondary">{HomeLines.working(session)}</span>
              </span>
              <ChevronRight size={ROW_CHEVRON} strokeWidth={ROW_CHEVRON_STROKE} className="text-ink-tertiary" />
            </Pressable>
          ))
        )}
      </HomeBlock>
      <HomeBlock title={OverviewLines.todayTitle}>
        <p className="text-body text-foreground">{HomeLines.today(view.today)}</p>
      </HomeBlock>
      {view.ready !== undefined && (
        <HomeBlock title={OverviewLines.readyTitle}>
          <p className="text-headline font-semibold text-ink">{HomeLines.ready(view.ready)}</p>
          {view.ready.targets.length > 0 && (
            <div className="flex flex-col gap-1">
              {view.ready.targets.map((target) => (
                <TruncatedText key={target} text={target} middle className="font-code text-footnote text-ink-primary" />
              ))}
            </div>
          )}
          <p className="text-body text-muted">{view.ready.because}</p>
          <div className="flex items-center gap-2">
            <Button
              kind="primary"
              disabled={home.handingOver}
              onClick={() => view.ready !== undefined && void home.handOver(view.ready, words.keyTitle)}
              title={OverviewLines.handOverHint(words.keyTitle)}
            >
              {home.handingOver ? OverviewLines.handingOver : OverviewLines.handOver}
            </Button>
            {home.handOverNote !== undefined && <span className="text-body text-muted">{home.handOverNote}</span>}
          </div>
        </HomeBlock>
      )}
      <HomeBlock title={OverviewLines.notCoveredTitle}>
        {HomeLines.notCovered(view.notCovered).map((line) => (
          <p key={line} className={`text-body ${view.notCovered.unprotected === 0 && view.notCovered.dormant === 0 ? 'text-muted' : 'text-foreground'}`}>
            {line}
          </p>
        ))}
        {view.notCovered.unprotected > 0 && (
          <div className="flex items-center gap-2">
            <Button kind="primary" disabled={home.protecting} onClick={() => void home.protect()} title={OverviewLines.protectHint}>
              {home.protecting ? OverviewLines.protecting : OverviewLines.protect}
            </Button>
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
      <Card pad="roomy" className="flex flex-col gap-2">
        {children}
      </Card>
    </SettingsSection>
  );
}

/** The counts on one line, when the daemon has no home to give. */
function OverviewNumbers({ parts }: { parts: SettingsParts }) {
  const numbers = parts.home.numbers;
  const pairs: [string, number][] = [
    [OverviewLines.needYou, numbers.needYou],
    [OverviewLines.working, numbers.working],
    [OverviewLines.agents, numbers.agents],
    [OverviewLines.repositories, numbers.repositories],
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
