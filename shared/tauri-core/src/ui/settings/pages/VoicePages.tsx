import { AppWindow, ArrowRight, AudioWaveform, Bell, CircleMinus, Ear, Gauge, History, Keyboard, MessageSquareText, MicVocal, Play, Sparkles, TextCursorInput, Volume1, VolumeX } from 'lucide-react';
import { Fragment, useEffect, useState } from 'react';
import type { VoiceChoices } from '../../../core/application/voice-preferences';
import type { Platform } from '../../../core/domain/platform';
import { DICTATION_KEY_WORDS, type DictationKeyName } from '../../../core/domain/voice-keys';
import { AgentCheckText } from '../../../core/domain/agent-check-text';
import { firstName, voiceDetail, voiceStep } from '../../../core/domain/setup-steps';
import { AgentLogos, BrandLogo } from '../../kit/logos';
import { QuietLine, SettingsCard, SettingsDivider, SettingsRow, SettingsSection, Surface, SwitchRow, useCopied } from '../kit';
import { useObserved, usePreferences, type SettingsParts } from '../parts';
import { SetupDivider, SetupStep } from '../steps';
import { Button, Input, Pressable, Select, Spinner } from '../../kit';
import { OverviewLines } from '../../../core/domain/overview-lines';
import { VoiceLines } from '../../../core/domain/voice-page-lines';

/** `VoicePicker` is 220 wide and the small pop ups 140, as the Mac sizes them. */
const VOICE_PICKER_WIDTH = 220;
const SMALL_PICKER_WIDTH = 140;
/** The "When I say" field, wide enough for a name and no wider. */
const SAID_FIELD_WIDTH = 200;
/** The voice a first run starts on, the natural voice's default. */
const FIRST_VOICE = 'af_sky';
/** The Mac's unhurried pace, between half speed and normal. */
const UNHURRIED = 0.85;
/** An agent's logo in its row, and those not installed yet, smaller in a line. */
const AGENT_LOGO = 24;
const ABSENT_LOGO = 14;
/** Hear it's play mark, and the glyphs beside a learned word. */
const PLAY_GLYPH = 11;
const PLAY_GLYPH_STROKE = 2.4;
const WORD_ARROW = 13;
const REMOVE_GLYPH = 15;

/** "af_sky" as "Sky", with who it sounds like, as the Mac's voice menu names them. */
const VOICE_PEOPLE: Record<string, string> = {
  af: 'American Female',
  am: 'American Male',
  bf: 'British Female',
  bm: 'British Male',
};

/** The computer's own voice, as the Mac's picker names its own "Mac voice". */
export const SYSTEM_VOICE = 'system';
const SYSTEM_VOICE_LABEL: Record<Platform, string> = { windows: VoiceLines.windowsVoice, linux: VoiceLines.systemVoice, other: VoiceLines.systemVoice };

