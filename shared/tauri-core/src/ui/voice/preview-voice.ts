import { Mouth, VoicePreferences, VoiceTurns, type Ear, type EarEvent, type Speaker, type Talking, type Timer } from '../../core';
import { loudness } from '../island/loudness';

/** The voice's preview scenes, each driving the real turns over a scripted ear, typist and keys. */
export const VOICE_SCENES = ['voice-listening', 'voice-speaking', 'voice-rule', 'voice-rule-words', 'voice-dictating', 'voice-dictating-words', 'voice-phone', 'voice-phone-done'] as const;
export type VoiceScene = (typeof VOICE_SCENES)[number];

export function isVoiceScene(scene: string | undefined): scene is VoiceScene {
  return (VOICE_SCENES as readonly string[]).includes(scene ?? '');
}

/** An ear that says its script once and then stays open, so a scene holds still to be looked at. */
function scriptedEar(script: readonly EarEvent[]): Ear {
  return {
    async open(onEvent) {
      script.forEach((event, index) => setTimeout(() => onEvent(event), 250 + index * 220));
    },
    async close() {
      return undefined;
    },
  };
}

const words = (...steps: string[]): EarEvent[] => [{ kind: 'speech' }, ...steps.map((text): EarEvent => ({ kind: 'words', text, final: false }))];

const memory = new Map<string, string>();
const store = { load: (key: string) => memory.get(key) ?? null, save: (key: string, value: string) => void memory.set(key, value) };

/**
 * The turns for a voice scene, already pressed or spoken to: listening with words arriving, a rule held
 * down, dictation held down into Slack, or a paired phone's turn mirrored with its answer.
 */
export function previewVoice(scene: VoiceScene, talking: Talking, speaker: Speaker): VoiceTurns {
  const timer: Timer = (ms, fire) => {
    const handle = setTimeout(fire, ms);
    return () => clearTimeout(handle);
  };
  const script: Record<VoiceScene, EarEvent[]> = {
    'voice-listening': words('push the', 'push the fix to main', 'push the fix to main and tell the team'),
    'voice-speaking': [],
    'voice-rule': [],
    'voice-rule-words': words('never let an agent', 'never let an agent push to main without asking me'),
    'voice-dictating': [],
    'voice-dictating-words': words('the island now', 'the island now matches the Mac on Windows and Linux'),
    'voice-phone': [],
    'voice-phone-done': [],
  };
  const preferences = new VoicePreferences(store);
  preferences.set('typesLive', false);
  const voice = new VoiceTurns({
    talking,
    mouth: new Mouth(speaker, preferences),
    ear: scriptedEar(script[scene]),
    preferences,
    timer,
    typist: { focus: async () => ({ app: 'slack', secure: false }), type: async () => undefined, revise: async () => undefined, copy: async () => undefined },
    ready: () => true,
  });
  const none = { ctrl: false, leftAlt: false, rightAlt: false, shift: false, meta: false };
  switch (scene) {
    case 'voice-listening':
      voice.talk();
      break;
    case 'voice-speaking': {
      // Kokoro's level as it says a sentence: syllables a fifth of a second apart, so the orb throws rings.
      const started = performance.now();
      setInterval(() => {
        const t = (performance.now() - started) / 1_000;
        loudness.voice(Math.max(0, 0.35 + 0.45 * Math.sin(t * 2 * Math.PI * 4.5) * Math.abs(Math.sin(t * 1.3))));
      }, 33);
      break;
    }
    case 'voice-rule':
    case 'voice-rule-words':
      voice.keys({ kind: 'modifiers', ...none, ctrl: true, leftAlt: true });
      break;
    case 'voice-dictating':
    case 'voice-dictating-words':
      voice.keys({ kind: 'modifiers', ...none, rightAlt: true });
      break;
    case 'voice-phone':
    case 'voice-phone-done': {
      const phone = { deviceId: 'dev_1', name: "Ana's iPhone" };
      const at = new Date().toISOString();
      const notice = (turn: object) => voice.arrived({ kind: 'notice', subject: 'ask_1', agent: 'memnox', summary: 'A phone turn', at, phoneTurn: { ...phone, ...turn } });
      notice({ said: 'What did Codex change in the island since this morning?' });
      notice({
        answer:
          'Codex moved the island onto the kit and fixed the held call card.\n\n- **Island.tsx**: the satellites slide out a beat apart\n- **Cards.tsx**: the queue chevrons press as the Mac does\n\nEvery test passes.',
      });
      if (scene === 'voice-phone-done') notice({ ended: true });
      break;
    }
  }
  return voice;
}
