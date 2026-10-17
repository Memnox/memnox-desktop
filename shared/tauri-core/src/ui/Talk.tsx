import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { listen } from '@tauri-apps/api/event';
import type { Talking } from '../core';
import { voice, type InstallStep } from './adapters/tauri-listener';

type Mic = 'unknown' | 'missing' | 'installing' | 'ready' | 'listening';

const megabytes = (bytes: number): string => `${Math.round(bytes / 1_000_000)} MB`;

/**
 * The microphone: one press hears one thing, the reply is said, and it listens again for a follow up
 * until the person stops talking or the brain says they are done. It listens only once the reply has
 * been said, so the voice is never heard as the person.
 */
export function Talk({ talking }: { talking: Talking }) {
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
    const stop = listen('talk', () => void latest.current());
    return () => void stop.then((unlisten) => unlisten());
  }, []);

  useEffect(() => {
    voice.installed().then((installed) => setMic(installed ? 'ready' : 'missing'), () => setMic('missing'));
  }, []);

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

  async function converse() {
    if (mic === 'listening' || mic === 'missing' || mic === 'installing' || mic === 'unknown') return;
    if (talking.state.phase !== 'idle') await talking.interrupt();
    setProblem(undefined);
    let finished = false;
    for (;;) {
      setMic('listening');
      const said = await voice.listenOnce().catch((error: unknown) => {
        setProblem(String(error));
        return undefined;
      });
      setMic('ready');
      if (said === undefined) return;
      await talking.heard(said, finished);
      if (talking.takeEnd()) return;
      // The brain is waiting for the rest, so the next words are marked whole.
      finished = talking.takeHold();
    }
  }

  latest.current = converse;

  if (mic === 'missing' || mic === 'installing') {
    const total = step?.total ?? undefined;
    return (
      <section className="talk">
        <button disabled={mic === 'installing'} onClick={() => void install()}>
          {mic === 'installing' ? 'Installing the voice…' : 'Install the voice'}
        </button>
        {step !== undefined && mic === 'installing' && (
          <span className="progress">
            {step.part}: {megabytes(step.done)}
            {total !== undefined && ` of ${megabytes(total)}`}
          </span>
        )}
        {problem !== undefined && <p className="note">{problem}</p>}
      </section>
    );
  }

  return (
    <section className="talk">
      <button className="mic" disabled={mic !== 'ready'} onClick={() => void converse()} aria-label="Talk to Memnox">
        {mic === 'listening' ? 'Listening…' : state.phase === 'idle' ? 'Talk' : 'Interrupt'}
      </button>
      <span className="progress">or press Ctrl Alt Space anywhere</span>
      {state.heard !== undefined && <p className="heard">“{state.heard}”</p>}
      {state.reply !== '' && <p className="reply">{state.reply}</p>}
      {state.failure !== undefined && <p className="note">{state.failure}</p>}
      {problem !== undefined && <p className="note">{problem}</p>}
    </section>
  );
}
