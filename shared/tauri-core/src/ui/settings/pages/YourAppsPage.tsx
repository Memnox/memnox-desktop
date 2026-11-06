import { CircleAlert, LayoutGrid, Plug, RotateCw, UserRoundPlus, X } from 'lucide-react';
import { useEffect, useState, type CSSProperties } from 'react';
import type { YourAppNote } from '../../../core/domain/your-apps';
import {
  agentsLine,
  categoriesOf,
  countLine,
  FEATURED_TOOLKITS,
  inCategory,
  narrowed,
  offered,
  ORDER_LEGEND,
  orderChip,
  reachLine,
  recommended,
  showingLine,
  statusLine,
  statusTone,
  supportPill,
  tabOf,
  tabTitle,
  YOUR_APPS_TABS,
  YourAppDisconnect,
  YourAppsLayout,
  YourAppsLines,
  yours,
  type YourAppCard,
  type YourAppsTab,
} from '../../../core/domain/your-apps';
import { agentLabel } from '../../../core/domain/mcp-hub-lines';
import { BrandLogo, ToolMark } from '../../kit/logos';
import { EmptyState } from '../../app/widgets';
import { ConfirmDialog } from '../../app/pages/SkillDialogs';
import { KitButton, SearchField, SettingsCard, SettingsRow, Spinner } from '../kit';
import { useObserved, type SettingsParts } from '../parts';

const TONE_TEXT = { good: 'text-success', attention: 'text-warm', quiet: 'text-muted' } as const;
const TONE_DOT = { good: 'bg-success', attention: 'bg-warm', quiet: 'bg-faint' } as const;
/** The console's blue pill, as its Fully supported badge: the blue at 10 percent under a 40 percent edge. */
const BLUE_PILL = 'border-primary/40 bg-primary/10 text-primary';
const PLAIN_PILL = 'border-border text-muted';
/** The agents' logos are a line of small text tall, so they sit level with the words that name them. */
const AGENT_LOGO = 16;

/**
 * Connectors, as the Mac's `YourAppsPage`: Connected, Recommended and All as tabs over a categories rail, one search
 * and one grid of the console's cards. Connecting needs a Memnox Cloud account, so while the daemon says nobody is
 * signed in the page leads with that step and Connect starts the app's own sign in. The list is read again on focus,
 * so a sign in finished in the browser shows at once.
 */
