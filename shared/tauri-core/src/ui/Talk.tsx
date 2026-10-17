import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { listen } from '@tauri-apps/api/event';
import { AudioLines, Download, Mic, Square, TriangleAlert } from 'lucide-react';
import type { Talking } from '../core';
import { voice, type InstallStep } from './adapters/tauri-listener';
import { button, note } from './ui';

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

  async function hear(): Promise<string | undefined> {
    setMic('listening');
    talking.listening(true);
    try {
      return await voice.listenOnce();
    } catch (error) {
      setProblem(String(error));
      return undefined;
    } finally {
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

  if (mic === 'missing' || mic === 'installing') {
    const total = step?.total ?? undefined;
    return (
      <section className="grid gap-1.5">
        <button className={`${button('quiet')} justify-self-start`} disabled={mic === 'installing'} onClick={() => void install()}>
          <Download size={14} /> {mic === 'installing' ? 'Installing the voice' : 'Install the voice'}
        </button>
        {step !== undefined && mic === 'installing' && (
          <span className="text-xs text-muted">
            {step.part}: {megabytes(step.done)}
            {total !== undefined && ` of ${megabytes(total)}`}
          </span>
        )}
        {problem !== undefined && <Problem text={problem} />}
      </section>
    );
  }

  const speaking = state.phase === 'thinking' || state.phase === 'speaking';
  return (
    <section className="grid gap-1.5">
      <div className="flex items-center gap-2.5">
        <button className={button(speaking ? 'quiet' : 'primary')} disabled={mic !== 'ready'} onClick={() => void converse()} aria-label="Talk to Memnox">
          {mic === 'listening' ? <AudioLines size={14} /> : speaking ? <Square size={12} /> : <Mic size={14} />}
          {mic === 'listening' ? 'Listening' : speaking ? 'Interrupt' : 'Talk'}
        </button>
        <span className="text-xs text-muted">or Ctrl Alt Space anywhere</span>
      </div>
      {state.heard !== undefined && <p className="text-xs text-muted">“{state.heard}”</p>}
      {state.reply !== '' && <p className="max-h-[6.5em] overflow-auto">{state.reply}</p>}
      {state.failure !== undefined && <Problem text={state.failure} />}
      {problem !== undefined && <Problem text={problem} />}
    </section>
  );
}

function Problem({ text }: { text: string }) {
  return (
    <p className={note}>
      <TriangleAlert size={13} className="mt-px shrink-0" /> {text}
    </p>
  );
}
