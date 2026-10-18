import { StrictMode, useEffect, useLayoutEffect, useRef, useState, useSyncExternalStore } from 'react';
import { createRoot } from 'react-dom/client';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { RequestIds } from '../../core';
import { Tools } from '../../core/application/tools';
import type { MenuAction, ToolChip } from '../../core/domain/menu-panel';
import { TauriDaemonLink } from '../adapters/tauri-daemon-link';
import { WINDOW_EVENTS, type IslandStatus } from '../adapters/tauri-windows';
import { TrayPanel, type TrayPanelState } from './TrayPanel';
import '../styles.css';
import '../cards/floating/floating.css';

/** How the talk key reads here, until the island says otherwise. */
const TALK_KEYS = ['Ctrl', 'Alt', 'Space'];
/** The room around the panel for its shadow, which the window keeps transparent. */
const MARGIN = 12;

const asked = new URLSearchParams(window.location.search);
const preview = asked.get('preview') ?? undefined;
if (asked.get('theme') === 'light' || asked.get('theme') === 'dark') document.documentElement.dataset.theme = asked.get('theme') ?? undefined;

/** The chips the preview draws with no daemon. */
const PREVIEW_CHIPS: ToolChip[] = [
  { id: 'agent:claude-code', kind: 'agent', key: 'claude-code', name: 'Claude Code', ready: true },
  { id: 'agent:codex', kind: 'agent', key: 'codex', name: 'Codex', ready: false },
  { id: 'app:slack', kind: 'app', key: 'slack', name: 'Slack', ready: true },
  { id: 'app:github', kind: 'app', key: 'github', name: 'GitHub', ready: true },
  { id: 'app:gmail', kind: 'app', key: 'gmail', name: 'Gmail', ready: false },
];

function previewState(scene: string): TrayPanelState {
  switch (scene) {
    case 'reading':
      return { muted: false, wakesByName: false, talkKeys: TALK_KEYS, chips: [], reading: true, failed: undefined };
    case 'muted':
      return { muted: true, wakesByName: true, talkKeys: TALK_KEYS, chips: PREVIEW_CHIPS, reading: false, failed: undefined };
    default:
      return { muted: false, wakesByName: false, talkKeys: TALK_KEYS, chips: PREVIEW_CHIPS, reading: false, failed: undefined };
  }
}

if (preview === undefined) document.documentElement.dataset.solid = '';

const tools = preview === undefined ? new Tools(new TauriDaemonLink(), new RequestIds()) : undefined;

/**
 * The tray panel's window: Rust shows it beside the tray icon and hides it on a click outside or Escape;
 * each time it opens, the agents and apps are read again and the island says whether the voice is muted.
 */
function TrayWindow() {
  const [opened, setOpened] = useState(0);
  const [status, setStatus] = useState<IslandStatus>({ muted: false, wakesByName: false, talkKeys: TALK_KEYS });
  const toolsState = useSyncExternalStore(
    (changed) => tools?.observe(changed) ?? (() => undefined),
    () => tools?.state,
  );
  const holder = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (preview !== undefined) return;
    const opens = listen(WINDOW_EVENTS.menuOpened, () => {
      setOpened((count) => count + 1);
      void tools?.refresh();
    });
    const told = listen<IslandStatus>(WINDOW_EVENTS.islandStatus, (event) => setStatus(event.payload));
    const escape = (event: KeyboardEvent) => event.key === 'Escape' && void invoke('tray_panel_hide').catch(() => undefined);
    window.addEventListener('keydown', escape);
    void tools?.refresh();
    return () => {
      void opens.then((stop) => stop());
      void told.then((stop) => stop());
      window.removeEventListener('keydown', escape);
    };
  }, []);

  // The window hugs the panel, which changes height with the strip's note and the rows.
  useLayoutEffect(() => {
    const element = holder.current;
    if (element === null || preview !== undefined) return;
    const fit = () => {
      const box = element.getBoundingClientRect();
      void invoke('tray_panel_fit', { width: Math.ceil(box.width) + 2 * MARGIN, height: Math.ceil(box.height) + 2 * MARGIN }).catch(() => undefined);
    };
    const watcher = new ResizeObserver(fit);
    watcher.observe(element);
    return () => watcher.disconnect();
  }, []);

  const state: TrayPanelState =
    preview !== undefined
      ? previewState(preview)
      : {
          ...status,
          chips: tools?.chips ?? [],
          reading: toolsState?.reading ?? true,
          failed: toolsState?.connectionsNote,
        };

  function act(action: MenuAction) {
    if (preview !== undefined) return;
    if (action === 'mute') setStatus((now) => ({ ...now, muted: !now.muted }));
    void invoke('tray_action', { action }).catch(() => undefined);
  }

  return (
    <div style={{ padding: MARGIN, display: 'inline-block' }}>
      <div ref={holder}>
        <TrayPanel state={state} opened={opened} onAction={act} online={preview === undefined} />
      </div>
    </div>
  );
}


const root = document.getElementById('root');
if (root === null) throw new Error('tray.html has no root');
createRoot(root).render(
  <StrictMode>
    <TrayWindow />
  </StrictMode>,
);