export function YourAppsPage({ parts }: { parts: SettingsParts }) {
  const { tools, apps } = parts;
  useObserved(tools, apps);
  const [chosenTab, chooseTab] = useState<YourAppsTab | undefined>(undefined);
  const [category, setCategory] = useState<string | undefined>(undefined);
  const [leaving, setLeaving] = useState<YourAppCard | undefined>(undefined);
  useEffect(() => {
    void tools.refresh();
    apps.search(apps.state.query);
    const again = () => void tools.refresh();
    window.addEventListener('focus', again);
    return () => window.removeEventListener('focus', again);
  }, []);
  const { connections, connectionsNote, reading } = tools.state;
  const { busy, notice, waitingFor, query, found, searchNote, signInNeeded, signingIn } = apps.state;
  const mine = yours(connections, found);
  const tab = tabOf(chosenTab, query, mine.length);
  const pool = tab === 'connected' ? narrowed(mine, query) : tab === 'recommended' ? narrowed(recommended(found, connections), query) : offered(found, searchNote !== undefined, query, connections);
  const categories = categoriesOf(pool);
  const shown = pool.filter((each) => inCategory(each, category));
  // A note that belongs to no card on screen is said over the grid, so it is never lost behind a tab or a category.
  const pageNote = notice !== undefined && (notice.toolkit === undefined || !shown.some((each) => each.slug === notice.toolkit)) ? notice : undefined;
  const search = (words: string) => {
    // A category from one search means nothing in the next, as the console resets it.
    setCategory(undefined);
    apps.search(words);
  };
  const featured = new Set(FEATURED_TOOLKITS);

  return (
    <div className="flex flex-col gap-5">
      <div className="flex items-center gap-3">
        <Tabs
          tabs={YOUR_APPS_TABS.map((each) => ({ id: each, title: tabTitle(each, mine.length) }))}
          chosen={tab}
          choose={(id) => {
            chooseTab(id);
            setCategory(undefined);
          }}
        />
        <button type="button" onClick={() => void tools.refresh()} className="mx-focus inline-flex shrink-0 cursor-pointer items-center gap-1.5 text-body-sm text-muted hover:text-foreground">
          <RotateCw size={13} aria-hidden />
          {YourAppsLines.checkAgain}
        </button>
      </div>
      {signInNeeded && (
        <SettingsCard>
          <SettingsRow icon={UserRoundPlus} tint="var(--color-primary)" title={YourAppsLines.signInTitle} caption={YourAppsLines.signInDetail}>
            {signingIn && <Spinner />}
            <KitButton kind="primary" disabled={signingIn} aria-label={YourAppsLines.signInTitle} onClick={() => void apps.signInForApps()}>
              {YourAppsLines.signIn}
            </KitButton>
          </SettingsRow>
        </SettingsCard>
      )}
      {pageNote !== undefined && <NoteView note={pageNote} dismiss={() => apps.dismissNote()} />}
      <div className="flex items-start" style={{ gap: YourAppsLayout.railSpacing }}>
        {categories.length > 0 && (
          <Rail
            total={pool.length}
            categories={categories.slice(0, YourAppsLayout.railLeading)}
            chosen={category}
            choose={setCategory}
          />
        )}
        <div className="flex min-w-0 flex-1 flex-col gap-5">
          <div className="flex items-center gap-3">
            <div className="min-w-0 flex-1">
              <SearchField value={query} placeholder={tab === 'all' ? YourAppsLines.searchAll : YourAppsLines.searchThese} onChange={search} />
            </div>
            <span className="shrink-0 font-mono text-meta tabular-nums text-muted" aria-live="polite">
              {showingLine(shown.length, pool.length)}
            </span>
          </div>
          {tab === 'all' && found.some((each) => each.source !== undefined) && <p className="m-0 text-meta text-faint">{ORDER_LEGEND}</p>}
          {tab === 'all' && searchNote !== undefined && <p className="m-0 text-meta text-warm">{searchNote}</p>}
          {shown.length === 0 ? (
            tab === 'connected' && reading ? (
              <EmptyState icon={LayoutGrid} title={YourAppsLines.reading} body={YourAppsLines.readingDetail} />
            ) : tab === 'connected' && query.trim() === '' ? (
              <EmptyState icon={LayoutGrid} title={YourAppsLines.noApps} body={connectionsNote ?? YourAppsLines.noAppsDetail} />
            ) : (
              <EmptyState icon={LayoutGrid} title={countLine(0, query)} body={tab === 'all' ? YourAppsLines.tryAnother : YourAppsLines.searchAllDetail} />
            )
          ) : (
            <div className="grid items-stretch" style={{ gridTemplateColumns: `repeat(auto-fill, minmax(${YourAppsLayout.cardMinimum}px, 1fr))`, gap: YourAppsLayout.gridSpacing }}>
              {shown.map((each) => (
                <AppTile
                  key={each.slug}
                  card={each}
                  recommended={featured.has(each.slug)}
                  busy={busy === each.slug}
                  waiting={waitingFor === each.slug}
                  disabled={busy !== undefined || signingIn}
                  signInFirst={signInNeeded}
                  note={notice?.toolkit === each.slug ? notice : undefined}
                  connect={() => void apps.connect(each.slug, each.standing === 'sign-in-again')}
                  anotherAccount={() => void apps.connect(each.slug, true)}
                  disconnect={() => setLeaving(each)}
                  dismissNote={() => apps.dismissNote()}
                />
              ))}
            </div>
          )}
        </div>
      </div>
      <p className="m-0 text-meta text-faint">{YourAppsLines.allowance}</p>
      {leaving !== undefined && (
        <ConfirmDialog
          icon={Plug}
          title={YourAppDisconnect.title(leaving.name)}
          message={`${YourAppDisconnect.message(leaving.name)} ${YourAppDisconnect.detail(leaving.name)}`}
          confirm={YourAppDisconnect.confirm}
          cancel={() => setLeaving(undefined)}
          act={() => {
            const slug = leaving.slug;
            setLeaving(undefined);
            void apps.disconnect(slug);
          }}
        />
      )}
    </div>
  );
}

