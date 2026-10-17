import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import type { DaemonEvent, DaemonRequest, DaemonResponse } from '@memnox/core/wire';
import { HeldCalls, ProposalCards, RequestIds, Setup, Signer, Talking, VoiceSettings, type ConfirmKey, type DaemonLink, type Runtime, type Speaker } from '../core';
import { Island } from './Island';
import './styles.css';

/**
 * The island as a designer sees it, in a browser with no Tauri and no daemon: `pnpm dev`, then open
 * /preview.html. A scripted daemon holds one call and a rule waits on its card.
 */
/** `/preview.html?settings` opens on the settings with nothing waiting. */
const settingsView = new URLSearchParams(window.location.search).has('settings');

const held: DaemonEvent = {
  kind: 'held',
  subject: 'hld_preview',
  agent: 'codex',
  agentName: 'Codex',
  summary: 'Codex wants to push to main',
  what: 'push to main',
  why: 'It reaches past its repository.',
  place: 'memnox-web',
  at: new Date().toISOString(),
};

const link: DaemonLink = {
  async *stream(request: DaemonRequest): AsyncIterable<DaemonResponse> {
    if (request.method === 'waiting') yield { id: request.id, ok: true, waiting: settingsView ? [] : [held] };
    else if (request.method === 'voice-agents')
      yield {
        id: request.id,
        ok: true,
        voiceAgents: [
          { kind: 'claude-code', label: 'Claude Code', installed: true, sealed: true, works: true, chosen: true, install: '' },
          { kind: 'codex', label: 'Codex', installed: true, sealed: true, works: false, because: 'It did not call a Memnox tool when asked.', chosen: false, install: '' },
          { kind: 'cursor', label: 'Cursor', installed: false, sealed: true, chosen: false, install: 'Install the Cursor CLI: curl https://cursor.com/install -fsS | bash' },
        ],
      };
    else if (request.method === 'subscribe') {
      yield { id: request.id, ok: true };
      await new Promise(() => undefined);
    } else yield { id: request.id, ok: true };
  },
};
const key: ConfirmKey = { publicPoint: async () => undefined, sign: async () => undefined };
const speaker: Speaker = { queue: () => undefined, drained: async () => undefined, stop: () => undefined };

const ids = new RequestIds();
const signer = new Signer(link, key, ids);
const calls = new HeldCalls(link, signer, ids);
const cards = new ProposalCards(link, signer, speaker, ids);
const talking = new Talking(link, speaker, signer, ids, { timer: () => () => undefined, cards });
const runtime: Runtime = { found: async () => true, install: async () => true, wired: async () => true, run: async () => true };
const setup = new Setup(link, runtime, ids, async () => undefined);
const voiceSettings = new VoiceSettings(link, ids);
void calls.watch();
if (!settingsView) cards.show({
  ...held,
  kind: 'proposal',
  subject: 'prp_preview',
  rule: {
    summary: 'Deny git push to main',
    effect: 'deny',
    action: 'git.push',
    reason: 'You asked for every push to main to stop here.',
    scopes: [
      { id: 'machine', kind: 'machine', label: 'This computer' },
      { id: 'repo', kind: 'repository', label: 'memnox-web', suggested: true },
    ],
  },
});

const root = document.getElementById('root');
if (root === null) throw new Error('preview.html has no root');
createRoot(root).render(
  <StrictMode>
    <div style={{ paddingTop: 12 }}>
      <Island calls={calls} talking={talking} cards={cards} setup={setup} voiceSettings={voiceSettings} settingsOpen={settingsView} />
    </div>
  </StrictMode>,
);
