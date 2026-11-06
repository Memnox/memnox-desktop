import { useEffect, useState } from 'react';
import type { VoiceAgentStatus } from '@memnox/core/wire';
import { Brain, RefreshCw, ShieldPlus, Volume2 } from 'lucide-react';
import type { Setup, VoiceSettings } from '../core';
import { kokoro } from './adapters/tauri-runtime';
import { IslandSettingsLines } from '../core/domain/island-settings-lines';
import { BrandLogo, IslandButton, Pressable, PRESSABLE, Radio } from './kit';
import { note } from './ui';

/** The panel's glyphs, beside caption sized words. */
const LABEL_GLYPH = 12;
const PRESS_GLYPH = 13;
const PROTECT_GLYPH = 14;
/** An agent's logo beside its name. */
const AGENT_LOGO = 18;
/** The group the agent choices share, so one pick clears the others. */
const AGENT_CHOICE = 'voice-agent';

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
          <Volume2 size={LABEL_GLYPH} /> {IslandSettingsLines.voice}
        </p>
        <div className="flex flex-wrap gap-1.5">
          {voices.map((id) => (
            <IslandButton key={id} kind={voice === id ? 'primary' : 'secondary'} onClick={() => void chooseVoice(id)}>
              {voiceName(id)}
            </IslandButton>
          ))}
        </div>
      </div>
      )}
      <div className="grid gap-1.5">
        <p className="flex items-center gap-1.5 text-xs text-muted">
          <Brain size={LABEL_GLYPH} /> {IslandSettingsLines.agent}
        </p>
        {agents.map((agent) => (
          <label key={agent.kind} className={`flex items-start gap-2 ${agent.installed ? 'cursor-pointer' : 'opacity-50'}`}>
            <Radio className="mt-1 accent-primary" name={AGENT_CHOICE} disabled={!agent.installed} checked={agent.chosen} onPick={() => void chooseAgent(agent.kind)} />
            <BrandLogo agent={agent.kind} name={agent.label} size={AGENT_LOGO} className="mt-0.5" />
            <span className="grid">
              <span>{agent.label}</span>
              {agent.because !== undefined && <span className="text-xs text-muted">{agent.because}</span>}
              {!agent.installed && <span className="text-xs text-muted">{agent.install}</span>}
            </span>
          </label>
        ))}
        <Pressable className={`${PRESSABLE} inline-flex items-center justify-center justify-self-start text-white disabled:opacity-40`} disabled={busy} onClick={() => void listAgents(true)}>
          <RefreshCw size={PRESS_GLYPH} /> {IslandSettingsLines.askAgain}
        </Pressable>
      </div>
      <IslandButton className="justify-self-start" disabled={busy} onClick={() => void protect()}>
        <ShieldPlus size={PROTECT_GLYPH} /> {IslandSettingsLines.protect}
      </IslandButton>
      {said !== undefined && <p className={note}>{said}</p>}
    </section>
  );
}
