import { ChevronRight, CircleAlert, Link, Plus, RotateCw, Terminal, UserRoundX } from 'lucide-react';
import { Fragment, useEffect, useState } from 'react';
import type { ToolConnection } from '@memnox/core/wire';
import type { AppConnections } from '../../../core/application/app-connections';
import { agentStatusWord, connectionStatusWord } from '../../../core/application/tools';
import { toolkitName } from '../../../core/domain/tool-brand';
import { AgentMark, ToolMark } from '../../kit/logos';
import { HOVER_LIGHT, KitButton, SearchField, SettingsCard, SettingsDivider, SettingsRow, Spinner } from '../kit';
import { useObserved, type SettingsParts } from '../parts';

/** A 7 dot after a tool: ready in the success colour, needing the person in the warm one. */
function StatusDot({ ready }: { ready: boolean }) {
  return <span className={`size-[7px] shrink-0 rounded-full ${ready ? 'bg-success' : 'bg-warm'}`} aria-label={ready ? 'Ready' : 'Needs you'} />;
}

/** The Connected tools page, as the Mac's `ToolsPage`: the agents on this computer, then the person's own apps. */
export function ToolsPage({ parts }: { parts: SettingsParts }) {
  const { tools, apps } = parts;
  useObserved(tools, apps);
  const [adding, setAdding] = useState(false);
  useEffect(() => {
    void tools.refresh();
    // Back from the browser's sign in, the list is read again so a tool just connected shows at once.
    const again = () => void tools.refresh();
    window.addEventListener('focus', again);
    return () => window.removeEventListener('focus', again);
  }, []);
  const { agents, connections, connectionsNote, reading } = tools.state;
  const { busy, note } = apps.state;
  return (
    <>
      <SettingsCard title="Agents">
        {agents.length === 0 ? (
          <SettingsRow icon={Terminal} title={reading ? 'Looking for agents' : 'No agents found'} caption="Install Claude Code, Codex or Cursor and Memnox finds it." />
        ) : (
          agents.map((agent, index) => (
            <Fragment key={agent.kind}>
              {index > 0 && <SettingsDivider />}
              <SettingsRow tile={<AgentMark agent={agent.kind} name={agent.label} />} title={agent.label} caption={<span className="text-micro">{agentStatusWord(agent)}</span>}>
                <StatusDot ready={agent.works !== false} />
              </SettingsRow>
            </Fragment>
          ))
        )}
      </SettingsCard>
      <SettingsCard title="Apps">
        {connectionsNote !== undefined && (
          <>
            <SettingsRow icon={UserRoundX} tint="var(--mx-warm)" title="Your apps are not showing" caption={connectionsNote} />
            {connections.length > 0 && <SettingsDivider />}
          </>
        )}
        {connections.length === 0 && connectionsNote === undefined ? (
          <SettingsRow icon={Link} title={reading ? 'Reading your apps' : 'No apps connected yet'} caption="Add any app you use and Memnox can work in it for you." />
        ) : (
          connections.map((connection, index) => (
            <Fragment key={connection.toolkit}>
              {index > 0 && <SettingsDivider />}
              <AppRow connection={connection} apps={apps} />
            </Fragment>
          ))
        )}
        {connectionsNote === undefined && (
          <>
            <SettingsDivider />
            <button type="button" className={`${HOVER_LIGHT} cursor-pointer text-left disabled:pointer-events-none disabled:opacity-45`} disabled={busy !== undefined} onClick={() => setAdding(true)}>
              <SettingsRow icon={Plus} title="Add an app" caption="Search every app Memnox can connect to and sign in with your own account.">
                <ChevronRight size={14} className="text-muted" aria-hidden />
              </SettingsRow>
            </button>
          </>
        )}
        {note !== undefined && <SettingsRow icon={CircleAlert} tint="var(--mx-warm)" title="That did not work" caption={note} />}
      </SettingsCard>
      <div className="flex justify-end">
        <KitButton icon={RotateCw} onClick={() => void tools.refresh()}>
          Check again
        </KitButton>
      </div>
      {adding && <AddAppSheet apps={apps} done={() => setAdding(false)} />}
    </>
  );
}

