import { ArrowRight, Bell, ChevronsUpDown, CircleMinus, Ear, Keyboard, MessageSquareText, MicVocal, Play, Sparkles, TextCursorInput, Volume1, VolumeX } from 'lucide-react';
import { Fragment, useEffect, useState } from 'react';
import type { VoiceChoices } from '../../../core/application/voice-preferences';
import { AgentCheckText } from '../../../core/domain/agent-check-text';
import { firstName, voiceDetail, voiceStep } from '../../../core/domain/setup-steps';
import { BrandLogo } from '../../kit/logos';
import { KitButton, KitField, QuietLine, SettingsCard, SettingsDivider, SettingsSection, Spinner, Surface, SwitchRow, useCopied } from '../kit';
import { useObserved, usePreferences, type SettingsParts } from '../parts';
import { SetupDivider, SetupStep } from '../steps';

/** "af_sky" as "Sky", with who it sounds like, as the Mac's voice menu names them. */
const VOICE_PEOPLE: Record<string, string> = {
  af: 'American Female',
  am: 'American Male',
  bf: 'British Female',
  bm: 'British Male',
};

export function voiceLabel(id: string): string {
  const [accent, name] = id.split('_');
  const named = name === undefined ? id : name.charAt(0).toUpperCase() + name.slice(1);
  const who = accent === undefined ? undefined : VOICE_PEOPLE[accent];
  return who === undefined ? named : `${named} (${who})`;
}

/** The Voice page, as the Mac's `SetupVoiceCard`: who thinks for the voice, then the voice it answers in. */
export function VoicePage({ parts }: { parts: SettingsParts }) {
  const { steps } = parts;
  useObserved(steps);
  useEffect(() => void steps.refresh(), []);
  return (
    <Surface>
      <AgentsStep parts={parts} />
      <SetupDivider />
      <VoiceStep parts={parts} />
    </Surface>
  );
}

/** "Who answers for you", with each agent and Use, folded away once one answers. */
function AgentsStep({ parts }: { parts: SettingsParts }) {
  const { steps } = parts;
  const [shown, setShown] = useState(false);
  const state = steps.agentsState;
  const done = state.kind === 'done';
  const installed = steps.agents.filter((agent) => agent.installed);
  const missing = steps.agents.filter((agent) => !agent.installed).map((agent) => agent.label);
  return (
    <SetupStep
      state={state}
      title="Who answers for you"
      detail={steps.agentsDetail}
      trailing={done ? <KitButton onClick={() => setShown(!shown)}>{shown ? 'Hide agents' : 'Show agents'}</KitButton> : undefined}
      extra={
        !done || shown ? (
          <div className="flex flex-col gap-2">
            {installed.map((agent) => (
              <div key={agent.kind} className="flex items-center gap-2">
                <BrandLogo agent={agent.kind} name={agent.label} size={24} />
                <span className="w-[84px] shrink-0 truncate text-caption font-semibold text-foreground">{agent.label}</span>
                <span className={`min-w-0 flex-1 truncate text-caption ${agent.works === false ? 'text-ink-primary' : 'text-ink-secondary'}`} title={AgentCheckText.status(agent, steps.checkingAgents)}>
                  {AgentCheckText.status(agent, steps.checkingAgents)}
                </span>
                {agent.chosen ? (
                  <span className="text-caption font-semibold text-green">In use</span>
                ) : (
                  <KitButton disabled={agent.works === false} onClick={() => void steps.useAgent(agent.kind)}>
                    Use
                  </KitButton>
                )}
              </div>
            ))}
            {missing.length > 0 && <p className="text-caption text-muted">Also answers through {AgentCheckText.names(missing)} once installed and logged in.</p>}
            <div className="flex items-center gap-2">
              <KitButton disabled={steps.checkingAgents} onClick={() => void steps.loadAgents(true)}>
                Check again
              </KitButton>
              {steps.checkingAgents && <Spinner />}
            </div>
          </div>
        ) : undefined
      }
    />
  );
}

