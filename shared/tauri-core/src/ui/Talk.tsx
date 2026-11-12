import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { listen } from '@tauri-apps/api/event';
import { IDLE_TURNS, type NotchGeometry, type Talking, type TalkState, type VoiceTurns, type VoiceTurnsState } from '../core';
import { voice as models, type InstallStep } from './adapters/tauri-listener';
import { loudness } from './island/loudness';
import { IslandButton, UnderPill } from './kit';
import { IslandHearing } from './voice/Hearing';
import { voiceModels } from './voice/models';
import { keyboardHasAltGr, keysWatching, onKeys, onPresence, onSay, onVoiceLevel } from './voice/tauri-voice';
import { TalkLines } from '../core/domain/island-settings-lines';
import { TALK_EVENT } from './adapters/tauri-commands';

/** Where the microphone stands: not looked at yet, not installed, installing, ready, or open. */
export type Mic = 'unknown' | 'missing' | 'installing' | 'ready' | 'listening';

const megabytes = (bytes: number): string => `${Math.round(bytes / 1_000_000)} MB`;

/** Everything the island needs from the voice: where it stands, what it hears, and the presses that start it. */
export interface Conversation {
  readonly mic: Mic;
  readonly step: InstallStep | undefined;
  readonly problem: string | undefined;
  readonly state: TalkState;
  /** A turn of the person's own is under way, which puts the island in the voice or hearing mode. */
  readonly active: boolean;
  /** The words as they are said, and why it listens when not to talk to Memnox. */
  readonly turns: VoiceTurnsState;
  /** Why the hold keys cannot be seen on this desktop, when they cannot. */
  readonly keysNote: string | undefined;
  /** The talk key, a tap on the resting orb or on the open island: listen, or stop what is going on. */
  converse(): Promise<void>;
  install(): Promise<void>;
}

/** The facts `settle` reads from the voice, so the island opens on the words, a rule or a dictation. */
export function voiceFacts(conversation: Conversation, liveWords = true): { ruling: boolean; dictating: boolean; wordsHeard: boolean; phoneTurn: boolean } {
  const { turns } = conversation;
  // A caption such as "Testing my voice" is drawn where the words go, so it opens the same screen.
  const wordsHeard = (liveWords && turns.live !== '') || turns.caption !== undefined;
  return { ruling: turns.ruling, dictating: turns.dictating !== undefined, wordsHeard, phoneTurn: turns.phone !== undefined };
}

const NO_TURNS = { state: IDLE_TURNS, observe: () => () => undefined };

/**
 * The microphone as the island drives it, through the core's `VoiceTurns`: the talk key and a tap open
 * the orb and listen, follow ups are listened for until the brain ends it, the person can talk over the
 * voice, and right Alt and Control Alt dictate and take down a rule. The models install on their own the
 * first time, so the person only ever grants permissions.
 */
