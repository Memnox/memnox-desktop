import { StrictMode, useSyncExternalStore } from 'react';
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
import { hintNames, localPreferences, TauriChimes, TauriEar, TauriTypist } from './voice/tauri-voice';
import { DictationWords } from '../core/application/voice-settings';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { WebviewWindow } from '@tauri-apps/api/webviewWindow';
import { AgentQuestions, Displays, HistoryKeeper, Sessions } from '../core';
import { localHistory } from './sessions/history-store';
import { ASK_AGAIN_EVENT, TauriPresenter } from './sessions/tauri-presenter';
import { Preferences } from '../core/application/preferences';
import type { VoiceChoices } from '../core/application/voice-preferences';
import { firstName } from '../core/domain/setup-steps';
import { displayCaption, keyCaption } from '../core/domain/caption-lines';
import { platformOf } from '../core/domain/platform';
import { DAEMON_EVENT } from '@memnox/core/wire';
import type { ConfirmKey } from '../core';
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
/** Set once the talking is built, so the key's prompt and a display under way show on the island's caption line. */
let caption: (text: string | undefined) => void = () => undefined;
const platform = platformOf(navigator.userAgent);
const systemKey = new TauriConfirmKey();
/** The system's key, with the caption saying what its prompt is for while it is up, as the Mac's "Touch ID to ...". */
const key: ConfirmKey = {
  publicPoint: () => systemKey.publicPoint(),
  sign: async (message, reason) => {
    caption(keyCaption(platform, reason));
    try {
      return await systemKey.sign(message, reason);
    } finally {
      caption(undefined);
    }
  },
};
const signer = new Signer(link, key, ids, (status) => calls?.keyChanged(status));
calls = new HeldCalls(link, signer, ids, { timer });
const heldCalls: HeldCalls = calls;
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
const dictationWords = new DictationWords(localPreferences);
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
caption = (text) => talking.captioned(text);
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
  // The Dictation page's words and history, kept where Settings reads them.
  dictionary: () => {
    const words = dictationWords.words();
    return { spellings: words.filter((word) => word.said === undefined).map((word) => word.written), replacements: words.filter((word) => word.said !== undefined) };
  },
  dictated: ({ written, app }) => dictationWords.remember({ written, ...(app === undefined ? {} : { app }), at: Date.now() }),
  corrected: (corrections) => corrections.forEach(({ heard, meant }) => dictationWords.addWord(heard, meant)),
  hints: hintNames,
  // The privacy switch read before each listen, since a denied one hands the app silence and not an error.
  microphone: () => invoke<{ microphone: 'allowed' | 'denied' | 'none' | 'unknown' }>('permission_facts').then((facts) => facts.microphone),
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
calls.observeEvents((event) => {
  // "typing it in", "starting it" and the like while a display that takes a moment is carried out.
  const doing = event.kind === DAEMON_EVENT.SHOW ? displayCaption(event) : undefined;
  if (doing !== undefined) caption(doing);
  void displays.handle(event).finally(() => doing !== undefined && caption(undefined));
});
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
const openSettings = (page: string | null) => void invoke('open_settings', { page }).catch(() => undefined);

/** Whether the side panel is up, which lights the history satellite and tile; it learns of a close however the panel went. */
const side = (() => {
  let open = false;
  const listeners = new Set<() => void>();
  const set = (now: boolean) => {
    if (now === open) return;
    open = now;
    for (const listener of listeners) listener();
  };
  // The side window stays up as its tab and says when it grows out or folds back, however that happened.
  void listen<boolean>('side-state', (event) => set(event.payload));
  return {
    get open() {
      return open;
    },
    observe(listener: () => void) {
      listeners.add(listener);
      return () => void listeners.delete(listener);
    },
    /** Opens or closes the panel, as the Mac's `toggleSide`. */
    toggle() {
      const opening = !open;
      void invoke('open_side', { open: opening }).catch(() => undefined);
    },
  };
})();

async function keepWatching(held: HeldCalls): Promise<never> {
  // Memnox is installed, set up, started and brought up to date first, so the person only grants permissions.
  await setup.ensure();
  // Somebody else's key already trusted is said at launch, as the Mac's introduce does.
  await talking.introduce(await held.registerKey());
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

/** The island with the side panel's state, so the history satellite and tile light while it is up. */
function Root() {
  const sideOpen = useSyncExternalStore(
    (changed) => side.observe(changed),
    () => side.open,
  );
  return (
    <VoiceIsland
      preferences={voicePreferences}
      voice={voiceTurns}
      calls={heldCalls}
      talking={talking}
      cards={cards}
      setup={setup}
      voiceSettings={voiceSettings}
      sessions={sessions}
      questions={questions}
      onOpenSession={openLive}
      onWatchLive={openLive}
      onSide={() => side.toggle()}
      sideOpen={sideOpen}
      extras={extras}
      onSettings={() => openSettings(null)}
      launcher={{
        actions: {
          history: () => side.toggle(),
          whatHappened: () => extras.copyWhatHappened(),
          phones: () => openSettings('phones'),
          dictation: () => openSettings('dictation'),
        },
        facts: { historyOpen: sideOpen },
      }}
    />
  );
}

const root = document.getElementById('root');
if (root === null) throw new Error('index.html has no root');
createRoot(root).render(
  <StrictMode>
    <Root />
  </StrictMode>,
);