export function voiceLabel(id: string, platform: Platform = 'other'): string {
  if (id === SYSTEM_VOICE) return SYSTEM_VOICE_LABEL[platform];
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
  const absent = steps.agents.filter((agent) => !agent.installed);
  const missing = absent.map((agent) => agent.label);
  return (
    <SetupStep
      state={state}
      title={VoiceLines.whoAnswers}
      detail={steps.agentsDetail}
      trailing={done ? <Button onClick={() => setShown(!shown)}>{shown ? VoiceLines.hideAgents : VoiceLines.showAgents}</Button> : undefined}
      extra={
        !done || shown ? (
          <div className="flex flex-col gap-2">
            {installed.map((agent) => (
              <div key={agent.kind} className="flex items-center gap-2">
                <BrandLogo agent={agent.kind} name={agent.label} size={AGENT_LOGO} />
                <span className="w-settings-agent-label shrink-0 truncate text-caption font-semibold text-foreground">{agent.label}</span>
                <span className={`min-w-0 flex-1 truncate text-caption ${agent.works === false ? 'text-ink-primary' : 'text-ink-secondary'}`} title={AgentCheckText.status(agent, steps.checkingAgents)}>
                  {AgentCheckText.status(agent, steps.checkingAgents)}
                </span>
                {agent.chosen ? (
                  <span className="text-caption font-semibold text-green">{VoiceLines.inUse}</span>
                ) : (
                  <Button disabled={agent.works === false} onClick={() => void steps.useAgent(agent.kind)}>
                    {VoiceLines.use}
                  </Button>
                )}
              </div>
            ))}
            {missing.length > 0 && (
              <p className="flex items-center gap-1.5 text-caption text-muted">
                <AgentLogos agents={absent.map((agent) => ({ agent: agent.kind, name: agent.label }))} size={ABSENT_LOGO} />
                <span>{VoiceLines.alsoAnswers(AgentCheckText.names(missing))}</span>
              </p>
            )}
            <div className="flex items-center gap-2">
              <Button disabled={steps.checkingAgents} onClick={() => void steps.loadAgents(true)}>
                {VoiceLines.checkAgain}
              </Button>
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
  const [chosen, setChosen] = useState<string>(FIRST_VOICE);
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
      .then(() => (install.kind === 'done' ? host.voices.say(VoiceLines.soundsNow) : undefined))
      .catch(() => undefined);
  };
  const hear = () => {
    const first = firstName(preferences.name);
    void host.voices
      .choose(chosen)
      .then(() => host.voices.say(OverviewLines.hello(first, parts.words.talkKeysSaid)))
      .catch(() => undefined);
  };
  return (
    <SetupStep
      state={voiceStep(install)}
      title={VoiceLines.voice}
      detail={voiceDetail(install)}
      trailing={
        <>
          <Select
            look="popup"
            width={VOICE_PICKER_WIDTH}
            label={VoiceLines.voice}
            value={chosen}
            options={(voices.length > 0 ? voices : [chosen]).map((id) => ({ value: id, label: voiceLabel(id, host.platform) }))}
            onChange={pick}
          />
          <Button onClick={hear} title={VoiceLines.hear} aria-label={VoiceLines.hear}>
            <Play size={PLAY_GLYPH} fill="currentColor" strokeWidth={PLAY_GLYPH_STROKE} />
          </Button>
        </>
      }
      hint={false}
      extra={
        install.kind === 'installing' ? (
          <div className="flex items-center gap-2">
            <Spinner />
            <QuietLine>{VoiceLines.downloading(install.percent)}</QuietLine>
          </div>
        ) : install.kind === 'failed' ? (
          <div className="flex flex-col items-start gap-2">
            <QuietLine>{install.why}</QuietLine>
            <div className="flex items-center gap-2">
              <Button onClick={() => void steps.installVoice()}>{VoiceLines.tryAgain}</Button>
              {voices.includes(SYSTEM_VOICE) && chosen !== SYSTEM_VOICE && (
                <Button onClick={() => pick(SYSTEM_VOICE)}>{VoiceLines.useInstead(voiceLabel(SYSTEM_VOICE, host.platform))}</Button>
              )}
            </div>
          </div>
        ) : install.kind === 'idle' ? (
          <Button onClick={() => void steps.installVoice()}>{VoiceLines.download}</Button>
        ) : undefined
      }
    />
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
      <SettingsCard title={VoiceLines.hearing}>
        <VoiceSwitch parts={parts} name="wake" icon={Ear} title={VoiceLines.wake} caption={VoiceLines.wakeCaption} />
        <SettingsDivider />
        <VoiceSwitch parts={parts} name="talkOver" icon={MicVocal} title={VoiceLines.talkOver} caption={VoiceLines.talkOverCaption} />
        <SettingsDivider />
        <VoiceSwitch parts={parts} name="liveWords" icon={MessageSquareText} title={VoiceLines.liveWords} caption={VoiceLines.liveWordsCaption} />
        <SettingsDivider />
        <VoiceSwitch parts={parts} name="stayPut" icon={AppWindow} title={VoiceLines.stayPut} caption={VoiceLines.stayPutCaption} />
        <SettingsDivider />
        <VoiceSwitch parts={parts} name="echoCancel" icon={AudioWaveform} title={VoiceLines.echoCancel} caption={VoiceLines.echoCancelCaption} />
      </SettingsCard>
      <SettingsCard title={VoiceLines.speaking}>
        <VoiceSwitch parts={parts} name="muted" icon={VolumeX} title={VoiceLines.mute} caption={VoiceLines.muteCaption} />
        <SettingsDivider />
        <VoiceSwitch parts={parts} name="speakUp" icon={Bell} title={VoiceLines.speakUp} caption={VoiceLines.speakUpCaption} />
        <SettingsDivider />
        <VoiceSwitch parts={parts} name="chimes" icon={Volume1} title={VoiceLines.sounds} caption={VoiceLines.soundsCaption} />
        <SettingsDivider />
        <VoiceSwitch parts={parts} name="catchUp" icon={History} title={VoiceLines.catchUp} caption={VoiceLines.catchUpCaption} />
        <SettingsDivider />
        <SpeedRow parts={parts} />
      </SettingsCard>
    </>
  );
}

/** The speeds on offer, the Mac's unhurried pace in the middle, held between half speed and normal as it holds them. */
const SPEEDS: readonly { readonly speed: number; readonly label: string }[] = [
  { speed: 0.7, label: VoiceLines.slower },
  { speed: UNHURRIED, label: VoiceLines.unhurried },
  { speed: 1, label: VoiceLines.normal },
];

/** How fast the voice speaks, kept by Rust beside the chosen voice and heard on the next sentence. */
function SpeedRow({ parts }: { parts: SettingsParts }) {
  const { host } = parts;
  const [speed, setSpeed] = useState(UNHURRIED);
  useEffect(() => {
    host.voices.choice().then(
      (choice) => choice.speed !== undefined && setSpeed(choice.speed),
      () => undefined,
    );
  }, []);
  const pick = (next: number) => {
    setSpeed(next);
    void host.voices
      .setSpeed(next)
      .then(() => host.voices.say(VoiceLines.speedNow))
      .catch(() => undefined);
  };
  const nearest = SPEEDS.reduce((best, each) => (Math.abs(each.speed - speed) < Math.abs(best.speed - speed) ? each : best));
  return (
    <SettingsRow icon={Gauge} title={VoiceLines.speed} caption={VoiceLines.speedCaption}>
      <Select look="popup" width={SMALL_PICKER_WIDTH} label={VoiceLines.speed} value={String(nearest.speed)} options={SPEEDS.map((each) => ({ value: String(each.speed), label: each.label }))} onChange={(value) => pick(Number(value))} />
    </SettingsRow>
  );
}

/** Which key dictates; right Alt is AltGr on most European layouts, so right Ctrl is offered and is their default. */
function DictationKeyRow({ parts }: { parts: SettingsParts }) {
  useObserved(parts.voice);
  const key = parts.voice.dictationKey;
  const keys = Object.entries(DICTATION_KEY_WORDS) as [DictationKeyName, string][];
  return (
    <SettingsRow icon={Keyboard} title={VoiceLines.dictationKey} caption={VoiceLines.dictationKeyCaption}>
      <Select look="popup" width={SMALL_PICKER_WIDTH} label={VoiceLines.dictationKey} value={key} options={keys.map(([value, label]) => ({ value, label }))} onChange={(value) => parts.voice.pickDictationKey(value as DictationKeyName)} />
    </SettingsRow>
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
      <SettingsSection title={VoiceLines.dictate}>
        <SettingsCard>
          <VoiceSwitch
            parts={parts}
            name="dictation"
            icon={Keyboard}
            title={VoiceLines.dictateAnywhere}
            caption={VoiceLines.dictateCaption(DICTATION_KEY_WORDS[voice.dictationKey])}
          />
          <SettingsDivider />
          <DictationKeyRow parts={parts} />
          <SettingsDivider />
          <VoiceSwitch parts={parts} name="typesLive" icon={TextCursorInput} title={VoiceLines.typesLive} caption={VoiceLines.typesLiveCaption} disabled={!on} />
          <SettingsDivider />
          <VoiceSwitch
            parts={parts}
            name="polish"
            icon={Sparkles}
            title={VoiceLines.polish}
            caption={VoiceLines.polishCaption}
            disabled={!on}
          />
        </SettingsCard>
      </SettingsSection>
      <SettingsSection title={VoiceLines.yourWords}>
        <Surface className="py-1">
          <div className="flex items-center gap-1.5 px-4 py-3">
            <Input value={said} placeholder={VoiceLines.whenISay} width={SAID_FIELD_WIDTH} onValue={setSaid} onSubmit={add} />
            <Input value={written} placeholder={VoiceLines.writeAs} className="flex-1" onValue={setWritten} onSubmit={add} />
            <Button kind="primary" disabled={written.trim() === ''} onClick={add}>
              {VoiceLines.add}
            </Button>
          </div>
          {words.length === 0 ? (
            <p className="px-4 pb-3 text-footnote text-muted">{VoiceLines.noWords}</p>
          ) : (
            words.map((word) => (
              <Fragment key={`${word.said ?? ''}:${word.written}`}>
                <div className="ml-settings-menu-divider h-px bg-ink-rim" />
                <div className="flex items-center gap-1.5 px-4 py-2 text-callout">
                  {word.said !== undefined && (
                    <>
                      <span className="text-ink-secondary">{word.said}</span>
                      <ArrowRight size={WORD_ARROW} className="text-ink-tertiary" />
                    </>
                  )}
                  <span className="flex-1 text-ink">{word.written}</span>
                  <Pressable className="grid cursor-pointer text-muted hover:text-foreground" title={VoiceLines.remove} aria-label={VoiceLines.remove} onClick={() => dictation.removeWord(word)}>
                    <CircleMinus size={REMOVE_GLYPH} />
                  </Pressable>
                </div>
              </Fragment>
            ))
          )}
        </Surface>
      </SettingsSection>
      <SettingsSection title={VoiceLines.lately}>
        <Surface className="py-1">
          {history.length === 0 ? (
            <p className="px-4 py-3 text-body text-muted">{VoiceLines.noHistory}</p>
          ) : (
            <>
              {history.map((entry, index) => (
                <Fragment key={entry.at}>
                  {index > 0 && <div className="ml-settings-menu-divider h-px bg-ink-rim" />}
                  <div className="flex items-center gap-3 px-4 py-3">
                    <div className="flex min-w-0 flex-1 flex-col gap-0.5">
                      <span className="line-clamp-3 select-text text-callout text-ink">{entry.written}</span>
                      <span className="text-caption text-ink-tertiary">
                        {entry.app ?? VoiceLines.anApp}, {new Date(entry.at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}
                      </span>
                    </div>
                    <Button onClick={() => copy(entry.written)}>{VoiceLines.copy}</Button>
                  </div>
                </Fragment>
              ))}
              <div className="ml-settings-menu-divider h-px bg-ink-rim" />
              <div className="flex justify-end px-4 py-3">
                <Button onClick={() => dictation.clearHistory()}>{VoiceLines.clearHistory}</Button>
              </div>
            </>
          )}
        </Surface>
      </SettingsSection>
    </>
  );
}