/** "Voice": the picker and Hear it, the download while it comes, and Try again when it failed. */
function VoiceStep({ parts }: { parts: SettingsParts }) {
  const { steps, host, preferences, voiceSettings } = parts;
  const [voices, setVoices] = useState<string[]>([]);
  const [chosen, setChosen] = useState<string>('af_sky');
  useEffect(() => {
    host.voices.choice().then(
      (choice) => {
        setVoices(choice.voices);
        if (choice.chosen !== null) setChosen(choice.chosen);
      },
      () => undefined,
    );
  }, []);
  const install = steps.voiceInstall;
  const pick = (id: string) => {
    setChosen(id);
    // The phone hears the pick too, and once the natural voice is in it says one line so the choice is heard.
    void host.voices
      .choose(id)
      .then(() => voiceSettings.tellVoice(id))
      .then(() => (install.kind === 'done' ? host.voices.say('This is how I sound now.') : undefined))
      .catch(() => undefined);
  };
  const hear = () => {
    const first = firstName(preferences.name);
    void host.voices
      .choose(chosen)
      .then(() => host.voices.say(`Hi ${first ?? 'there'}, I am Memnox. Press ${parts.words.talkKeysSaid} whenever you want me.`))
      .catch(() => undefined);
  };
  return (
    <SetupStep
      state={voiceStep(install)}
      title="Voice"
      detail={voiceDetail(install)}
      trailing={
        <>
          <VoicePicker voices={voices} chosen={chosen} pick={pick} />
          <KitButton onClick={hear} title="Hear it" aria-label="Hear it" className="px-3">
            <Play size={11} fill="currentColor" strokeWidth={2.4} />
          </KitButton>
        </>
      }
      hint={false}
      extra={
        install.kind === 'installing' ? (
          <div className="flex items-center gap-2">
            <Spinner />
            <QuietLine>
              Downloading the voice{install.percent === undefined ? '' : `, ${install.percent}%`}. Memnox speaks with your computer&rsquo;s own voice until it is in.
            </QuietLine>
          </div>
        ) : install.kind === 'failed' ? (
          <div className="flex flex-col items-start gap-2">
            <QuietLine>{install.why}</QuietLine>
            <KitButton onClick={() => void steps.installVoice()}>Try again</KitButton>
          </div>
        ) : install.kind === 'idle' ? (
          <KitButton onClick={() => void steps.installVoice()}>Download the voice</KitButton>
        ) : undefined
      }
    />
  );
}

/** `VoicePicker`: 220 by 28, radius 9, ink 6% with an 8% edge, the name 14 on the left and the chevron right. */
function VoicePicker({ voices, chosen, pick }: { voices: readonly string[]; chosen: string; pick: (id: string) => void }) {
  return (
    <label className="relative flex h-7 w-[220px] cursor-pointer items-center justify-between rounded-[9px] border border-ink-fill bg-ink-faint-fill px-3">
      <span className="truncate text-callout text-foreground">{voiceLabel(chosen)}</span>
      <ChevronsUpDown size={10} strokeWidth={2.5} className="shrink-0 text-muted" />
      <select className="absolute inset-0 cursor-pointer opacity-0" value={chosen} onChange={(event) => pick(event.target.value)} aria-label="Voice">
        {(voices.length > 0 ? voices : [chosen]).map((id) => (
          <option key={id} value={id}>
            {voiceLabel(id)}
          </option>
        ))}
      </select>
    </label>
  );
}

/** One switch on the Listening page, by the key the voice reads. */
function VoiceSwitch({ parts, name, icon, title, caption, disabled }: { parts: SettingsParts; name: keyof VoiceChoices; icon: typeof Ear; title: string; caption: string; disabled?: boolean }) {
  useObserved(parts.voice);
  return <SwitchRow icon={icon} title={title} caption={caption} on={parts.voice.choices[name]} onChange={(on) => parts.voice.set(name, on)} disabled={disabled} />;
}

/** The Listening page: hearing the person, then speaking to them, every row a switch. */
export function ListeningPage({ parts }: { parts: SettingsParts }) {
  usePreferences();
  return (
    <>
      <SettingsCard title="Hearing you">
        <VoiceSwitch parts={parts} name="wake" icon={Ear} title={'Wake when I say “Memnox”'} caption="On this computer only" />
        <SettingsDivider />
        <VoiceSwitch parts={parts} name="talkOver" icon={MicVocal} title="Talk over it" caption="Cut in just by speaking" />
        <SettingsDivider />
        <VoiceSwitch parts={parts} name="liveWords" icon={MessageSquareText} title="Live words" caption="See what you say in the island" />
      </SettingsCard>
      <SettingsCard title="Speaking to you">
        <VoiceSwitch parts={parts} name="muted" icon={VolumeX} title="Mute the voice" caption="Answers still show in the island" />
        <SettingsDivider />
        <VoiceSwitch parts={parts} name="speakUp" icon={Bell} title="Speak up on its own" caption="When work finishes or ships" />
        <SettingsDivider />
        <VoiceSwitch parts={parts} name="chimes" icon={Volume1} title="Sounds" caption="A chime when something happens" />
      </SettingsCard>
    </>
  );
}