/** One connected app: how it stands, Sign in again when it does not work, and Disconnect after asking first. */
function AppRow({ connection, apps }: { connection: ToolConnection; apps: AppConnections }) {
  const [asking, setAsking] = useState(false);
  const { busy, waitingFor } = apps.state;
  const name = toolkitName(connection.toolkit);
  const caption = asking
    ? `Disconnect ${name}? Memnox stops working in it for you until you connect it again.`
    : waitingFor === connection.toolkit
      ? 'Finish signing in in your browser'
      : connectionStatusWord(connection);
  return (
    <SettingsRow tile={<ToolMark toolkit={connection.toolkit} size={26} />} title={name} caption={caption}>
      {busy === connection.toolkit && <Spinner />}
      {asking ? (
        <>
          <KitButton onClick={() => setAsking(false)}>Cancel</KitButton>
          <KitButton
            kind="primary"
            onClick={() => {
              setAsking(false);
              void apps.disconnect(connection.toolkit);
            }}
          >
            Disconnect
          </KitButton>
        </>
      ) : (
        <>
          {!connection.connected && (
            <KitButton kind="primary" disabled={busy !== undefined} onClick={() => void apps.connect(connection.toolkit, true)}>
              Sign in again
            </KitButton>
          )}
          <KitButton disabled={busy !== undefined} onClick={() => setAsking(true)}>
            Disconnect
          </KitButton>
        </>
      )}
      <StatusDot ready={connection.connected} />
    </SettingsRow>
  );
}

/** The catalogue searched as the person types, each tool one press from its own sign in. */
function AddAppSheet({ apps, done }: { apps: AppConnections; done: () => void }) {
  const { query, found, searchNote, searching } = apps.state;
  useEffect(() => {
    apps.search(query);
    const close = (event: KeyboardEvent) => {
      if (event.key === 'Escape') done();
    };
    window.addEventListener('keydown', close);
    return () => window.removeEventListener('keydown', close);
  }, []);
  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-black/30 p-4" onClick={done}>
      <div role="dialog" aria-modal="true" aria-label="Add an app" className="flex max-h-full w-[420px] max-w-full flex-col gap-[13px] rounded-2xl bg-card p-4 shadow-[0_12px_40px_rgb(0_0_0/0.3)]" onClick={(event) => event.stopPropagation()}>
        <h3 className="text-headline font-semibold text-foreground">Add an app</h3>
        <p className="text-footnote text-muted">Pick the app and sign in to it in your browser. Nobody else has to approve it.</p>
        <SearchField value={query} placeholder="Search apps" onChange={(words) => apps.search(words)} />
        <div className="flex h-[320px] flex-col gap-1.5 overflow-y-auto px-2">
          {searchNote !== undefined ? (
            <SettingsRow icon={CircleAlert} tint="var(--mx-warm)" title="The apps are not showing" caption={searchNote} />
          ) : (
            found.length === 0 && <span className="text-footnote text-muted">{searching ? 'Looking' : 'No app by that name'}</span>
          )}
          {found.map((toolkit) => (
            <button
              key={toolkit.slug}
              type="button"
              className={`${HOVER_LIGHT} flex cursor-pointer items-center gap-3 py-1 text-left`}
              aria-label={`Connect ${toolkit.name}`}
              onClick={() => {
                void apps.connect(toolkit.slug);
                done();
              }}
            >
              <ToolMark toolkit={toolkit.slug} size={26} />
              <span className="min-w-0 flex-1 truncate text-body text-foreground">{toolkit.name}</span>
            </button>
          ))}
        </div>
        <div className="flex justify-end">
          <KitButton onClick={done}>Done</KitButton>
        </div>
      </div>
    </div>
  );
}
