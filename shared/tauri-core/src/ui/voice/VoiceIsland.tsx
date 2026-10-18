import { useEffect, useState, useSyncExternalStore } from 'react';
import type { VoicePreferences, VoiceTurns } from '../../core';
import { Island, type IslandParts } from '../Island';
import { keysWatching } from './tauri-voice';

/** The launcher's seams the voice fills, read loosely so the island's own launcher type stays its own. */
interface LauncherSeams {
  readonly launcher?: { readonly actions?: object; readonly facts?: object };
}

/**
 * The island with the voice's own switches wired in: the mute satellite and tile show and flip the one
 * mute the whole app shares, the words keep showing while it is on since muting loses nothing but the
 * sound, and Say a rule teaches the keys, or says why this desktop will not let them be seen.
 */
export function VoiceIsland({ preferences, voice, ...rest }: IslandParts & LauncherSeams & { preferences: VoicePreferences; voice: VoiceTurns }) {
  const parts = rest as IslandParts & LauncherSeams;
  const choices = useSyncExternalStore(
    (changed) => preferences.observe(changed),
    () => preferences.choices,
  );
  const [keysSeen, setKeysSeen] = useState(true);
  useEffect(() => {
    void keysWatching().then((answer) => setKeysSeen(answer.watching));
  }, []);
  const toggle = () => preferences.toggle('muted');
  const launcher = {
    ...parts.launcher,
    actions: { sayRule: () => voice.sayRule(keysSeen), mute: toggle, ...parts.launcher?.actions },
    facts: { muted: choices.muted, ...parts.launcher?.facts },
  };
  return <Island {...parts} {...({ launcher } as object)} voice={voice} liveWords={choices.liveWords} mute={{ on: choices.muted, toggle }} />;
}