/** The Dictation page: the three switches, the person's own words, and what was dictated lately. */
export function DictationPage({ parts }: { parts: SettingsParts }) {
  usePreferences();
  useObserved(parts.voice);
  const { voice, dictation, host } = parts;
  const [said, setSaid] = useState('');
  const [written, setWritten] = useState('');
  const [, copy] = useCopied(host.copy);
  const on = voice.choices.dictation;
  const words = dictation.words();
  const history = dictation.history();
  const add = () => {
    dictation.addWord(said, written);
    setSaid('');
    setWritten('');
  };
  return (
    <>
      <SettingsSection title="Dictate">
        <SettingsCard>
          <VoiceSwitch parts={parts} name="dictation" icon={Keyboard} title="Dictate anywhere" caption="Hold the right Alt key and speak, or tap it twice to keep going hands free." />
          <SettingsDivider />
          <VoiceSwitch parts={parts} name="typesLive" icon={TextCursorInput} title="Type as I speak" caption="Words appear at the cursor while you talk, and are tidied once you finish." disabled={!on} />
          <SettingsDivider />
          <VoiceSwitch
            parts={parts}
            name="polish"
            icon={Sparkles}
            title="Polish with Claude Code"
            caption="Your own Claude Code tidies false starts and layout, and lets you edit selected text by voice. Off, Memnox tidies it alone."
            disabled={!on}
          />
        </SettingsCard>
      </SettingsSection>
      <SettingsSection title="Your words">
        <Surface className="py-1">
          <div className="flex items-center gap-1.5 px-4 py-3">
            <KitField value={said} placeholder="When I say (optional)" width={200} onChange={setSaid} onSubmit={add} />
            <KitField value={written} placeholder="Write it as" className="flex-1" onChange={setWritten} onSubmit={add} />
            <KitButton kind="primary" disabled={written.trim() === ''} onClick={add}>
              Add
            </KitButton>
          </div>
          {words.length === 0 ? (
            <p className="px-4 pb-3 text-footnote text-muted">
              Names and words Memnox should spell your way, such as a teammate&rsquo;s name or ORB. Fixes you make right after dictating are learned here too.
            </p>
          ) : (
            words.map((word) => (
              <Fragment key={`${word.said ?? ''}:${word.written}`}>
                <div className="ml-[41px] h-px bg-ink-rim" />
                <div className="flex items-center gap-1.5 px-4 py-2 text-callout">
                  {word.said !== undefined && (
                    <>
                      <span className="text-ink-secondary">{word.said}</span>
                      <ArrowRight size={13} className="text-ink-tertiary" />
                    </>
                  )}
                  <span className="flex-1 text-ink">{word.written}</span>
                  <button type="button" className="grid cursor-pointer text-muted hover:text-foreground" title="Remove" aria-label="Remove" onClick={() => dictation.removeWord(word)}>
                    <CircleMinus size={15} />
                  </button>
                </div>
              </Fragment>
            ))
          )}
        </Surface>
      </SettingsSection>
      <SettingsSection title="Lately">
        <Surface className="py-1">
          {history.length === 0 ? (
            <p className="px-4 py-3 text-body text-muted">What you dictate shows here, so a dictation that went nowhere can be copied again.</p>
          ) : (
            <>
              {history.map((entry, index) => (
                <Fragment key={entry.at}>
                  {index > 0 && <div className="ml-[41px] h-px bg-ink-rim" />}
                  <div className="flex items-center gap-3 px-4 py-3">
                    <div className="flex min-w-0 flex-1 flex-col gap-0.5">
                      <span className="line-clamp-3 select-text text-callout text-ink">{entry.written}</span>
                      <span className="text-caption text-ink-tertiary">
                        {entry.app ?? 'An app'}, {new Date(entry.at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}
                      </span>
                    </div>
                    <KitButton onClick={() => copy(entry.written)}>Copy</KitButton>
                  </div>
                </Fragment>
              ))}
              <div className="ml-[41px] h-px bg-ink-rim" />
              <div className="flex justify-end px-4 py-3">
                <KitButton onClick={() => dictation.clearHistory()}>Clear history</KitButton>
              </div>
            </>
          )}
        </Surface>
      </SettingsSection>
    </>
  );
}
