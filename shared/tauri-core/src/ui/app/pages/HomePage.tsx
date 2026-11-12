import { CONNECTION_PAGE, RuntimeAwayLines, type RuntimeStanding } from '../../../core/domain/runtime-away';
import { useRuntimeStanding } from '../runtime-standing';
import { UpdateBanner } from '../../UpdateOffers';
import { ArrowRight } from 'lucide-react';
import { useEffect } from 'react';
import type { Route, WidthClass } from '../../../core/domain/destinations';
import { greeting } from '../../../core/domain/setup-steps';
import { useObserved, usePreferences, type SettingsParts } from '../../settings/parts';
import { homeMode, modeBadge } from '../../../core/domain/home-steps';
import { HomePageLines } from '../../../core/domain/home-page-lines';
import { HomeStart } from './HomeStart';
import { TodayPage } from './TodayPage';
import { Note, PRESS_DIP, Pressable, ReadFailed, Spinner, StatusWord } from '../../kit';

/**
 * Home is the one page the window opens on, the same on the console, the Mac, Windows and Linux: the greeting and mode,
 * one Do this next card, then the blocks in the contract's order, each counting what it holds in its header. No charts
 * and no tiles, and every number is a count the ledger can show.
 */
export function HomePage({ parts, width, go }: { parts: SettingsParts; width: WidthClass; go: (route: Route) => void }) {
  const { home, sessions, preferences, host } = parts;
  useObserved(home, sessions);
  usePreferences();
  useEffect(() => {
    void home.refresh();
    sessions.start();
    return () => sessions.stop();
  }, []);
  useEffect(() => host.onHomeStale?.(() => home.refreshSoon()), []);
  // Live rows count into today's actions as they happen, with no read each second.
  useEffect(() => host.onLiveActivity?.((rows, missed) => home.heard(rows.length + missed)), []);

  const view = home.home;
  const standing = useRuntimeStanding(parts);
  const lead = (
    <>
      <header className="flex flex-wrap items-end justify-between gap-x-3 gap-y-2">
        <div className="flex flex-col gap-1">
          <h1 className="text-app-greeting leading-tight font-bold text-foreground">{greeting(preferences.name)}</h1>
          <p className="text-footnote text-muted">{HomePageLines.lead}</p>
        </div>
        <Standing mode={homeMode(view?.mode)} read={view !== undefined} standing={standing} />
      </header>

      {/* A service still being set up is said calmly; only one that stayed away reads as a fault with a way to fix it. */}
      {standing === 'starting' && (
        <Note>
          <span className="flex items-center gap-2">
            <Spinner />
            <span className="flex flex-col">
              <span className="font-medium text-foreground">{RuntimeAwayLines.starting}</span>
              <span>{RuntimeAwayLines.startingDetail}</span>
            </span>
          </span>
        </Note>
      )}
      {standing === 'away' && (
        <div className="flex flex-col gap-2">
          <ReadFailed what={HomePageLines.readFailed} retry={() => void home.refresh()} />
          <GoLink onClick={() => host.openSettings(CONNECTION_PAGE)}>{RuntimeAwayLines.openConnection}</GoLink>
        </div>
      )}

      <UpdateBanner updates={parts.updates} />

      {/* The one Do this next card, setup first until it is done, then the getting started steps until every one is. */}
      <HomeStart parts={parts} go={go} actions={view?.today.actions ?? 0} mode={homeMode(view?.mode)} openSetup={() => host.openOnboarding()} />
    </>
  );
  return <TodayPage parts={parts} width={width} go={go} lead={lead} />;
}

/** The mode the runtime reported, as the Mac's badge beside the greeting says it, or whether the runtime answers at all. */
function Standing({ mode, read, standing }: { mode: ReturnType<typeof homeMode>; read: boolean; standing: RuntimeStanding }) {
  // The last read decides, since a home kept from before outlives a runtime that stopped since.
  if (standing === 'away') return <StatusWord tone="bad">{HomePageLines.away}</StatusWord>;
  if (standing === 'starting') return <StatusWord tone="quiet">{RuntimeAwayLines.starting}</StatusWord>;
  if (mode !== undefined) return <StatusWord tone={mode === 'enforce' ? 'good' : 'attention'}>{modeBadge(mode)}</StatusWord>;
  if (read) return <StatusWord tone="good">{HomePageLines.protecting}</StatusWord>;
  return null;
}

/** `GoLink`'s arrow is micro sized and semibold, smaller than its 12 point words. */
const GO_ARROW = 10;
const GO_ARROW_STROKE = 2.5;

/** `GoLink`: a quiet link to another place in the window, 12 medium in the brand blue with an arrow after it. */
export function GoLink({ onClick, children }: { onClick: () => void; children: string }) {
  return (
    <Pressable className={`mx-focus inline-flex w-fit cursor-pointer items-center gap-1 self-start text-footnote font-medium text-primary ${PRESS_DIP}`} onClick={onClick}>
      {children}
      <ArrowRight size={GO_ARROW} strokeWidth={GO_ARROW_STROKE} aria-hidden />
    </Pressable>
  );
}