export function useConversation(talking: Talking, { probe = true, voice }: { probe?: boolean; voice?: VoiceTurns } = {}): Conversation {
  const state = useSyncExternalStore(
    (changed) => talking.observe(changed),
    () => talking.state,
  );
  const source = voice ?? NO_TURNS;
  const turns = useSyncExternalStore(
    (changed) => source.observe(changed),
    () => source.state,
  );
  const [mic, setMic] = useState<Mic>(probe ? 'unknown' : 'ready');
  const [step, setStep] = useState<InstallStep>();
  const [problem, setProblem] = useState<string>();
  const [keysNote, setKeysNote] = useState<string>();
  const keysSeen = useRef(true);

  async function install() {
    setMic('installing');
    setProblem(undefined);
    try {
      await models.install(setStep);
      voiceModels.set(true);
      setMic('ready');
      voice?.listenForName();
    } catch (error) {
      setProblem(String(error));
      setMic('missing');
    }
  }

  // The talk key fires from Rust; the keyboard and the voice's own level come from Rust as well.
  useEffect(() => {
    if (!probe || voice === undefined) return;
    voice.onLevel = (level) => loudness.set(level);
    // Settings' Say a rule asks for rule mode, which teaches the keys as the tray's does.
    const stopTalk = listen<{ intent?: string } | null>(TALK_EVENT, (event) => (event.payload?.intent === 'rule' ? voice.sayRule(keysSeen.current) : voice.talk()));
    // A line from Settings or the first run is said here, in its turn, so the mute and the echo memory hold.
    const stopSay = onSay((line) => (line === undefined ? voice.saySomething() : voice.sayInTurn(line)));
    const stopPresence = onPresence((now) => (now === 'locked' ? voice.locked() : voice.unlocked()));
    const stopKeys = onKeys((report) => voice.keys(report));
    const stopLevel = onVoiceLevel((level) => loudness.voice(level));
    void keyboardHasAltGr().then((has) => has !== undefined && voice.layout(has));
    void keysWatching().then((answer) => {
      keysSeen.current = answer.watching;
      setKeysNote(answer.watching ? undefined : answer.why);
    });
    return () => {
      voice.onLevel = undefined;
      void stopTalk.then((unlisten) => unlisten(), () => undefined);
      stopKeys();
      stopLevel();
      stopSay();
      stopPresence();
    };
  }, [probe, voice]);

  // Installed in the background on first launch, as the Mac installs Kokoro, so nothing waits on a press.
  useEffect(() => {
    if (!probe) return;
    let cancelled = false;
    models.installed().then(
      (installed) => {
        if (cancelled) return;
        voiceModels.set(installed);
        if (installed) {
          setMic('ready');
          voice?.listenForName();
        } else void install();
      },
      () => !cancelled && setMic('missing'),
    );
    return () => {
      cancelled = true;
    };
  }, [probe, voice]);

  const listening = turns.listening ? 'listening' : mic;
  return {
    mic: listening,
    step,
    problem: problem ?? turns.problem,
    state,
    active: turns.active || state.phase !== 'idle',
    turns,
    keysNote,
    converse: async () => voice?.talk(),
    install,
  };
}

/**
 * `IslandHearing` for the island: the person's words as they say them under the orb, or the hint and
 * the chip while a rule or a dictation is taken down. The preview passes words of its own in `state`.
 */
export function Hearing({ state, notch, onTap, conversation }: { state: TalkState; notch: NotchGeometry; onTap: () => void; conversation?: Conversation }) {
  const turns = conversation?.turns;
  const view =
    turns !== undefined && (turns.active || turns.live !== '')
      ? { live: turns.live, listening: turns.listening, ruling: turns.ruling, dictating: turns.dictating, caption: turns.caption }
      : { live: state.heard ?? '', listening: state.phase === 'listening', ruling: false, dictating: undefined };
  return <IslandHearing view={view} notch={notch} onTap={onTap} />;
}

/**
 * What keeps the voice from working, as pills under the island: the models installing with their
 * progress, and what went wrong. The Mac installs on its own, so these are the only visible trace of it.
 */
export function VoicePills({ conversation, starting = false }: { conversation: Conversation; starting?: boolean }) {
  const { mic, step, problem, state, install } = conversation;
  // While the service is still starting, the pill above already says so, and a turn it could not take is no fault.
  const failure = problem ?? (starting ? undefined : state.failure);
  return (
    <>
      {(mic === 'missing' || mic === 'installing') && (
        <UnderPill symbol="waveform" tone="neutral">
          {mic === 'installing' && step !== undefined ? (
            <span className="tabular text-white/[0.62]">
              {TalkLines.installingStep(step.part, megabytes(step.done))}
              {step.total !== null && TalkLines.ofTotal(megabytes(step.total))}
            </span>
          ) : mic === 'installing' ? (
            <span className="text-white/[0.62]">{TalkLines.installing}</span>
          ) : (
            <>
              <span>{TalkLines.notInstalled}</span>
              <IslandButton onClick={() => void install()}>
                {TalkLines.tryAgain}
              </IslandButton>
            </>
          )}
        </UnderPill>
      )}
      {failure !== undefined && (
        <UnderPill symbol="exclamationmark.triangle.fill" tone="red">
          {failure}
        </UnderPill>
      )}
    </>
  );
}
