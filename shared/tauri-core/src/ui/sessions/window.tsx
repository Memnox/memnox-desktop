import { StrictMode, useCallback, useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { invoke } from '@tauri-apps/api/core';
import { emit, emitTo, listen } from '@tauri-apps/api/event';
import { getCurrentWebviewWindow } from '@tauri-apps/api/webviewWindow';
import type { SessionCard } from '@memnox/core/wire';
import { HeldCalls, HistoryKeeper, RequestIds, Sessions, Signer, type Timer } from '../../core';
import { TauriConfirmKey } from '../adapters/tauri-confirm-key';
import { TauriDaemonLink } from '../adapters/tauri-daemon-link';
import { islandWindow } from '../adapters/tauri-island-window';
import { Board } from './Board';
import { localHistory, HISTORY_KEY } from './history-store';
import { LiveSession } from './LiveSession';
import { SIDE_TAB, SidePanel, SideTab } from './SidePanel';
import { Switcher } from './Switcher';
import { ASK_AGAIN_EVENT, DISMISS_EVENT } from './tauri-presenter';
import '../styles.css';

/**
 * The session windows' composition root: the live window, the side panel, the switcher and the card
 * wall are each this page, told which by `?view=`, each with its own link to the daemon.
 */

/** Told to an open live window when another session is asked for. */
const LIVE_SESSION_EVENT = 'live-session';
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

/** Told to the side window by Rust to open or fold, and by the side window to the island when it does. */
const SIDE_OPEN_EVENT = 'side-open';
const SIDE_STATE_EVENT = 'side-state';

/**
 * The side panel as the Mac's `SidePanel` keeps it: one window always up on the left edge, a thin tab at
 * rest that swells under the pointer and grows into the panel after a short rest there. It never takes
 * the keyboard until the search is clicked, and folds back once the pointer has left, unless pinned.
 */
function SideWindow() {
  const [calls] = useState(watchedCalls);
  const [history] = useState(() => new HistoryKeeper(localHistory, () => crypto.randomUUID()));
  const [pinned, setPinned] = useState(false);
  const [open, setOpen] = useState(false);
  const [hovering, setHovering] = useState(false);
  const [searching, setSearching] = useState(false);
  const [height, setHeight] = useState(window.innerHeight);
  const visited = useRef(false);
  useEffect(() => {
    sessions.start();
    // The island writes the history as the voice answers; this window reads it again each time it changes.
    const changed = (event: StorageEvent) => event.key === HISTORY_KEY && history.reload();
    const resized = () => setHeight(window.innerHeight);
    window.addEventListener('storage', changed);
    window.addEventListener('resize', resized);
    const asked = getCurrentWebviewWindow().listen<boolean>(SIDE_OPEN_EVENT, (event) => setOpen(event.payload));
    const dismissed = listen(DISMISS_EVENT, () => setOpen(false));
    return () => {
      sessions.stop();
      window.removeEventListener('storage', changed);
      window.removeEventListener('resize', resized);
      void asked.then((unlisten) => unlisten());
      void dismissed.then((unlisten) => unlisten());
    };
  }, [history]);
  // The island lights its history satellite and tile from this.
  useEffect(() => {
    void emitTo('island', SIDE_STATE_EVENT, open).catch(() => undefined);
    visited.current = false;
    setHovering(false);
    if (!open) {
      setSearching(false);
      islandWindow.keyboard(false);
    }
  }, [open]);
  // Clicks are taken on the tab and a little past it at rest, and on the whole panel once it is open.
  const tab = hovering ? SIDE_TAB.hovering : SIDE_TAB.resting;
  useEffect(() => {
    islandWindow.setHitAreas(
      open
        ? [{ x: 0, y: 0, width: window.innerWidth, height }]
        : [{ x: 0, y: height / 2 - tab.height / 2 - SIDE_TAB.slop, width: tab.width + SIDE_TAB.slop, height: tab.height + 2 * SIDE_TAB.slop }],
    );
  }, [open, height, tab.width, tab.height]);
  // Resting on the tab opens it, as resting on the notch opens the island.
  useEffect(() => {
    if (open || !hovering) return;
    const wait = setTimeout(() => setOpen(true), SIDE_TAB.dwellMs);
    return () => clearTimeout(wait);
  }, [open, hovering]);
  // Once the pointer has been over the open panel and left it, it folds after a short grace, unless pinned or typed in.
  const [away, setAway] = useState(false);
  useEffect(() => {
    if (!open || !away || pinned || searching) return;
    const fold = setTimeout(() => setOpen(false), SIDE_TAB.graceMs);
    return () => clearTimeout(fold);
  }, [open, away, pinned, searching]);
  useEffect(() => islandWindow.onPointer((over) => (open ? visited.current && setAway(!over) : !over && setHovering(false))), [open]);
  // A press in another app folds it unless pinned; Escape folds it once it has the keyboard.
  useEffect(() => islandWindow.onOutsidePress(() => !pinned && setOpen(false)), [pinned]);
  useEffect(() => {
    const escape = (event: KeyboardEvent) => event.key === 'Escape' && setOpen(false);
    window.addEventListener('keydown', escape);
    return () => window.removeEventListener('keydown', escape);
  }, []);
  if (!open)
    return (
      <div className="relative h-screen w-screen" onPointerEnter={() => setHovering(true)} onPointerLeave={() => setHovering(false)}>
        <SideTab hovering={hovering} />
      </div>
    );
  return (
    <div
      className="h-screen w-screen origin-left animate-[side-grow_380ms_cubic-bezier(0.3,1.2,0.5,1)_both]"
      onPointerEnter={() => {
        visited.current = true;
        setAway(false);
      }}
      onPointerLeave={() => visited.current && setAway(true)}
    >
      <SidePanel
        calls={calls}
        sessions={sessions}
        history={history}
        pinned={pinned}
        onPin={setPinned}
        onOpenSession={(card: SessionCard) => openLive(card.sessionId)}
        onAskAgain={(question) => void emit(ASK_AGAIN_EVENT, question)}
        onPick={(exchange) => islandWindow.pick(exchange.id)}
        onSearching={(on) => {
          setSearching(on);
          islandWindow.keyboard(on);
        }}
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
    // The side panel stays up as its tab and folds itself, so only the other windows close.
    if (view === 'side') return;
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
