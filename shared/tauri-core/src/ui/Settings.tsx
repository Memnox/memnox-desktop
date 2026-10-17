import { useEffect, useState } from 'react';
import type { VoiceAgentStatus } from '@memnox/core/wire';
import { Brain, RefreshCw, ShieldPlus, Volume2 } from 'lucide-react';
import type { Setup, VoiceSettings } from '../core';
import { kokoro } from './adapters/tauri-runtime';
import { button, note } from './ui';

/** "af_sky" as "Sky", the way the Mac's voice menu names them. */
const voiceName = (id: string): string => {
  const name = id.split('_')[1] ?? id;
  return name.charAt(0).toUpperCase() + name.slice(1);
};

const MAC_DEFAULT_VOICE = 'af_sky';

/** Settings: the voice it speaks in, the agent it thinks with, and putting the agents here under Memnox. */
export function Settings({ voiceSettings, setup }: { voiceSettings: VoiceSettings; setup: Setup }) {
  const [voices, setVoices] = useState<string[]>([]);
  const [voice, setVoice] = useState<string>();
  const [agents, setAgents] = useState<readonly VoiceAgentStatus[]>([]);
  const [said, setSaid] = useState<string>();
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    kokoro.choice().then(
      (choice) => {
        setVoices(choice.voices);
        setVoice(choice.chosen ?? MAC_DEFAULT_VOICE);
      },
      () => undefined,
    );
    void listAgents(false);
  }, []);

  async function listAgents(recheck: boolean) {
    setBusy(true);
    const answer = await voiceSettings.agents(recheck);
    if (answer.kind === 'listed') setAgents(answer.agents);
    setSaid(answer.kind === 'failed' ? answer.why : undefined);
    setBusy(false);
  }

  async function chooseAgent(kind: string) {
    const answer = await voiceSettings.choose(kind);
    if (answer.kind === 'listed') setAgents(answer.agents);
    setSaid(answer.kind === 'failed' ? answer.why : undefined);
  }

  async function chooseVoice(id: string) {
    setVoice(id);
    await kokoro.choose(id).catch((error: unknown) => setSaid(String(error)));
  }

  async function protect() {
    setBusy(true);
    setSaid(await setup.protectAgents());
    setBusy(false);
  }

  return (
    <section className="grid gap-3 border-t border-line pt-2.5">
      {voices.length > 0 && (
      <div className="grid gap-1.5">
        <p className="flex items-center gap-1.5 text-xs text-muted">
          <Volume2 size={12} /> The voice it speaks in
        </p>
        <div className="flex flex-wrap gap-1.5">
          {voices.map((id) => (
            <button key={id} className={button(voice === id ? 'primary' : 'quiet')} onClick={() => void chooseVoice(id)}>
              {voiceName(id)}
            </button>
          ))}
        </div>
      </div>
      )}
      <div className="grid gap-1.5">
        <p className="flex items-center gap-1.5 text-xs text-muted">
          <Brain size={12} /> The agent it thinks with
        </p>
        {agents.map((agent) => (
          <label key={agent.kind} className={`flex items-start gap-2 ${agent.installed ? 'cursor-pointer' : 'opacity-50'}`}>
            <input
              type="radio"
              className="mt-1 accent-primary"
              name="voice-agent"
              disabled={!agent.installed}
              checked={agent.chosen}
              onChange={() => void chooseAgent(agent.kind)}
            />
            <span className="grid">
              <span>{agent.label}</span>
              {agent.because !== undefined && <span className="text-xs text-muted">{agent.because}</span>}
              {!agent.installed && <span className="text-xs text-muted">{agent.install}</span>}
            </span>
          </label>
        ))}
        <button className={`${button('icon')} justify-self-start`} disabled={busy} onClick={() => void listAgents(true)}>
          <RefreshCw size={13} /> Ask each agent again
        </button>
      </div>
      <button className={`${button('quiet')} justify-self-start`} disabled={busy} onClick={() => void protect()}>
        <ShieldPlus size={14} /> Put my agents under Memnox
      </button>
      {said !== undefined && <p className={note}>{said}</p>}
    </section>
  );
}
