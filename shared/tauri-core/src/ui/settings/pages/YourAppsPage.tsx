import { LayoutGrid, Plug, RotateCw, UserRoundPlus } from 'lucide-react';
import { useEffect, useState, type CSSProperties } from 'react';
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
  statusLine,
  statusTone,
  supportPill,
  tabOf,
  tabTitle,
  YOUR_APPS_TABS,
  YourAppDisconnect,
  YourAppsLayout,
  YourAppsLines,
  YourAppsNamed,
  yours,
  type YourAppCard,
  type YourAppNote,
  type YourAppsTab,
} from '../../../core/domain/your-apps';
import { agentLabel } from '../../../core/domain/mcp-hub-lines';
import { SettingsCard, SettingsRow } from '../kit';
import { useObserved, type SettingsParts } from '../parts';
import { Banner, BrandLogo, Button, ConfirmDialog, EmptyState, Pill, Pressable, SearchInput, Spinner, Tabs, ToolMark } from '../../kit';

const TONE_TEXT = { good: 'text-success', attention: 'text-warm', quiet: 'text-muted' } as const;
const TONE_DOT = { good: 'bg-success', attention: 'bg-warm', quiet: 'bg-faint' } as const;
/** The refresh glyph beside Check again, a point under the words. */
const REFRESH_GLYPH = 13;
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
        <Pressable onClick={() => void tools.refresh()} className="mx-focus inline-flex shrink-0 cursor-pointer items-center gap-1.5 text-body-sm text-muted hover:text-foreground">
          <RotateCw size={REFRESH_GLYPH} aria-hidden />
          {YourAppsLines.checkAgain}
        </Pressable>
      </div>
      {signInNeeded && (
        <SettingsCard>
          <SettingsRow icon={UserRoundPlus} tint="var(--color-primary)" title={YourAppsLines.signInTitle} caption={YourAppsLines.signInDetail}>
            {signingIn && <Spinner />}
            <Button kind="primary" disabled={signingIn} aria-label={YourAppsLines.signInTitle} onClick={() => void apps.signInForApps()}>
              {YourAppsLines.signIn}
            </Button>
          </SettingsRow>
        </SettingsCard>
      )}
      {pageNote !== undefined && <Banner title={pageNote.title} words={pageNote.words} dismiss={() => apps.dismissNote()} dismissLabel={YourAppsLines.close} />}
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
          <SearchInput value={query} placeholder={tab === 'all' ? YourAppsLines.searchAll : YourAppsLines.searchThese} onChange={search} count={{ shown: shown.length, total: pool.length }} />
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
          message={YourAppDisconnect.message(leaving.name)}
          detail={YourAppDisconnect.detail(leaving.name)}
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

/** `CategoryRail`: the categories down the side with their counts, commonest first, the chosen one on the active fill. */
function Rail({ total, categories, chosen, choose }: { total: number; categories: readonly { id: string; label: string; count: number }[]; chosen: string | undefined; choose: (id: string | undefined) => void }) {
  const rows = [{ id: undefined, label: YourAppsLines.allToolkits, count: total }, ...categories];
  return (
    <nav aria-label={YourAppsLines.categories} className="flex shrink-0 flex-col gap-0.5" style={{ width: YourAppsLayout.railWidth }}>
      <p className="m-0 px-2.5 pb-1.5 font-code text-meta tracking-[1.98px] text-muted uppercase">{YourAppsLines.categories}</p>
      {rows.map((row) => {
        const on = row.id === chosen;
        return (
          <Pressable
            key={row.id ?? ''}
            onClick={() => choose(row.id)}
            aria-current={on ? 'true' : undefined}
            className={`mx-focus flex w-full cursor-pointer items-center gap-1.5 rounded-control px-2.5 py-1.5 text-left text-body-sm ${on ? 'bg-active font-medium text-foreground' : 'text-muted'}`}
          >
            <span className="min-w-0 flex-1 truncate">{row.label}</span>
            <span className="shrink-0 font-code text-meta tabular-nums text-faint">{row.count}</span>
          </Pressable>
        );
      })}
    </nav>
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
    <article className="flex min-w-0 flex-col gap-3 rounded-card border border-panel-edge bg-card" style={pad}>
      <div className="flex min-w-0 items-start gap-3">
        <ToolMark toolkit={card.slug} size={YourAppsLayout.markSide} />
        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
          <span className="line-clamp-2 text-body-sm font-semibold text-foreground">{card.name}</span>
          {(support !== undefined || isRecommended || order !== undefined) && (
            <span className="flex flex-wrap gap-0.5">
              {support !== undefined && <Pill tint={card.support === 'full' ? 'blue' : 'plain'}>{support}</Pill>}
              {isRecommended && <Pill tint="blue">{YourAppsLines.recommended}</Pill>}
              {order !== undefined && <Pill label={YourAppsNamed.source(order)}>{order}</Pill>}
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
      {note !== undefined && <Banner title={note.title} words={note.words} dismiss={dismissNote} dismissLabel={YourAppsLines.close} />}
      <div className="flex items-center gap-2">
        {card.standing === 'on-this-computer' && <span className="flex min-h-8 items-center text-meta text-faint">{YourAppsLines.onThisComputerFoot}</span>}
        {card.standing === 'connected' && (
          <>
            <Button disabled={disabled} aria-label={YourAppsNamed.disconnect(card.name)} onClick={disconnect}>
              {YourAppsLines.disconnect}
            </Button>
            <Pressable disabled={disabled} aria-label={YourAppsNamed.anotherAccount(card.name)} onClick={anotherAccount} className="mx-focus cursor-pointer text-meta text-muted hover:text-foreground disabled:cursor-default disabled:opacity-45">
              {YourAppsLines.anotherAccount}
            </Pressable>
          </>
        )}
        {card.standing === 'sign-in-again' && (
          <>
            <Button kind="primary" wide disabled={disabled} aria-label={YourAppsNamed.signInAgain(card.name)} onClick={connect}>
              {YourAppsLines.signInAgain}
            </Button>
            <Button disabled={disabled} aria-label={YourAppsNamed.disconnect(card.name)} onClick={disconnect}>
              {YourAppsLines.disconnect}
            </Button>
          </>
        )}
        {card.standing === 'available' && (
          <Button kind="primary" wide disabled={disabled} aria-label={signInFirst ? `${YourAppsLines.signInTitle} ${card.name}` : YourAppsNamed.connect(card.name)} onClick={connect}>
            {signInFirst ? YourAppsLines.signInButton : YourAppsLines.connect}
          </Button>
        )}
        {busy && <Spinner />}
      </div>
    </article>
  );
}

