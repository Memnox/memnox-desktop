import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { HeldCalls, ProposalCards, RequestIds, Setup, Signer, Talking, VoiceSettings, Wakefulness, type Timer } from '../core';
import { TauriConfirmKey } from './adapters/tauri-confirm-key';
import { TauriDaemonLink } from './adapters/tauri-daemon-link';
import { TauriPower } from './adapters/tauri-power';
import { TauriRuntime } from './adapters/tauri-runtime';
import { TauriSpeaker } from './adapters/tauri-speaker';
import { islandExtras } from './tray/island-extras';
import { DictationPolish, Mouth, VoicePreferences, VoiceTurns } from '../core';
import { VoiceIsland } from './voice/VoiceIsland';
import { voiceModels } from './voice/models';
import { localPreferences, TauriChimes, TauriEar, TauriTypist } from './voice/tauri-voice';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { AgentQuestions, Displays, HistoryKeeper, Sessions } from '../core';
import { localHistory } from './sessions/history-store';
import { ASK_AGAIN_EVENT, TauriPresenter } from './sessions/tauri-presenter';
import { Preferences } from '../core/application/preferences';
import type { VoiceChoices } from '../core/application/voice-preferences';
import { firstName } from '../core/domain/setup-steps';
import './styles.css';

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
calls = new HeldCalls(link, signer, ids, { timer });
// The voice: Kokoro behind a mouth that remembers what it said and honours the mute, the ear, the keys and the typist.
const voicePreferences = new VoicePreferences(localPreferences);
// Settings writes the switches in its own window, so a change there reaches this copy of them.
window.addEventListener('storage', (event) => {
  const key = event.key?.startsWith('memnox.voice.') === true ? (event.key.slice('memnox.voice.'.length) as keyof VoiceChoices) : undefined;
  if (key !== undefined && key in voicePreferences.choices && (event.newValue === 'true' || event.newValue === 'false')) voicePreferences.set(key, event.newValue === 'true');
});
// The person's own choices, kept by Settings and the first run: their name, and whether the first run is done.
const personal = new Preferences(localPreferences);
const speaker = new Mouth(new TauriSpeaker(), voicePreferences);
const chimes = new TauriChimes();
const typist = new TauriTypist();
const cards = new ProposalCards(link, signer, speaker, ids);
const talking = new Talking(link, speaker, signer, ids, {
  timer,
  cards,
  chimes: { play: (cue) => voicePreferences.choices.chimes && chimes.play(cue) },
  lookingAt: () => typist.focus(),
  owner: () => firstName(personal.name),
});
const voiceTurns = new VoiceTurns({
  talking,
  mouth: speaker,
  ear: new TauriEar(),
  preferences: voicePreferences,
  timer,
  chimes,
  typist,
  polish: new DictationPolish(link, ids, timer),
  ready: () => voiceModels.installed,
});
const wakefulness = new Wakefulness(link, new TauriPower(), ids);
const setup = new Setup(link, new TauriRuntime(), ids, (ms) => new Promise((resolve) => setTimeout(resolve, ms)));
const voiceSettings = new VoiceSettings(link, ids);
// What waits on the person is said in its turn and listened for; the rest goes straight to the talking.
calls.observeEvents((event) => voiceTurns.arrived(event));
// The sessions, an agent's own questions, what the daemon asks to show, and every question asked kept.
const sessions = new Sessions(link, ids, timer);
const questions = new AgentQuestions(link, ids, timer, (subject) => talking.answeredByHand(subject));
const displays = new Displays(link, ids, new TauriPresenter());
calls.observeEvents((event) => void displays.handle(event));
const history = new HistoryKeeper(localHistory, () => crypto.randomUUID());
history.follow(talking);
// The tray panel's rows, the pills under the island, the chimes for answers by hand and the diary.
const extras = islandExtras({
  calls,
  talking,
  timer,
  chimes: { play: (cue) => voicePreferences.choices.chimes && chimes.play(cue) },
  mute: () => ({ on: voicePreferences.choices.muted, toggle: () => voicePreferences.toggle('muted') }),
  sayRule: () => voiceTurns.sayRule(),
  wakesByName: () => voicePreferences.choices.wake,
});
sessions.start();
void listen<string>(ASK_AGAIN_EVENT, (event) => void talking.heard(event.payload, true));
const openLive = (sessionId: string) => void invoke('open_live_session', { sessionId }).catch(() => undefined);

async function keepWatching(held: HeldCalls): Promise<never> {
  // Memnox is installed, set up, started and brought up to date first, so the person only grants permissions.
  await setup.ensure();
  await held.registerKey();
  for (;;) {
    await held.watch();
    await new Promise((resolve) => setTimeout(resolve, RECONNECT_MS));
  }
}

void keepWatching(calls);
// A first launch opens the first run in its own window; after it, Settings is one press on the island away.
if (!personal.setupDone) void invoke('open_onboarding').catch(() => undefined);
void wakefulness.check();
setInterval(() => void wakefulness.check(), AWAKE_CHECK_MS);

const root = document.getElementById('root');
if (root === null) throw new Error('index.html has no root');
createRoot(root).render(
  <StrictMode>
    <VoiceIsland
      preferences={voicePreferences}
      voice={voiceTurns}
      calls={calls}
      talking={talking}
      cards={cards}
      setup={setup}
      voiceSettings={voiceSettings}
      sessions={sessions}
      questions={questions}
      onOpenSession={openLive}
      onWatchLive={openLive}
      onSide={() => void invoke('open_side', { open: true }).catch(() => undefined)}
      extras={extras}
      onSettings={() => void invoke('open_settings', { page: null }).catch(() => undefined)}
    />
  </StrictMode>,
);
