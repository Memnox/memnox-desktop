import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { HeldCalls, RequestIds, Signer, Talking, Wakefulness, type Timer } from '../core';
import { TauriConfirmKey } from './adapters/tauri-confirm-key';
import { TauriDaemonLink } from './adapters/tauri-daemon-link';
import { TauriPower } from './adapters/tauri-power';
import { TauriSpeaker } from './adapters/tauri-speaker';
import { Island } from './Island';
import './island.css';

/** How long after the daemon closes the feed before it is opened again, long enough for a restart to finish. */
const RECONNECT_MS = 2_000;
/** How often the phones and the charger are checked, since either changes without telling the app. */
const AWAKE_CHECK_MS = 60_000;

const timer: Timer = (ms, fire) => {
  const handle = setTimeout(fire, ms);
  return () => clearTimeout(handle);
};

/** The composition root: the one place the Tauri adapters meet the core. */
const ids = new RequestIds();
const link = new TauriDaemonLink();
let calls: HeldCalls | undefined;
const signer = new Signer(link, new TauriConfirmKey(), ids, (status) => calls?.keyChanged(status));
calls = new HeldCalls(link, signer, ids);
const talking = new Talking(link, new TauriSpeaker(), signer, ids, { timer });
const wakefulness = new Wakefulness(link, new TauriPower(), ids);
calls.observeEvents((event) => void talking.handle(event));

async function keepWatching(held: HeldCalls): Promise<never> {
  await held.registerKey();
  for (;;) {
    await held.watch();
    await new Promise((resolve) => setTimeout(resolve, RECONNECT_MS));
  }
}

void keepWatching(calls);
void wakefulness.check();
setInterval(() => void wakefulness.check(), AWAKE_CHECK_MS);

const root = document.getElementById('root');
if (root === null) throw new Error('index.html has no root');
createRoot(root).render(
  <StrictMode>
    <Island calls={calls} talking={talking} />
  </StrictMode>,
);
