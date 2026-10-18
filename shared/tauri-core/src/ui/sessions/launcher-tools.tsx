import { useEffect, useState, useSyncExternalStore } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { RequestIds, toolkitName } from '../../core';
import { agentStatusWord, connectionStatusWord, Tools } from '../../core/application/tools';
import { TauriDaemonLink } from '../adapters/tauri-daemon-link';
import { AgentMark, ToolMark } from '../kit';
import type { LauncherTool } from './Launcher';

/** Said under the grid while no app is connected. */
const NO_APPS = 'No apps connected yet. Ask Memnox to do something in Gmail, Slack or GitHub and it opens the sign in for you.';

/** A connected app picked on the Tools page, which opens it up close. */
export interface PickedTool {
  readonly toolkit: string;
  readonly connected: boolean;
}

/** The launcher's own read of the agents and apps, made once, so the island needs nothing more passed in. */
let shared: Tools | undefined;
function tools(): Tools {
  shared ??= new Tools(new TauriDaemonLink(), new RequestIds());
  return shared;
}

/**
 * The Tools page's tiles, as the Mac's `ToolsModel` gives the grid: one per agent with how it stands, then
 * one per connected app, which opens that app up close. Read again each time the page opens, since either
 * list changes without telling. Off, as in the preview, it reads nothing.
 */
export function useLauncherTools(on: boolean, onPick: (tool: PickedTool) => void): { tiles: LauncherTool[]; note: string | undefined; caption: string } {
  const source = on ? tools() : undefined;
  const state = useSyncExternalStore(
    (changed) => source?.observe(changed) ?? (() => undefined),
    () => source?.state,
  );
  const [asked, setAsked] = useState(false);
  useEffect(() => {
    if (source === undefined || asked) return;
    setAsked(true);
    void source.refresh();
  }, [source, asked]);
  if (state === undefined) return { tiles: [], note: undefined, caption: 'None yet' };
  const tiles: LauncherTool[] = [
    ...state.agents.map((agent) => ({
      id: `agent:${agent.kind}`,
      title: agent.label,
      caption: agentStatusWord(agent),
      mark: <AgentMark agent={agent.kind} name={agent.label} size={25} />,
      // An agent's own settings live on the Connected tools page, where it can be made the voice.
      onPress: () => void invoke('open_settings', { page: 'tools' }).catch(() => undefined),
    })),
    ...state.connections.map((app) => ({
      id: `app:${app.toolkit}`,
      title: toolkitName(app.toolkit),
      caption: connectionStatusWord(app),
      mark: <ToolMark toolkit={app.toolkit} size={25} />,
      onPress: () => onPick({ toolkit: app.toolkit, connected: app.connected }),
    })),
  ];
  const connected = state.connections.filter((app) => app.connected).length;
  const caption = state.reading ? 'Reading' : connected === 0 ? 'None yet' : `${connected} connected`;
  return { tiles, note: state.connections.length === 0 ? (state.connectionsNote ?? NO_APPS) : undefined, caption };
}
