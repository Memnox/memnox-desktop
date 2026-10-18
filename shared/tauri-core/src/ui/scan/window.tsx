import { StrictMode, useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import type { AgentNode } from '@memnox/core/wire';
import { WINDOW_EVENTS } from '../adapters/tauri-windows';
import { ScanScreen } from './ScanScreen';
import '../styles.css';

/** Agents the preview draws with no scan behind it: scan.html?preview=found. */
const PREVIEW_AGENTS: AgentNode[] = [
  { id: 'a1', kind: 'claude-code', name: 'Claude Code', servers: 3, reaches: ['shell', 'filesystem', 'git', 'network'], working: 2, open: 0, mcp: [{ name: 'memnox', tools: 14, changing: 3 }, { name: 'github', tools: 38, changing: 17 }, { name: 'linear', tools: 22, changing: 9 }], clis: ['gh', 'aws', 'fly'] },
  { id: 'a2', kind: 'codex', name: 'Codex', servers: 1, reaches: ['shell', 'filesystem', 'git'], working: 0, open: 1, mcp: [{ name: 'memnox', tools: 14, changing: 3 }], clis: ['gh'] },
  { id: 'a3', kind: 'cursor', name: 'Cursor', servers: 2, reaches: ['filesystem', 'browser'], working: 1, open: 0, mcp: [{ name: 'figma', tools: 9, changing: 2 }, { name: 'notion', tools: 16, changing: 6 }] },
  { id: 'a4', kind: 'gemini', name: 'Gemini CLI', servers: 0, reaches: ['shell'], working: 0, open: 0 },
  { id: 'a5', kind: 'hermes', name: 'Hermes', servers: 1, reaches: ['network', 'cloud'], working: 0, open: 0, mcp: [{ name: 'slack', tools: 12, changing: 5 }] },
];

const asked = new URLSearchParams(window.location.search);
const preview = asked.get('preview') ?? undefined;
document.documentElement.dataset.theme = 'dark';

/** The scan window, the Mac's `ScanPanel`: dark glass over the whole screen while the scan is up. */
function ScanWindow() {
  const [agents, setAgents] = useState<readonly AgentNode[] | undefined>(preview === undefined ? undefined : PREVIEW_AGENTS);
  useEffect(() => {
    if (preview !== undefined) return;
    const stop = listen<{ agents: AgentNode[] }>(WINDOW_EVENTS.scan, (event) => setAgents(event.payload.agents));
    return () => void stop.then((unlisten) => unlisten());
  }, []);
  if (agents === undefined) return null;
  return (
    <ScanScreen
      key={agents.map((agent) => agent.id).join()}
      agents={agents}
      still={preview === 'found'}
      onClose={() => {
        setAgents(undefined);
        if (preview === undefined) void invoke('scan_hide').catch(() => undefined);
      }}
    />
  );
}

const root = document.getElementById('root');
if (root === null) throw new Error('scan.html has no root');
createRoot(root).render(
  <StrictMode>
    <ScanWindow />
  </StrictMode>,
);
