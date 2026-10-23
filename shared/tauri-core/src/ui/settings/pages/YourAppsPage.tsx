import { CircleAlert, Link, RotateCw, UserRoundX } from 'lucide-react';
import { useEffect, useState, type ReactNode } from 'react';
import type { AppConnections } from '../../../core/application/app-connections';
import { catalogueCards, connectedCards, connectedSummary, resultCountLine, type CatalogueCard, type ConnectedCard, type YourConnection } from '../../../core/domain/your-apps';
import { ToolMark } from '../../kit/logos';
import { KitButton, SearchField, SettingsCard, SettingsRow, SettingsSection, Spinner } from '../kit';
import { useObserved, type SettingsParts } from '../parts';

/** The mark on every card, a little larger than a row's tile so the grid reads as a shelf of apps. */
const MARK_SIDE = 32;
const GRID = 'grid grid-cols-[repeat(auto-fill,minmax(200px,1fr))] gap-2.5';

/**
 * Your apps, as the Mac's page of the same name: the tools the person connected as themselves and the
 * ones this computer already reaches, then the catalogue searched for more, each one press from its own
 * sign in in the browser. The list is read again on focus, so a sign in finished there shows at once.
 */
export function YourAppsPage({ parts }: { parts: SettingsParts }) {
  const { tools, apps } = parts;
  useObserved(tools, apps);
  useEffect(() => {
    void tools.refresh();
    apps.search(apps.state.query);
    const again = () => void tools.refresh();
    window.addEventListener('focus', again);
    return () => window.removeEventListener('focus', again);
  }, []);
  const { connections, connectionsNote, reading } = tools.state;
  const { busy, note, waitingFor, query, found, searchNote, searching } = apps.state;
  const mine = connectedCards(connections as readonly YourConnection[], waitingFor);
  const offered = catalogueCards(found, connections as readonly YourConnection[], waitingFor);
  return (
    <>
      <SettingsSection title="Connected" trailing={<span className="text-footnote text-muted">{reading ? 'Reading' : connectedSummary(mine)}</span>}>
        {connectionsNote !== undefined && mine.length === 0 ? (
          <SettingsCard>
            <SettingsRow icon={UserRoundX} tint="var(--mx-warm)" title="Your apps are not showing" caption={connectionsNote} />
          </SettingsCard>
        ) : mine.length === 0 ? (
          <SettingsCard>
            <SettingsRow icon={Link} title={reading ? 'Reading your apps' : 'No apps connected yet'} caption="Search below for any tool you use and sign in to it in your browser." />
          </SettingsCard>
        ) : (
          <div className={GRID}>
            {mine.map((card) => (
              <MineCard key={card.toolkit} card={card} apps={apps} />
            ))}
          </div>
        )}
      </SettingsSection>
      {note !== undefined && (
        <SettingsCard>
          <SettingsRow icon={CircleAlert} tint="var(--mx-warm)" title="That did not work" caption={note} />
        </SettingsCard>
      )}
      <SettingsSection title="Connect a tool" trailing={<span className="text-footnote text-muted">{resultCountLine({ query, count: found.length, searching, note: searchNote })}</span>}>
        <SearchField value={query} placeholder="Search apps" onChange={(words) => apps.search(words)} />
        {offered.length > 0 && (
          <div className={GRID}>
            {offered.map((card) => (
              <CatalogueCardView key={card.slug} card={card} busy={busy} connect={() => void apps.connect(card.slug)} />
            ))}
          </div>
        )}
      </SettingsSection>
      <div className="flex justify-end">
        <KitButton icon={RotateCw} onClick={() => void tools.refresh()}>
          Check again
        </KitButton>
      </div>
    </>
  );
}

/** One card: the mark, the name, one line, and what can be done at its foot. */
function AppCard({ toolkit, name, line, children }: { toolkit: string; name: string; line: string; children?: ReactNode }) {
  return (
    <div className="flex min-w-0 flex-col gap-3 rounded-2xl bg-card p-4">
      <div className="flex min-w-0 items-center gap-3">
        <ToolMark toolkit={toolkit} size={MARK_SIDE} />
        <div className="flex min-w-0 flex-col gap-0.5">
          <span className="truncate text-body font-medium text-foreground">{name}</span>
          <span className="truncate text-footnote text-muted" title={line}>
            {line}
          </span>
        </div>
      </div>
      {children !== undefined && <div className="flex items-center justify-end gap-1.5">{children}</div>}
    </div>
  );
}

/** A tool the person has: Disconnect after asking first, Sign in again where it stopped working, nothing for a local one. */
function MineCard({ card, apps }: { card: ConnectedCard; apps: AppConnections }) {
  const [asking, setAsking] = useState(false);
  const { busy } = apps.state;
  if (asking) {
    return (
      <AppCard toolkit={card.toolkit} name={card.name} line="Memnox stops working in it for you until you connect it again.">
        <KitButton onClick={() => setAsking(false)}>Cancel</KitButton>
        <KitButton
          kind="primary"
          onClick={() => {
            setAsking(false);
            void apps.disconnect(card.toolkit);
          }}
        >
          Disconnect
        </KitButton>
      </AppCard>
    );
  }
  if (!card.canDisconnect) return <AppCard toolkit={card.toolkit} name={card.name} line={card.line} />;
  return (
    <AppCard toolkit={card.toolkit} name={card.name} line={card.line}>
      {busy === card.toolkit && <Spinner />}
      {card.canSignInAgain && (
        <KitButton kind="primary" disabled={busy !== undefined} onClick={() => void apps.connect(card.toolkit, true)}>
          Sign in again
        </KitButton>
      )}
      <KitButton disabled={busy !== undefined} onClick={() => setAsking(true)}>
        Disconnect
      </KitButton>
    </AppCard>
  );
}

/** A tool from the catalogue: Connect when the person has not got it, its standing when they have. */
function CatalogueCardView({ card, busy, connect }: { card: CatalogueCard; busy: string | undefined; connect: () => void }) {
  return (
    <AppCard toolkit={card.slug} name={card.name} line={card.line}>
      {busy === card.slug && <Spinner />}
      {card.standing === 'new' && (
        <KitButton kind="primary" disabled={busy !== undefined} aria-label={`Connect ${card.name}`} onClick={connect}>
          Connect
        </KitButton>
      )}
    </AppCard>
  );
}