/** The tabs as the Mac's `InspectorTabs`: 13 medium, an underline in blue under the chosen one, a hairline under all. */
function Tabs({ tabs, chosen, choose }: { tabs: readonly { id: YourAppsTab; title: string }[]; chosen: YourAppsTab; choose: (id: YourAppsTab) => void }) {
  return (
    <div role="tablist" className="flex min-w-0 flex-1 overflow-x-auto border-b border-panel-edge">
      {tabs.map((each) => {
        const on = each.id === chosen;
        return (
          <button
            key={each.id}
            type="button"
            role="tab"
            aria-selected={on}
            onClick={() => choose(each.id)}
            className={`mx-focus -mb-px shrink-0 cursor-pointer border-b-2 px-3 py-2.5 text-body-sm font-medium whitespace-nowrap ${on ? 'border-primary text-foreground' : 'border-transparent text-muted hover:text-foreground'}`}
          >
            {each.title}
          </button>
        );
      })}
    </div>
  );
}

/** The categories down the side with their counts, commonest first, as the console's rail. */
function Rail({ total, categories, chosen, choose }: { total: number; categories: readonly { id: string; label: string; count: number }[]; chosen: string | undefined; choose: (id: string | undefined) => void }) {
  const rows = [{ id: undefined, label: YourAppsLines.allToolkits, count: total }, ...categories];
  return (
    <nav aria-label={YourAppsLines.categories} className="flex shrink-0 flex-col gap-0.5" style={{ width: YourAppsLayout.railWidth }}>
      <p className="m-0 px-2.5 pb-1.5 font-mono text-meta tracking-[0.165em] text-muted uppercase">{YourAppsLines.categories}</p>
      {rows.map((row) => {
        const on = row.id === chosen;
        return (
          <button
            key={row.id ?? ''}
            type="button"
            onClick={() => choose(row.id)}
            aria-current={on ? 'true' : undefined}
            className={`mx-focus flex w-full cursor-pointer items-center gap-1.5 rounded-md px-2.5 py-1.5 text-left text-body-sm ${on ? 'bg-active font-medium text-foreground' : 'text-muted hover:text-foreground'}`}
          >
            <span className="min-w-0 flex-1 truncate">{row.label}</span>
            <span className="shrink-0 font-mono text-meta tabular-nums text-faint">{row.count}</span>
          </button>
        );
      })}
    </nav>
  );
}

function Pill({ words, blue, label }: { words: string; blue: boolean; label?: string }) {
  return (
    <span aria-label={label} className={`inline-flex shrink-0 items-center rounded-full border px-2 py-0.5 text-label font-medium whitespace-nowrap ${blue ? BLUE_PILL : PLAIN_PILL}`}>
      {words}
    </span>
  );
}

/**
 * One tool's card in the console's connector look, as the Mac's `YourAppTile`: its logo, its name with the support
 * pill and a Recommended pill, its kind, two lines of the provider's own words, where it stands in its colour, and its
 * buttons at the foot.
 */
