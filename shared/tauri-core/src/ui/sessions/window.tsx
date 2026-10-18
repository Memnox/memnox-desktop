import { StrictMode, useCallback, useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { invoke } from '@tauri-apps/api/core';
import { emit, listen } from '@tauri-apps/api/event';
import { getCurrentWindow } from '@tauri-apps/api/window';
import type { SessionCard } from '@memnox/core/wire';
import { HeldCalls, HistoryKeeper, RequestIds, Sessions, Signer, type Timer } from '../../core';
import { TauriConfirmKey } from '../adapters/tauri-confirm-key';
import { TauriDaemonLink } from '../adapters/tauri-daemon-link';
import { Board } from './Board';
import { localHistory, HISTORY_KEY } from './history-store';
import { LiveSession } from './LiveSession';
import { SidePanel } from './SidePanel';
import { Switcher } from './Switcher';
import { ASK_AGAIN_EVENT, DISMISS_EVENT } from './tauri-presenter';
import '../styles.css';

/**
 * The session windows' composition root: the live window, the side panel, the switcher and the card
 * wall are each this page, told which by `?view=`, each with its own link to the daemon.
 */

/** Told to an open live window when another session is asked for. */
const LIVE_SESSION_EVENT = 'live-session';
/** The side panel waits this long after the pointer or the focus left before it closes, unless pinned. */
const SIDE_CLOSE_MS = 450;
const RECONNECT_MS = 2_000;

const timer: Timer = (ms, fire) => {
  const handle = setTimeout(fire, ms);
  return () => clearTimeout(handle);
};

const asked = new URLSearchParams(window.location.search);
const view = asked.get('view');
const link = new TauriDaemonLink();
const ids = new RequestIds();
const sessions = new Sessions(link, ids, timer);

function close(): void {
  void invoke('close_session_window').catch(() => undefined);
}

/** Held calls watched from this window too, so one can be answered where it is read, signed as from the island. */
function watchedCalls(): HeldCalls {
  let calls: HeldCalls | undefined;
  const signer = new Signer(link, new TauriConfirmKey(), ids, (status) => calls?.keyChanged(status));
  calls = new HeldCalls(link, signer, ids, { timer });
  const held = calls;
  void (async () => {
    for (;;) {
      await held.watch();
      await new Promise((resolve) => setTimeout(resolve, RECONNECT_MS));
    }
  })();
  return held;
}

function openLive(sessionId: string): void {
  void invoke('open_live_session', { sessionId }).catch(() => undefined);
}

function LiveWindow({ first }: { first: string }) {
  const [sessionId, setSessionId] = useState(first);
  const [calls] = useState(watchedCalls);
  useEffect(() => {
    const stop = listen<string>(LIVE_SESSION_EVENT, (event) => setSessionId(event.payload));
    return () => void stop.then((unlisten) => unlisten());
  }, []);
  return <LiveSession sessionId={sessionId} sessions={sessions} calls={calls} onClose={close} onOpenFolder={(path) => void invoke('open_folder', { path }).catch(() => undefined)} />;
}

function SideWindow() {
  const [calls] = useState(watchedCalls);
  const [history] = useState(() => new HistoryKeeper(localHistory, () => crypto.randomUUID()));
  const [pinned, setPinned] = useState(false);
  useEffect(() => {
    sessions.start();
    // The island writes the history as the voice answers; this window reads it again each time it changes.
    const changed = (event: StorageEvent) => event.key === HISTORY_KEY && history.reload();
    window.addEventListener('storage', changed);
    return () => {
      sessions.stop();
      window.removeEventListener('storage', changed);
    };
  }, [history]);
  // It closes a moment after the person works elsewhere, unless they pinned it open.
  useEffect(() => {
    if (pinned) return;
    let leaving: ReturnType<typeof setTimeout> | undefined;
    const stop = getCurrentWindow().onFocusChanged(({ payload: focused }) => {
      if (leaving !== undefined) clearTimeout(leaving);
      leaving = focused ? undefined : setTimeout(close, SIDE_CLOSE_MS);
    });
    const escape = (event: KeyboardEvent) => event.key === 'Escape' && close();
    window.addEventListener('keydown', escape);
    return () => {
      if (leaving !== undefined) clearTimeout(leaving);
      window.removeEventListener('keydown', escape);
      void stop.then((unlisten) => unlisten());
    };
  }, [pinned]);
  return (
    <div className="h-screen w-screen">
    <SidePanel
      calls={calls}
      sessions={sessions}
      history={history}
      pinned={pinned}
      onPin={setPinned}
      onOpenSession={(card: SessionCard) => openLive(card.sessionId)}
      onAskAgain={(question) => void emit(ASK_AGAIN_EVENT, question)}
    />
    </div>
  );
}

function SwitcherWindow({ target }: { target: string }) {
  const [cards, setCards] = useState<readonly SessionCard[]>();
  useEffect(() => {
    void sessions.list().then(setCards);
  }, []);
  const done = useCallback(() => {
    openLive(target);
    close();
  }, [target]);
  // With one session or none there is nothing to turn through, so its live window opens at once.
  useEffect(() => {
    if (cards !== undefined && cards.filter((card) => card.sessionId === target).length === 0) done();
    else if (cards !== undefined && cards.length < 2) done();
  }, [cards, target, done]);
  if (cards === undefined || cards.length < 2) return null;
  return <Switcher cards={cards} target={target} onDone={done} />;
}

function Page() {
  useEffect(() => {
    const stop = listen(DISMISS_EVENT, close);
    return () => void stop.then((unlisten) => unlisten());
  }, []);
  switch (view) {
    case 'live':
      return <LiveWindow first={asked.get('session') ?? ''} />;
    case 'side':
      return <SideWindow />;
    case 'switcher':
      return <SwitcherWindow target={asked.get('session') ?? ''} />;
    case 'board':
      return <Board sessions={sessions} title={asked.get('title') ?? 'Your sessions'} onWatch={openLive} onClose={close} />;
    default:
      return null;
  }
}

const root = document.getElementById('root');
if (root === null) throw new Error('sessions.html has no root');
createRoot(root).render(
  <StrictMode>
    <Page />
  </StrictMode>,
);
