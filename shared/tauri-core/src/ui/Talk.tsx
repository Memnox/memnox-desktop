import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { listen } from '@tauri-apps/api/event';
import { islandTop, type NotchGeometry, type Talking, type TalkState } from '../core';
import { voice, type InstallStep } from './adapters/tauri-listener';
import { loudness } from './island/loudness';
import { IslandButton, UnderPill } from './kit';

/** Where the microphone stands: not looked at yet, not installed, installing, ready, or open. */
export type Mic = 'unknown' | 'missing' | 'installing' | 'ready' | 'listening';

const megabytes = (bytes: number): string => `${Math.round(bytes / 1_000_000)} MB`;

/** Everything the island needs from the voice: where it stands, and the presses that start it. */
export interface Conversation {
  readonly mic: Mic;
  readonly step: InstallStep | undefined;
  readonly problem: string | undefined;
  readonly state: TalkState;
  /** A turn of the person's own is under way, which puts the island in the voice or hearing mode. */
  readonly active: boolean;
  converse(): Promise<void>;
  install(): Promise<void>;
}

/**
 * The microphone as the island drives it: one press hears one thing, the reply is said, and it listens
 * again for a follow up until the person stops talking or the brain says they are done. It listens only
 * once the reply has been said, so the voice is never heard as the person. The talk key fires it from Rust.
 */
export function useConversation(talking: Talking, { probe = true }: { probe?: boolean } = {}): Conversation {
  const state = useSyncExternalStore(
    (changed) => talking.observe(changed),
    () => talking.state,
  );
  const [mic, setMic] = useState<Mic>('unknown');
  const [step, setStep] = useState<InstallStep>();
  const [problem, setProblem] = useState<string>();

  // The talk key fires from Rust; it reads the latest converse through a ref, so it never acts on an old state.
  const latest = useRef<() => Promise<void>>(async () => undefined);
  useEffect(() => {
    if (!probe) return;
    const stop = listen('talk', () => void latest.current());
    return () => void stop.then((unlisten) => unlisten(), () => undefined);
  }, [probe]);

  useEffect(() => {
    if (!probe) return;
    voice.installed().then(
      (installed) => setMic(installed ? 'ready' : 'missing'),
      () => setMic('missing'),
    );
  }, [probe]);

  async function install() {
    setMic('installing');
    setProblem(undefined);
    try {
      await voice.install(setStep);
      setMic('ready');
    } catch (error) {
      setProblem(String(error));
      setMic('missing');
    }
  }

  async function hear(): Promise<string | undefined> {
    setMic('listening');
    talking.listening(true);
    try {
      return await voice.listenOnce((level) => loudness.set(level));
    } catch (error) {
      setProblem(String(error));
      return undefined;
    } finally {
      loudness.set(0);
      talking.listening(false);
      setMic('ready');
    }
  }

  async function converse() {
    if (mic !== 'ready') return;
    if (talking.state.phase !== 'idle') await talking.interrupt();
    setProblem(undefined);
    let finished = false;
    for (;;) {
      const said = await hear();
      if (said === undefined) return;
      await talking.heard(said, finished);
      if (talking.takeEnd()) return;
      // The brain is waiting for the rest, so the next words are marked whole.
      finished = talking.takeHold();
    }
  }
  latest.current = converse;

  return { mic, step, problem, state, active: mic === 'listening' || state.phase !== 'idle', converse, install };
}

/** Where the words sit below the content top, clear of the 84 orb above them, and how much room they take. */
const WORDS = { belowTop: 104, side: 28, height: 84 } as const;

/**
 * `IslandHearing`: the words as they are heard, 17 medium centred under the orb, the newest word whole
 * and the ones before it a little dimmer, with a blue caret breathing while it listens. Once the reply
 * is being said it takes the words' place, until the voice phase brings the conversation screen.
 */
export function Hearing({ state, notch, onTap }: { state: TalkState; notch: NotchGeometry; onTap: () => void }) {
  const replying = state.phase === 'speaking' && state.reply !== '';
  const text = replying ? state.reply : (state.heard ?? '');
  const words = text.split(/\s+/).filter((word) => word !== '');
  return (
    <div className="absolute inset-0 cursor-pointer" onClick={onTap}>
      <div className="absolute flex items-end justify-center overflow-hidden" style={{ top: islandTop(notch) + WORDS.belowTop, left: WORDS.side, right: WORDS.side, height: WORDS.height }}>
        <p className="m-0 line-clamp-3 flex flex-wrap justify-center gap-x-[0.28em] gap-y-[0.15em] text-center text-title font-medium leading-[22px]">
          {words.map((word, index) => (
            <span key={`${index}-${word}`} className={`animate-[content-in_360ms_cubic-bezier(0.3,1.3,0.6,1)_both] ${replying ? 'text-white/[0.62]' : index === words.length - 1 ? 'text-white' : 'text-white/[0.78]'}`}>
              {word}
            </span>
          ))}
          {state.phase === 'listening' && <span className="ml-0.5 inline-block h-[18px] w-0.5 animate-caret self-center rounded-full bg-primary" aria-hidden />}
        </p>
      </div>
    </div>
  );
}

/**
 * What keeps the voice from working, as pills under the island: the models to install with their
 * progress, and what went wrong. The Mac installs on its own, so these are the only visible trace.
 */
export function VoicePills({ conversation }: { conversation: Conversation }) {
  const { mic, step, problem, state, install } = conversation;
  const failure = problem ?? state.failure;
  return (
    <>
      {(mic === 'missing' || mic === 'installing') && (
        <UnderPill symbol="waveform" tone="neutral">
          {mic === 'installing' && step !== undefined ? (
            <span className="tabular text-white/[0.62]">
              Installing the voice, {step.part}: {megabytes(step.done)}
              {step.total !== null && ` of ${megabytes(step.total)}`}
            </span>
          ) : (
            <>
              <span>The voice is not installed yet</span>
              <IslandButton className="!px-2.5 !py-[3px] !text-caption" disabled={mic === 'installing'} onClick={() => void install()}>
                Install
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