function AppTile({
  card,
  recommended: isRecommended,
  busy,
  waiting,
  disabled,
  signInFirst,
  note,
  connect,
  anotherAccount,
  disconnect,
  dismissNote,
}: {
  card: YourAppCard;
  recommended: boolean;
  busy: boolean;
  waiting: boolean;
  disabled: boolean;
  signInFirst: boolean;
  note: YourAppNote | undefined;
  connect: () => void;
  anotherAccount: () => void;
  disconnect: () => void;
  dismissNote: () => void;
}) {
  const support = supportPill(card);
  const order = orderChip(card);
  const tone = statusTone(card, waiting);
  const agents = agentsLine(card, agentLabel);
  const pad: CSSProperties = { padding: YourAppsLayout.cardPadding };
  return (
    <article className="flex min-w-0 flex-col gap-3 rounded-xl border border-panel-edge bg-card" style={pad}>
      <div className="flex min-w-0 items-start gap-3">
        <ToolMark toolkit={card.slug} size={YourAppsLayout.markSide} />
        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
          <span className="line-clamp-2 text-body-sm font-semibold text-foreground">{card.name}</span>
          {(support !== undefined || isRecommended || order !== undefined) && (
            <span className="flex flex-wrap gap-0.5">
              {support !== undefined && <Pill words={support} blue={card.support === 'full'} />}
              {isRecommended && <Pill words={YourAppsLines.recommended} blue />}
              {order !== undefined && <Pill words={order} blue={false} label={`Source ${order}`} />}
            </span>
          )}
          <span className="text-meta text-muted">{reachLine(card)}</span>
        </div>
      </div>
      {card.description !== undefined && <p className="m-0 line-clamp-2 text-meta text-muted">{card.description}</p>}
      <span className="flex items-center gap-1.5">
        <span className={`size-1.5 shrink-0 rounded-full ${TONE_DOT[tone]}`} aria-hidden />
        <span className={`text-meta font-medium ${TONE_TEXT[tone]}`}>{statusLine(card, waiting)}</span>
      </span>
      {agents !== undefined && (
        <span className="flex items-start gap-1.5">
          {card.uses.length > 0 && (
            <span className="flex shrink-0 gap-0.5" aria-hidden>
              {[...new Set(card.uses.map((use) => use.agent))].map((agent) => (
                <BrandLogo key={agent} agent={agent} name={agentLabel(agent)} size={AGENT_LOGO} />
              ))}
            </span>
          )}
          <span className="text-meta text-muted">{agents}</span>
        </span>
      )}
      <span className="flex-1" />
      {note !== undefined && <NoteView note={note} dismiss={dismissNote} />}
      <div className="flex items-center gap-2">
        {card.standing === 'on-this-computer' && <span className="flex min-h-8 items-center text-meta text-faint">{YourAppsLines.onThisComputerFoot}</span>}
        {card.standing === 'connected' && (
          <>
            <KitButton disabled={disabled} aria-label={`Disconnect ${card.name}`} onClick={disconnect}>
              {YourAppsLines.disconnect}
            </KitButton>
            <button type="button" disabled={disabled} aria-label={`Sign in to ${card.name} with another account`} onClick={anotherAccount} className="mx-focus cursor-pointer text-meta text-muted hover:text-foreground disabled:cursor-default disabled:opacity-45">
              {YourAppsLines.anotherAccount}
            </button>
          </>
        )}
        {card.standing === 'sign-in-again' && (
          <>
            <KitButton kind="primary" wide disabled={disabled} aria-label={`Sign in to ${card.name} again`} onClick={connect}>
              {YourAppsLines.signInAgain}
            </KitButton>
            <KitButton disabled={disabled} aria-label={`Disconnect ${card.name}`} onClick={disconnect}>
              {YourAppsLines.disconnect}
            </KitButton>
          </>
        )}
        {card.standing === 'available' && (
          <KitButton kind="primary" wide disabled={disabled} aria-label={signInFirst ? `${YourAppsLines.signInTitle} ${card.name}` : `Connect ${card.name}`} onClick={connect}>
            {signInFirst ? YourAppsLines.signInButton : YourAppsLines.connect}
          </KitButton>
        )}
        {busy && <Spinner />}
      </div>
    </article>
  );
}

/** A note that something did not work, inline where it happened, with a close button so it never stands over the page. */
function NoteView({ note, dismiss }: { note: YourAppNote; dismiss: () => void }) {
  return (
    <div role="status" className="flex items-start gap-2 rounded-md border border-warm/35 bg-warm/[0.08] p-3">
      <CircleAlert size={14} className="mt-0.5 shrink-0 text-warm" aria-hidden />
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="text-meta font-semibold text-foreground">{note.title}</span>
        <span className="text-meta break-words text-muted select-text">{note.words}</span>
      </div>
      <button type="button" aria-label={YourAppsLines.close} onClick={dismiss} className="mx-focus cursor-pointer text-muted hover:text-foreground">
        <X size={11} strokeWidth={2.5} />
      </button>
    </div>
  );
}
