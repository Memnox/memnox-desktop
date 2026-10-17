import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { HeldCalls, RequestIds, Wakefulness } from '../core';
import { TauriConfirmKey } from './adapters/tauri-confirm-key';
import { TauriDaemonLink } from './adapters/tauri-daemon-link';
import { TauriPower } from './adapters/tauri-power';
import { Island } from './Island';
import './island.css';

/** How long after the daemon closes the feed before it is opened again, long enough for a restart to finish. */
const RECONNECT_MS = 2_000;
/** How often the phones and the charger are checked, since either changes without telling the app. */
const AWAKE_CHECK_MS = 60_000;

/** The composition root: the one place the Tauri adapters meet the core. */
const ids = new RequestIds();
const link = new TauriDaemonLink();
const calls = new HeldCalls(link, new TauriConfirmKey(), ids);
const wakefulness = new Wakefulness(link, new TauriPower(), ids);

async function keepWatching(): Promise<never> {
  await calls.registerKey();
  for (;;) {
    await calls.watch();
    await new Promise((resolve) => setTimeout(resolve, RECONNECT_MS));
  }
}

void keepWatching();
void wakefulness.check();
setInterval(() => void wakefulness.check(), AWAKE_CHECK_MS);

const root = document.getElementById('root');
if (root === null) throw new Error('index.html has no root');
createRoot(root).render(
  <StrictMode>
    <Island calls={calls} />
  </StrictMode>,
);
